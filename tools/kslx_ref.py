"""모델 저장소(kslx)를 읽기 전용으로 import 하기 위한 경로 설정.

이 모듈을 다른 import 보다 먼저 import 한다. 저장소 안에 __pycache__ 가
생기지 않게 바이트코드 쓰기를 끈다.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True

KSLX_REPO = Path(os.environ.get(
    "KSLX_REPO", Path.home() / "학교/졸작/Sign-Language-Translation-1200"))
NPZ_PATH = Path(os.environ.get(
    "KSLX_NPZ", Path.home() / "학교/졸작/Sign-Language-Translation/data/kslx/word_real02.npz"))
ROOT = Path(__file__).resolve().parent.parent   # sign-trans/

if str(KSLX_REPO) not in sys.path:
    sys.path.insert(0, str(KSLX_REPO))
