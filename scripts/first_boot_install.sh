#!/usr/bin/env bash
set -euo pipefail

BOOT_DIR="${ELEPH_BOOT_DIR:-/boot/firmware}"
ARCHIVE_PATH="${BOOT_DIR}/eleph-project.tar.gz"
TARGET_DIR="/home/kojiychan/eleph"
LOG_PATH="/var/log/eleph-firstboot.log"
MARKER_PATH="${BOOT_DIR}/eleph-firstboot-ran.txt"

exec > >(tee -a "$LOG_PATH") 2>&1

echo "[$(date --iso-8601=seconds)] starting Eleph first-boot install"
echo "Eleph first boot started at $(date --iso-8601=seconds)" > "$MARKER_PATH"

if [[ -f "${BOOT_DIR}/eleph-wifi.env" ]]; then
  # shellcheck disable=SC1091
  source "${BOOT_DIR}/eleph-wifi.env"
  if [[ -n "${ELEPH_WIFI_SSID:-}" && -n "${ELEPH_WIFI_PASSWORD:-}" ]] && command -v nmcli >/dev/null 2>&1; then
    nmcli radio wifi on || true
    nmcli connection delete "$ELEPH_WIFI_SSID" >/dev/null 2>&1 || true
    nmcli device wifi connect "$ELEPH_WIFI_SSID" password "$ELEPH_WIFI_PASSWORD" ifname wlan0 || true
    nmcli connection modify "$ELEPH_WIFI_SSID" connection.autoconnect yes || true
  fi
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Missing Eleph archive: $ARCHIVE_PATH"
  exit 1
fi

install -d -o kojiychan -g kojiychan "$TARGET_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$TARGET_DIR"
chown -R kojiychan:kojiychan "$TARGET_DIR"

if [[ -f "${TARGET_DIR}/.env" ]]; then
  chmod 600 "${TARGET_DIR}/.env"
fi

chmod +x "${TARGET_DIR}"/scripts/*.sh

cd "$TARGET_DIR"

python3 -m compileall src

install -m 644 systemd/eleph-fake-motion.service /etc/systemd/system/eleph-fake-motion.service
install -m 644 systemd/eleph-fake-motion.timer /etc/systemd/system/eleph-fake-motion.timer
install -m 644 systemd/eleph-fake-motion-on-network.service /etc/systemd/system/eleph-fake-motion-on-network.service

systemctl daemon-reload
systemctl enable --now eleph-fake-motion.timer
systemctl enable --now eleph-fake-motion-on-network.service

echo "[$(date --iso-8601=seconds)] Eleph first-boot install complete"
echo "Eleph first boot completed at $(date --iso-8601=seconds)" >> "$MARKER_PATH"
