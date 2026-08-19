#!/usr/bin/env bash
set -euo pipefail

cd /home/kojiychan/eleph

for attempt in 1 2 3 4 5; do
  if PYTHONPATH=src python3 -m eleph post-fake-motion --device-id bathroom-monitor-001 --strict-upload; then
    exit 0
  fi

  logger -t eleph-fake-motion "fake motion upload failed on attempt ${attempt}; retrying"
  sleep 60
done

exit 1
