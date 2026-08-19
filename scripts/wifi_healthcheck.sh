#!/usr/bin/env bash
set -euo pipefail

SSID="${ELEPH_WIFI_SSID:-}"
WIFI_IFACE="${ELEPH_WIFI_IFACE:-wlan0}"
PING_TARGET="${ELEPH_WIFI_PING_TARGET:-1.1.1.1}"

if ping -I "$WIFI_IFACE" -c 1 -W 3 "$PING_TARGET" >/dev/null 2>&1; then
  exit 0
fi

logger -t eleph-wifi "Wi-Fi health check failed; reconnecting ${WIFI_IFACE}"

if command -v nmcli >/dev/null 2>&1; then
  nmcli device disconnect "$WIFI_IFACE" >/dev/null 2>&1 || true
  sleep 3
  if [[ -n "$SSID" ]]; then
    nmcli connection up "$SSID" >/dev/null 2>&1 || true
  fi
  nmcli device connect "$WIFI_IFACE" >/dev/null 2>&1 || true
else
  ip link set "$WIFI_IFACE" down || true
  sleep 3
  ip link set "$WIFI_IFACE" up || true
  systemctl restart wpa_supplicant.service >/dev/null 2>&1 || true
fi
