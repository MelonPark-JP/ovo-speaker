#!/usr/bin/env bash
# apply-buffer.sh — give the OVO sink a ~100ms buffer at boot so WiFi
# jitter/latency spikes don't underrun the DAC. Idempotent. Run ON THE JETSON:
#   sudo ./apply-buffer.sh
#
# It rewrites the `module-alsa-sink device=hw:OVO` line in /etc/pulse/system-ovo.pa
# to add `tsched=0 fragments=4 fragment_size=4800` (~100ms), then restarts the
# system PulseAudio daemon. Keep these args in sync with ovo-pa-ensure.sh.
set -euo pipefail

CONF=/etc/pulse/system-ovo.pa
BUF="tsched=0 fragments=4 fragment_size=4800"
# Matches the OVO sink line only when it already carries the full buffer args.
HAVE_RE='load-module module-alsa-sink .*device=hw:OVO .*tsched=0 .*fragments=4 .*fragment_size=4800'

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
[ -f "$CONF" ] || { echo "$CONF not found" >&2; exit 1; }

if grep -qE "$HAVE_RE" "$CONF"; then
  echo "Buffer args already present in $CONF — nothing to change, not restarting."
  exit 0
fi

backup="$CONF.bak.$(date +%Y%m%d%H%M%S)"
cp -a "$CONF" "$backup"
echo "Backed up $CONF -> $backup"

# Insert the buffer args right after `rate=48000` on the OVO sink line; if that
# anchor isn't there, fall back to inserting just before `sink_properties=`.
sed -i -E "s|(load-module module-alsa-sink .*device=hw:OVO[^\n]*rate=48000)( )|\1 ${BUF}\2|" "$CONF"
if ! grep -qE "$HAVE_RE" "$CONF"; then
  sed -i -E "s|(load-module module-alsa-sink .*device=hw:OVO[^\n]*)( sink_properties=)|\1 ${BUF}\2|" "$CONF"
fi

# Verify before touching the running daemon — never restart on an unverified edit.
if ! grep -qE "$HAVE_RE" "$CONF"; then
  echo "ERROR: could not insert buffer args into the OVO sink line; restoring backup." >&2
  cp -a "$backup" "$CONF"
  exit 1
fi
grep -n 'module-alsa-sink .*device=hw:OVO' "$CONF"

echo "Restarting pulseaudio-system.service ..."
systemctl restart pulseaudio-system.service
sleep 2
echo "Resulting sink latency:"
PULSE_SERVER=unix:/var/run/pulse/native pactl list sinks 2>/dev/null \
  | awk '/Name: ovo$/{f=1} f&&/Latency:/{print} f&&/Name: ovo.monitor/{exit}'
