#!/usr/bin/env bash
set -euo pipefail

BOOT_DIR="${ELEPH_BOOT_DIR:-/boot/firmware}"
WIFI_ENV="${BOOT_DIR}/eleph-wifi.env"
LOG_PATH="/var/log/eleph-early-wifi.log"

exec > >(tee -a "$LOG_PATH") 2>&1

echo "[$(date --iso-8601=seconds)] starting Eleph early Wi-Fi setup"

if [[ ! -f "$WIFI_ENV" ]]; then
  echo "Missing Wi-Fi env file: $WIFI_ENV"
  exit 0
fi

# shellcheck disable=SC1090
source "$WIFI_ENV"

if [[ -z "${ELEPH_WIFI_SSID:-}" || -z "${ELEPH_WIFI_PASSWORD:-}" ]]; then
  echo "Wi-Fi SSID or password is empty"
  exit 0
fi

install -d -m 700 /etc/NetworkManager/system-connections
cat >"/etc/NetworkManager/system-connections/${ELEPH_WIFI_SSID}.nmconnection" <<EOF
[connection]
id=${ELEPH_WIFI_SSID}
type=wifi
interface-name=wlan0
autoconnect=true

[wifi]
mode=infrastructure
ssid=${ELEPH_WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${ELEPH_WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
method=auto
EOF

chmod 600 "/etc/NetworkManager/system-connections/${ELEPH_WIFI_SSID}.nmconnection"
systemctl restart NetworkManager >/dev/null 2>&1 || true
nmcli radio wifi on >/dev/null 2>&1 || true
nmcli connection up "$ELEPH_WIFI_SSID" >/dev/null 2>&1 || true

echo "[$(date --iso-8601=seconds)] Eleph early Wi-Fi setup complete"
