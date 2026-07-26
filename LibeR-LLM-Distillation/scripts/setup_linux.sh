#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3.12}"
TRAINING="${TRAINING:-0}"

cd "$ROOT"
if [[ ! -x .venv/bin/python ]]; then
  "$PYTHON" -m venv .venv
fi
.venv/bin/python -m pip install --upgrade pip setuptools wheel
if [[ "$TRAINING" == "1" ]]; then
  .venv/bin/python -m pip install torch --index-url https://download.pytorch.org/whl/cu128
  .venv/bin/python -m pip install -e ".[train,test]"
else
  .venv/bin/python -m pip install -e ".[test]"
fi
.venv/bin/python -m liber_distill --config configs/default.yaml doctor
