#!/usr/bin/env bash
# install-ovo-recovery.sh — install the OVO PulseAudio self-heal hook on the Jetson.
# Run ON THE JETSON with sudo:   sudo ./install-ovo-recovery.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }

# Fail early with a clear message if any payload file is missing from $here.
for f in ovo-pa-ensure.sh ovo-pa-ensure.service ovo-pa-ensure.timer 99-ovo-pa.rules; do
  [ -f "$here/$f" ] || { echo "Missing required file: $here/$f" >&2; exit 1; }
done

echo "Installing self-heal script..."
install -m 0755 "$here/ovo-pa-ensure.sh"      /usr/local/bin/ovo-pa-ensure.sh

echo "Installing systemd units..."
install -m 0644 "$here/ovo-pa-ensure.service" /etc/systemd/system/ovo-pa-ensure.service
install -m 0644 "$here/ovo-pa-ensure.timer"   /etc/systemd/system/ovo-pa-ensure.timer

echo "Installing udev rule..."
install -m 0644 "$here/99-ovo-pa.rules"       /etc/udev/rules.d/99-ovo-pa.rules

echo "Reloading systemd + udev..."
systemctl daemon-reload
udevadm control --reload-rules

echo "Enabling + starting the timer..."
systemctl enable --now ovo-pa-ensure.timer

echo "Running one immediate check..."
systemctl start ovo-pa-ensure.service || true

echo
echo "Done. Status:"
systemctl --no-pager status ovo-pa-ensure.timer | sed -n '1,4p' || true
echo
echo "Current default sink:"
PULSE_SERVER=unix:/var/run/pulse/native pactl info | grep 'Default Sink' || true
