"""M3: kslx/sentence.py 를 앱에서 kiwi 없이 재현하기 위한 표를 만든다.

인식 어휘가 닫혀 있으므로(1200단어) kiwi 가 필요한 부분 — 단어별 품사 분석,
조사 이형태(받침), 용언 활용 — 을 단어마다 미리 계산해 둔다. 앱은 표를 찾아
보고 단위들을 공백으로 잇기만 한다. 그 '공백으로 잇기'가 kiwi.join 과 같은지는
이 스크립트의 미러 검사가 compose_sentence 와 직접 비교해서 확인한다.

    PYTHONDONTWRITEBYTECODE=1 tools/.venv/bin/python tools/make_sentence_tables.py
"""
from __future__ import annotations

import json
import random
import sys

from kslx_ref import KSLX_REPO, ROOT
from kslx import sentence as S
from kslx.eval_sentence import CASES, HELDOUT

STYLES = ("합쇼체", "해요체")
PARTICLES = [("은", "JX"), ("을", "JKO"), ("과", "JKB"), ("과", "JC"),
             ("에", "JKB"), ("에서", "JKB"), ("으로", "JKB"), ("이", "JKS")]
HADA_KIND = {"t": "trans", "m": "motion", "i": "intrans", "a": "adj"}
TABLES_PATH = ROOT / "SignCore/Sources/SignCore/Resources/sentence_tables.json"
CASES_PATH = ROOT / "fixtures/sentence_cases.json"


def key(style: str, past: bool) -> str:
    return f"{style}|{'past' if past else 'present'}"


def conj(stem) -> dict:
    kiwi = S._get_kiwi()
    return {key(st, p): kiwi.join(list(stem) + ([("었", "EP")] if p else []) + [S.STYLES[st]])
            for st in STYLES for p in (False, True)}


def copula(word: str, head_tag: str) -> dict:
    kiwi = S._get_kiwi()
    out = {}
    for st in STYLES:
        for p in (False, True):
            if st == "해요체" and not p:      # compose_sentence 의 '-이에요/-예요' 특별 처리와 같게
                last = word[-1]
                has_batchim = "가" <= last <= "힣" and (ord(last) - 0xAC00) % 28 != 0
                out[key(st, p)] = kiwi.join([(word, head_tag)]) + ("이에요" if has_batchim else "예요")
            else:
                out[key(st, p)] = kiwi.join([(word, head_tag), ("이", "VCP")]
                                            + ([("었", "EP")] if p else []) + [S.STYLES[st]])
    return out


def entry(g: str) -> dict:
    kiwi = S._get_kiwi()
    info = S._classify(g)
    e = {"role": info.role, "plain": kiwi.join([(t.form, t.tag) for t in info.toks])}
    if info.role == "predicate":
        e["predKind"] = S._predicate_kind(info)
        e["forms"] = conj(S._predicate_stem_toks(info))
    if info.role == "noun":
        e["headTag"] = info.head_tag
        e["nounClass"] = S._noun_class(g)
        e["bare"] = kiwi.join([(g, info.head_tag)])
        e["particles"] = {f"{f}/{t}": kiwi.join([(g, info.head_tag), (f, t)]) for f, t in PARTICLES}
        e["copula"] = copula(g, info.head_tag)
        if g in S.HADA:
            k = S.HADA[g]
            e["hadaKind"] = HADA_KIND[k]
            e["hadaForms"] = conj([(g, "NNG"), ("하", "XSA" if k == "a" else "XSV")])
    return e


def vocab() -> list[str]:
    words = []
    for line in (KSLX_REPO / "kslx/VOCAB_1200.txt").read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or ":" not in line:
            continue
        words.append(line.split(":", 1)[1].strip())
    assert len(words) == 1200, len(words)
    return words


