#!/usr/bin/env bash
set -euo pipefail

cd /home/kojiychan/eleph

printf "Eleph preflight: Python compile\n"
python3 -m compileall -q src tests

printf "Eleph preflight: doctor\n"
PYTHONPATH=src python3 -m eleph doctor

printf "Eleph preflight: simulated motion\n"
PYTHONPATH=src python3 -m eleph monitor \
  --sensor simulated \
  --device-id bathroom-monitor-001 \
  --iterations 5 \
  --debounce-ms 0 \
  --cooldown-seconds 0

printf "Eleph preflight complete.\n"
