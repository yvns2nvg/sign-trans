"""M0: Swift 이식을 검증할 Python 기준 데이터를 만든다.

    PYTHONDONTWRITEBYTECODE=1 tools/.venv/bin/python tools/make_fixtures.py

- adapter.json   : 가짜 MediaPipe 랜드마크 → holistic_result_to_frame89
- featurize.json : 실제 클립 + 경계 케이스 → featurize
- stream.json    : realtime.py 의 auto 모드 프레임 루프를 그대로 재현한 결과
"""
from __future__ import annotations

import json
from types import SimpleNamespace

import numpy as np

from kslx_ref import NPZ_PATH, ROOT
from kslx.adapters.mediapipe_adapter import holistic_result_to_frame89
from kslx.layout import RHAND_SLICE
from kslx.normalize import featurize
from kslx.sentence import SentenceBuilder
from kslx.stream import LiveNormalizer, OneEuroFilter, SegmentGate, hand_energy

FIX = ROOT / "fixtures"
DT = 1.0 / 30.0


def load_clips():
    z = np.load(NPZ_PATH, allow_pickle=True)
    flat, off = z["flat"], z["offsets"]
    clips = [flat[off[i]:off[i + 1], :, :2].astype(np.float32) for i in range(len(off) - 1)]
    return clips, z


def _lm(arr):
    return [SimpleNamespace(x=float(x), y=float(y)) for x, y in arr]


def adapter_cases():
    rng = np.random.default_rng(0)
    W, H = 1080, 1920
    cases = []
    for name, keep in [("all", (1, 1, 1, 1)), ("no_left_hand", (1, 0, 1, 1)),
                       ("no_face", (1, 1, 1, 0)), ("nothing", (0, 0, 0, 0))]:
        parts = {"pose": rng.random((33, 2)), "left_hand": rng.random((21, 2)),
                 "right_hand": rng.random((21, 2)), "face": rng.random((478, 2))}
        kept = dict(zip(parts, keep))
        res = SimpleNamespace(**{f"{k}_landmarks": (_lm(v) if kept[k] else [])
                                 for k, v in parts.items()})
        for use_face in (True, False):
            exp = holistic_result_to_frame89(res, W, H, use_face=use_face)
            cases.append({"name": f"{name}_face{int(use_face)}", "width": W, "height": H,
                          "use_face": use_face,
                          **{k: (v.tolist() if kept[k] else None) for k, v in parts.items()},
                          "expected": exp.tolist()})
    return cases


def featurize_cases(clips):
    cases = [{"name": f"clip{i}", "raw": clips[i].tolist(),
              "expected": featurize(clips[i]).tolist()} for i in (0, 100, 300, 600, 1000)]
    c = clips[0].copy()
    c[5:9, 2] = 0.0   # 오른 어깨
    c[5:9, 5] = 0.0   # 왼 어깨 → 클립 중앙값 스케일로 대체되는 경로
    cases.append({"name": "shoulders_missing", "raw": c.tolist(), "expected": featurize(c).tolist()})
    z = np.zeros((10, 89, 2), np.float32)
    cases.append({"name": "all_zero", "raw": z.tolist(), "expected": featurize(z).tolist()})
    one = clips[0][:1]
    cases.append({"name": "single_frame", "raw": one.tolist(), "expected": featurize(one).tolist()})
    return cases


def stream_case(clips):
    # 끝에 2초 정지(마지막 프레임 반복)를 붙여 문장 완성(45프레임 idle)이 일어나게 한다
    hold = np.repeat(clips[300][-1:], 60, axis=0)
    frames = np.concatenate([np.zeros((5, 89, 2), np.float32)] +
                            [clips[i] for i in (0, 100, 300)] + [hold]).copy()
    s = 5 + len(clips[0]) + 10
    frames[s:s + 8, RHAND_SLICE] = 0.0   # 수어 도중 오른손 미검출
    smoother, live, gate = OneEuroFilter(), LiveNormalizer(), SegmentGate()
    builder = SentenceBuilder()
    prev = None
    out = {"dt": DT, "frames": frames.tolist(), "smoothed": [], "norm": [],
           "energy": [], "label": [], "segments": [],
           "sentence_end_frames": []}
    for t, f in enumerate(frames):
        sm = smoother(f, DT)
        n = live.normalize(sm)
        e = hand_energy(prev, n) if (prev is not None and n is not None) else 0.0
        if n is not None:
            prev = n
        label, buf = gate.step(sm, e)
        out["smoothed"].append(np.asarray(sm).tolist())
        out["norm"].append(None if n is None else n.tolist())
        out["energy"].append(float(e))
        out["label"].append(label)
        if label == "finished" and buf is not None and len(buf) >= 4:
            out["segments"].append({"end_frame": t, "length": len(buf),
                                    "features": featurize(np.stack(buf)).tolist()})
            builder.on_word("사과")          # 분류 결과와 무관하게 '단어 하나'로 센다
        # realtime.py: 게이트가 대기 상태인 프레임마다 문장 완성 여부를 센다
        if gate.state == "idle" and builder.tick_idle():
            builder.finalize()
            out["sentence_end_frames"].append(t)
    assert out["segments"], "세그먼트가 하나도 안 나왔다 — 클립 선택을 바꿀 것"
    return out


def _dump(name, obj):
    FIX.mkdir(exist_ok=True)
    with open(FIX / name, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"wrote fixtures/{name} ({(FIX / name).stat().st_size / 1e6:.1f} MB)")


def main():
    clips, _ = load_clips()
    _dump("adapter.json", {"cases": adapter_cases()})
    _dump("featurize.json", {"t_out": 64, "cases": featurize_cases(clips)})
    st = stream_case(clips)
    print(f"stream: {len(st['label'])} frames, {len(st['segments'])} segments, "
          f"norm None {sum(n is None for n in st['norm'])} frames")
    _dump("stream.json", st)


if __name__ == "__main__":
    main()
