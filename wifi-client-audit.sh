#!/usr/bin/env bash
# wifi-client-audit.sh - Collect wireless client configuration and behaviour
# from a fleet laptop, for comparison against a known-good reference machine.
#
# Read-only. Changes nothing. Safe to run on a user's machine mid-workday,
# though the scan-watch section takes 5 minutes by default.
#
# Usage:
#   ./wifi-client-audit.sh                 # full audit, 300s scan watch
#   ./wifi-client-audit.sh -w 60           # shorter scan watch
#   ./wifi-client-audit.sh -w 0            # skip the scan watch entirely
#   ./wifi-client-audit.sh -o report.txt   # also write to a file
#
# IMPORTANT: close the GNOME Wi-Fi settings panel and any network applet menu
# before running. An open Wi-Fi list makes NetworkManager scan continuously,
# which invalidates the scan-behaviour section.

set -uo pipefail

WATCH=300
OUT=""
while getopts "w:o:h" opt; do
  case $opt in
    w) WATCH="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    h) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "try -h"; exit 1 ;;
  esac
done
if ! [[ "$WATCH" =~ ^[0-9]+$ ]]; then
  echo "-w expects a whole number of seconds (got '$WATCH')"; exit 1
fi

[[ -n "$OUT" ]] && exec > >(tee "$OUT") 2>&1

