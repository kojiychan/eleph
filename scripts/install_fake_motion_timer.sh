#!/usr/bin/env bash
set -euo pipefail

sudo install -m 644 systemd/eleph-fake-motion.service /etc/systemd/system/eleph-fake-motion.service
sudo install -m 644 systemd/eleph-fake-motion.timer /etc/systemd/system/eleph-fake-motion.timer
sudo install -m 644 systemd/eleph-fake-motion-on-network.service /etc/systemd/system/eleph-fake-motion-on-network.service
sudo systemctl daemon-reload
sudo systemctl enable --now eleph-fake-motion-on-network.service
sudo systemctl enable --now eleph-fake-motion.timer

printf "Installed Eleph fake motion services. One event posts when network is online, then every 4 hours.\n"
