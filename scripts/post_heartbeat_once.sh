#!/usr/bin/env bash
set -euo pipefail

cd /home/kojiychan/eleph

for attempt in 1 2 3 4 5; do
  if PYTHONPATH=src python3 -m eleph heartbeat --device-id bathroom-monitor-001 --strict-upload; then
    exit 0
  fi

  logger -t eleph-heartbeat "heartbeat upload failed on attempt ${attempt}; retrying"
  sleep 15
done

exit 1
