"""M1: PyTorch 와 ONNX Runtime 출력이 같은지 검사한다.

통과 조건(PRD S11): 1순위 100% 일치, logit 최대 절대오차 < 1e-3.
"""
from __future__ import annotations

import json
import sys
import time

import numpy as np
import onnxruntime as ort
import torch

from kslx_ref import ROOT
from export_onnx import ONNX_PATH, load_torch_model
from make_fixtures import load_clips
from kslx.normalize import featurize


def main() -> int:
    if not ONNX_PATH.exists():
        print(f"FAIL: {ONNX_PATH} 없음 — export_onnx.py 먼저 실행")
        return 1
    model, _ = load_torch_model()
    sess = ort.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])
    clips, z = load_clips()
    idx = np.linspace(0, len(clips) - 1, 200).astype(int)
    mismatch, maxdiff, saved = 0, 0.0, []
    for k, i in enumerate(idx):
        s, e = int(z["sign_start"][i]), int(z["sign_end"][i])
        feat = featurize(clips[i], sign_span=(s, e) if e > s else None)[None]
        with torch.no_grad():
            pt = model(torch.from_numpy(feat)).numpy()[0]
        ox = sess.run(["logits"], {"features": feat})[0][0]
        maxdiff = max(maxdiff, float(np.abs(pt - ox).max()))
        mismatch += int(pt.argmax() != ox.argmax())
        if k < 20:
            saved.append({"features": feat[0].tolist(), "logits": pt.tolist(), "top1": int(pt.argmax())})
    x = np.zeros((1, 64, 356), np.float32)
    t0 = time.perf_counter()
    for _ in range(100):
        sess.run(["logits"], {"features": x})
    ms = (time.perf_counter() - t0) * 10
    with open(ROOT / "fixtures/model_io.json", "w", encoding="utf-8") as fh:
        json.dump({"cases": saved}, fh, separators=(",", ":"))
    print(f"top1 mismatch {mismatch}/200, max |dlogit| {maxdiff:.2e}, PC ORT {ms:.2f} ms/회")
    return 0 if mismatch == 0 and maxdiff < 1e-3 else 1


if __name__ == "__main__":
    sys.exit(main())