hr()  { printf '\n%s\n%s\n%s\n' "======================================================================" "$1" "======================================================================"; }
sub() { printf '\n--- %s ---\n' "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# ---------- identify the wireless interface ----------
IFACE=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')
[[ -z "${IFACE:-}" ]] && IFACE=$(ls /sys/class/net | while read -r d; do
    [[ -d "/sys/class/net/$d/wireless" ]] && echo "$d" && break; done)
if [[ -z "${IFACE:-}" ]]; then
  echo "No wireless interface found. Aborting."; exit 1
fi

hr "WIRELESS CLIENT AUDIT  -  $(hostname)  -  $(date -Is)"
echo "  interface: $IFACE"
echo "  run as:    $(id -un)$([[ $EUID -eq 0 ]] && echo ' (root)' || echo ' (will prompt for sudo)')"

# ---------- system identity ----------
hr "1. SYSTEM"
sub "distribution"
[[ -r /etc/os-release ]] && grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
sub "kernel"
uname -r
sub "hardware"
have dmidecode && sudo dmidecode -s system-product-name 2>/dev/null || \
  cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "unavailable"

# ---------- radio hardware and driver ----------
hr "2. RADIO HARDWARE AND DRIVER"
sub "pci device and bound driver"
have lspci && lspci -nnk | grep -A3 -iE 'network|wireless' || echo "lspci unavailable"
sub "driver module"
DRV=$(basename "$(readlink -f "/sys/class/net/$IFACE/device/driver" 2>/dev/null)" 2>/dev/null)
echo "driver: ${DRV:-unknown}"
if [[ -n "${DRV:-}" ]] && have modinfo; then
  modinfo "$DRV" 2>/dev/null | grep -E '^(filename|version|firmware|description):' | head -12
fi
sub "firmware version reported by the adapter"
have ethtool && sudo ethtool -i "$IFACE" 2>/dev/null | grep -Ei 'driver|version|firmware' || echo "ethtool unavailable"

# ---------- supplicant backend ----------
hr "3. SUPPLICANT BACKEND"
sub "which backend is running"
systemctl is-active wpa_supplicant iwd 2>/dev/null | paste -d' ' <(echo -e "wpa_supplicant:\niwd:") -
sub "versions"
have wpa_supplicant && wpa_supplicant -v 2>/dev/null | head -1
have iwd && iwd --version 2>/dev/null | head -1
have NetworkManager && NetworkManager --version | sed 's/^/NetworkManager /'
sub "NetworkManager wifi backend"
NetworkManager --print-config 2>/dev/null | grep -A4 '^\[device\]' || echo "no [device] section"
sub "wpa_supplicant control socket"
ls -l /run/wpa_supplicant/ 2>/dev/null || \
  echo "absent - NetworkManager runs the supplicant over D-Bus (normal; wpa_cli will not attach)"

# ---------- connection profile ----------
hr "4. CONNECTION PROFILE"
CONN=$(nmcli -g GENERAL.CONNECTION device show "$IFACE" 2>/dev/null | head -1)
echo "active wireless connection: ${CONN:-<none>}"
if [[ -n "${CONN:-}" ]]; then
  sub "settings that affect band choice, roaming and power"
  nmcli -f 802-11-wireless.band,802-11-wireless.bssid,802-11-wireless.channel,\
802-11-wireless.powersave,802-11-wireless.cloned-mac-address,\
802-11-wireless-security.key-mgmt,802-11-wireless-security.pmf,connection.autoconnect \
    connection show "$CONN" 2>/dev/null
  sub "any bgscan property exposed by this NetworkManager version"
  nmcli connection show "$CONN" 2>/dev/null | grep -i bgscan || \
    echo "no bgscan property exposed (varies by NetworkManager version)"
fi

# ---------- current link ----------
hr "5. CURRENT LINK"
sub "association"
iw dev "$IFACE" link 2>/dev/null || echo "not associated"
sub "band"
FREQ=$(iw dev "$IFACE" link 2>/dev/null | awk '/freq/{print $2; exit}')
FREQ=${FREQ%%.*}   # newer iw prints "5180.0"
if [[ -n "${FREQ:-}" ]]; then
  if   (( FREQ < 2500 )); then echo "$FREQ MHz -> 2.4 GHz"
  elif (( FREQ < 5900 )); then echo "$FREQ MHz -> 5 GHz"
  else                          echo "$FREQ MHz -> 6 GHz"; fi
fi
sub "power save"
iw dev "$IFACE" get power_save 2>/dev/null || echo "unavailable"
sub "negotiated rates and signal"
iw dev "$IFACE" link 2>/dev/null | grep -Ei 'bitrate|signal' || true
sub "station counters (retries, failures)"
BSSID=$(iw dev "$IFACE" link 2>/dev/null | awk '/Connected to/{print $3; exit}')
[[ -n "${BSSID:-}" ]] && iw dev "$IFACE" station get "$BSSID" 2>/dev/null | \
  grep -Ei 'signal|tx bitrate|rx bitrate|tx retries|tx failed|connected time' || echo "unavailable"

# ---------- channel utilization ----------
hr "6. CHANNEL UTILIZATION (driver survey counters)"
echo "busy/active is how occupied the medium is. Counters are cumulative since"
echo "the interface came up, so treat these as a long-run average."
sub "survey"
iw dev "$IFACE" survey dump 2>/dev/null | awk '
  /frequency:/            { f=$2 }
  /channel active time:/  { a=$4 }
  /channel busy time:/    { b=$4 }
  /channel receive time:/ { r=$4 }
  /channel transmit time:/{ t=$4
      if (a+0>0) printf "  %s MHz: active %10d ms  busy %10d ms  (%.1f%%)  rx %d  tx %d\n", f,a,b,100*b/a,r,t }
' || echo "unavailable"

# ---------- 802.11r / k / v ----------
hr "7. FAST TRANSITION AND ROAMING SUPPORT"
sub "does the current AP advertise 802.11r (FT)?"
if [[ -n "${CONN:-}" ]]; then
  SSID=$(nmcli -g 802-11-wireless.ssid connection show "$CONN" 2>/dev/null)
  # a fresh scan fails with "busy" if NetworkManager is mid-scan; fall back to cached results
  SCAN=$(sudo iw dev "$IFACE" scan 2>/dev/null || sudo iw dev "$IFACE" scan dump 2>/dev/null)
  if [[ -z "$SCAN" ]]; then
    echo "  scan unavailable (needs root)"
  else
    # iw prints no blank line between BSS blocks, so flush on the next BSS line and at END
    awk -v s="$SSID" '
      function flush() { if (bss!="" && cur==s) printf "  %s  11r:%s  11k:%s  11v:%s\n", bss, (ft?"yes":"no"), (rrm?"yes":"no"), (bt?"yes":"no") }
      /^BSS / {flush(); bss=substr($2,1,17); cur=""; ft=0; rrm=0; bt=0}
      $1=="SSID:" {cur=$0; sub(/^[ \t]*SSID: /,"",cur)}
      /FT over/ || /Authentication suites.*FT/ || /MDE/ || /Mobility Domain/ {ft=1}
      /RM enabled/ {rrm=1}
      /BSS Transition/ {bt=1}
      END {flush()}
    ' <<< "$SCAN"
  fi
else
  echo "  not associated"
fi

# ---------- scan behaviour ----------
if (( WATCH > 0 )); then
  hr "8. SCAN BEHAVIOUR  (watching ${WATCH}s)"
  echo "REMINDER: if a Wi-Fi settings panel or applet menu is open, NetworkManager"
  echo "scans continuously and this section is meaningless. Close it and re-run."
  echo
  echo "Interpreting the result:"
  echo "  periodic scans, long gaps   -> client maintains roam candidates (healthy)"
  echo "  silence while connected     -> client is blind; can only move by dropping first"
  echo "  scans every ~15s            -> something is driving continuous rescan"
  echo
  TMP=$(mktemp)
  trap 'rm -f "$TMP"' EXIT
  sudo timeout "$WATCH" iw event -t > "$TMP" 2>/dev/null || true
  STARTS=$(grep -c 'scan started' "$TMP" 2>/dev/null || true)
  echo "  scans started in ${WATCH}s: $STARTS"
  if (( STARTS > 1 )); then
    awk '/scan started/{if(p){printf "  interval: %.1f s\n", $1-p} p=$1}' "$TMP" | head -10
    awk '/scan started/{s=$1} /scan finished/{if(s) printf "  duration: %.1f s\n", $1-s; s=0}' "$TMP" | head -10
    TOT=$(awk '/scan started/{s=$1} /scan finished/{if(s){d+=$1-s; s=0}} END{print d+0}' "$TMP")
    echo "  total time scanning: ${TOT}s of ${WATCH}s"
    awk -v t="$TOT" -v w="$WATCH" 'BEGIN{printf "  duty cycle: %.0f%%\n", 100*t/w}'
  fi
  sub "connect / disconnect / roam events during the watch"
  grep -Ei 'connected|disconnect|deauth|roam|auth' "$TMP" | head -20 || echo "  none"
  sub "raw event log (first 25 lines)"
  head -25 "$TMP"
  rm -f "$TMP"
fi

# ---------- recent NetworkManager history ----------
hr "9. RECENT NETWORKMANAGER ACTIVITY"
sub "disconnect and association events, last 24h"
sudo journalctl -u NetworkManager --since "24 hours ago" --no-pager 2>/dev/null | \
  grep -iE 'disconnect|deauth|association|roam|link down|timed out' | tail -30 || echo "unavailable"
sub "counts"
sudo journalctl -u NetworkManager --since "24 hours ago" --no-pager 2>/dev/null | \
  grep -icE 'disconnect' | sed 's/^/  disconnect mentions: /' || true

hr "END OF AUDIT"
echo "Compare against a reference machine. The fields that matter most:"
echo "  - distribution, kernel, driver, firmware  (section 1-2)"
echo "  - supplicant backend and versions         (section 3)"
echo "  - powersave and band settings             (section 4)"
echo "  - scan interval and duty cycle            (section 8)"
echo
