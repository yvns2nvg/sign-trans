#!/usr/bin/env bash
# kslx conda env(torch, mediapipe, kiwipiepy)를 상속하고 onnx 관련 패키지만 이 폴더에 추가로 설치한다.
# kslx env 자체는 건드리지 않는다.
set -euo pipefail
cd "$(dirname "$0")"
/opt/miniconda3/envs/kslx/bin/python -m venv --system-site-packages .venv
.venv/bin/pip install --quiet onnx onnxscript onnxruntime
.venv/bin/python -c "import torch, mediapipe, kiwipiepy, onnx, onnxruntime; print('env ok')"
