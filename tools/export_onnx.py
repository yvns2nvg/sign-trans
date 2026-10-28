"""M1: signer_out_c1200_aug.pt → models/sign_c1200.onnx + models/labels.json"""
from __future__ import annotations

import json

import onnx
import torch

from kslx_ref import KSLX_REPO, ROOT
from kslx.data.aihub import word_label_map
from kslx.train import build_model

CKPT_PATH = KSLX_REPO / "runs/signer_out_c1200_aug.pt"
ONNX_PATH = ROOT / "SignCore/Sources/SignInference/Resources/sign_c1200.onnx"
LABELS_PATH = ROOT / "SignCore/Sources/SignInference/Resources/labels.json"


def load_torch_model():
    ckpt = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)
    assert ckpt["num_classes"] == 1200 and ckpt["feature_dim"] == 356, "체크포인트가 다르다"
    model = build_model(ckpt.get("model", "conv_transformer"), ckpt["feature_dim"], ckpt["num_classes"])
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    return model, ckpt


def main():
    # eval 모드 TransformerEncoder 의 fused fast path 연산은 ONNX 로 못 내보낼 수 있어 끈다.
    torch.backends.mha.set_fastpath_enabled(False)
    model, ckpt = load_torch_model()
    ONNX_PATH.parent.mkdir(exist_ok=True)
    dummy = torch.zeros(1, 64, 356)
    try:
        torch.onnx.export(model, (dummy,), str(ONNX_PATH), input_names=["features"],
                          output_names=["logits"], dynamo=True)
    except Exception as e:   # dynamo exporter 실패 시 TorchScript exporter 로 재시도
        print(f"dynamo export 실패, legacy 로 재시도: {e!r}")
        torch.onnx.export(model, (dummy,), str(ONNX_PATH), input_names=["features"],
                          output_names=["logits"], dynamo=False, opset_version=17)
    # 가중치가 .onnx.data 로 따로 저장되면 앱 번들에 두 파일을 같이 넣어야 한다. 한 파일로 합친다.
    data_path = ONNX_PATH.with_name(ONNX_PATH.name + ".data")
    onnx.save(onnx.load(str(ONNX_PATH)), str(ONNX_PATH), save_as_external_data=False)
    data_path.unlink(missing_ok=True)
    labels = word_label_map()
    glosses = [labels[int(c)] for c in ckpt["classes"]]
    with open(LABELS_PATH, "w", encoding="utf-8") as fh:
        json.dump(glosses, fh, ensure_ascii=False)
    print(f"wrote {ONNX_PATH.name} ({ONNX_PATH.stat().st_size / 1e6:.1f} MB), {len(glosses)} labels")


if __name__ == "__main__":
    main()