def mirror(tables: dict, glosses: list[str], style: str) -> str:
    """Swift SentenceComposer 와 같은 알고리즘(표만 사용). 조사 선택은 S._particles 를 그대로 쓴다."""
    W = tables["words"]
    words = [g.strip() for g in glosses if g and g.strip()]
    past = any(w in tables["pastCues"] for w in words)
    if words and words[-1] == tables["pastMarker"]:
        words, past = words[:-1], True
    if not words:
        return ""
    infos = [W.get(w, {"role": "other", "plain": w}) for w in words]
    k = key(style, past)
    pred = next((i for i in range(len(infos) - 1, -1, -1) if infos[i]["role"] == "predicate"), None)
    if pred is not None:
        kind, form = infos[pred]["predKind"], infos[pred]["forms"][k]
    elif infos[-1]["role"] == "noun" and len(infos) > 1 and "hadaKind" in infos[-1]:
        pred, kind, form = len(infos) - 1, infos[-1]["hadaKind"], infos[-1]["hadaForms"][k]
    elif infos[-1]["role"] == "noun":
        pred, kind, form = len(infos) - 1, "copula", infos[-1]["copula"][k]
    else:
        return " ".join(words)
    noun_idx = [i for i in range(pred) if infos[i]["role"] == "noun"]
    parts = dict(zip(noun_idx, S._particles([words[i] for i in noun_idx], kind)))
    units = []
    for i in range(pred):
        if i in parts:
            p = parts[i]
            units.append(infos[i]["particles"][f"{p[0]}/{p[1]}"] if p else infos[i]["bare"])
        else:
            units.append(infos[i]["plain"])
    return " ".join([" ".join(units + [form])] + words[pred + 1:])


def main() -> int:
    v = vocab()
    eval_words = {w for g, _ in CASES + HELDOUT for w in g.split()}
    all_words = sorted(set(v) | eval_words)
    tables = {"pastCues": sorted(S.PAST_CUES), "pastMarker": S.PAST_MARKER,
              "timeE": sorted(S.TIME_E), "firstPerson": sorted(S.FIRST_PERSON),
              "words": {w: entry(w) for w in all_words}}
    TABLES_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(TABLES_PATH, "w", encoding="utf-8") as fh:
        json.dump(tables, fh, ensure_ascii=False, separators=(",", ":"))

    rng = random.Random(0)
    preds = [w for w in v if tables["words"][w]["role"] == "predicate"]
    combos = []
    for _ in range(500):
        ws = rng.sample(v, rng.randint(1, 3))
        if rng.random() < 0.7:
            ws.append(rng.choice(preds))
        combos.append(ws)

    cases, bad_eval, bad_random = [], [], 0
    sets = [("dev", [g.split() for g, _ in CASES]), ("heldout", [g.split() for g, _ in HELDOUT]),
            ("random", combos)]
    for name, items in sets:
        for ws in items:
            for st in STYLES:
                truth = S.compose_sentence(ws, st)
                ok = mirror(tables, ws, st) == truth
                cases.append({"set": name, "glosses": ws, "style": st,
                              "expected": truth, "mirrorMatches": ok})
                if not ok:
                    if name == "random":
                        bad_random += 1
                    else:
                        bad_eval.append((ws, st, truth, mirror(tables, ws, st)))
    with open(CASES_PATH, "w", encoding="utf-8") as fh:
        json.dump({"cases": cases}, fh, ensure_ascii=False, separators=(",", ":"))

    n_eval = 2 * (len(CASES) + len(HELDOUT))
    print(f"words {len(all_words)}, tables {TABLES_PATH.stat().st_size / 1e6:.2f} MB")
    print(f"mirror == compose_sentence: eval {n_eval - len(bad_eval)}/{n_eval}, "
          f"random {1000 - bad_random}/1000")
    for ws, st, truth, got in bad_eval:
        print(f"  ✗ {ws} [{st}]\n     python {truth}\n     mirror {got}")
    return 1 if bad_eval else 0


if __name__ == "__main__":
    sys.exit(main())
