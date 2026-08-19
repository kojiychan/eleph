#!/usr/bin/env bash
set -euo pipefail

SSID="${ELEPH_WIFI_SSID:-}"
PASSWORD="${ELEPH_WIFI_PASSWORD:-}"
WIFI_IFACE="${ELEPH_WIFI_IFACE:-wlan0}"
PING_TARGET="${ELEPH_WIFI_PING_TARGET:-1.1.1.1}"

if [[ -z "$SSID" ]]; then
  read -r -p "Wi-Fi SSID: " SSID
fi

if [[ -z "$SSID" ]]; then
  printf "Wi-Fi SSID is required.\n" >&2
  exit 1
fi

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "Wi-Fi password for ${SSID}: " PASSWORD
  printf "\n"
fi

if [[ -z "$PASSWORD" ]]; then
  printf "Wi-Fi password is required.\n" >&2
  exit 1
fi

if command -v nmcli >/dev/null 2>&1; then
  sudo nmcli radio wifi on
  if sudo nmcli --wait 30 device wifi connect "$SSID" password "$PASSWORD" ifname "$WIFI_IFACE"; then
    sudo nmcli connection modify "$SSID" connection.autoconnect yes
    sudo nmcli connection modify "$SSID" connection.autoconnect-priority 100
    sudo nmcli connection modify "$SSID" 802-11-wireless.powersave 2 || true
  else
    printf "NetworkManager could not connect to %s.\n" "$SSID" >&2
    exit 1
  fi
else
  if ! command -v wpa_passphrase >/dev/null 2>&1; then
    printf "Need either nmcli or wpa_passphrase to configure Wi-Fi.\n" >&2
    exit 1
  fi

  tmp_file="$(mktemp)"
  trap 'rm -f "$tmp_file"' EXIT
  wpa_passphrase "$SSID" "$PASSWORD" > "$tmp_file"
  sudo install -m 600 "$tmp_file" /etc/wpa_supplicant/wpa_supplicant.conf
  sudo systemctl enable wpa_supplicant.service >/dev/null 2>&1 || true
  sudo systemctl restart wpa_supplicant.service
fi

sudo install -m 755 scripts/wifi_healthcheck.sh /usr/local/bin/eleph-wifi-healthcheck
sudo install -m 644 systemd/eleph-wifi-healthcheck.service /etc/systemd/system/eleph-wifi-healthcheck.service
sudo install -m 644 systemd/eleph-wifi-healthcheck.timer /etc/systemd/system/eleph-wifi-healthcheck.timer
sudo systemctl daemon-reload
sudo systemctl enable --now eleph-wifi-healthcheck.timer

printf "Configured Wi-Fi SSID %s for autoconnect on %s.\n" "$SSID" "$WIFI_IFACE"
printf "Health check target: %s\n" "$PING_TARGET"
