#!/usr/bin/env bash
# ovo-pa-ensure.sh — self-heal the OVO USB DAC as the system PulseAudio sink.
#
# Why this exists:
#   /etc/pulse/system-ovo.pa loads `module-alsa-sink device=hw:OVO sink_name=ovo`
#   ONCE at daemon start. If the OVO USB device is mid-(re)enumeration at that
#   moment (it flaps for a few seconds on plug-in), that load fails, PulseAudio
#   falls back to module-always-sink (auto_null), and `set-default-sink ovo`
#   silently no-ops. Audio then plays into the null sink — nothing comes out.
#
#   This script makes the box self-healing: if the OVO card is present but the
#   `ovo` sink is missing, it (re)loads it, makes it default, unmutes it, and
#   moves any in-flight streams onto it. Safe to run repeatedly; it is driven by
#   a systemd timer (every 30s) and by a udev hook on OVO plug-in.
#
#   Routing policy: once `ovo` exists and is healthy, this script does NOT keep
#   forcing it to be the default or yanking streams onto it — that would fight a
#   deliberate choice (e.g. Bluetooth). It only takes over when output has fallen
#   back to the dummy sink (auto_null) or no default exists.
set -u

export PULSE_SERVER="${PULSE_SERVER:-unix:/var/run/pulse/native}"
PACTL="${PACTL:-$(command -v pactl || echo /usr/bin/pactl)}"

log() { logger -t ovo-pa-ensure -- "$*" 2>/dev/null || true; }

# Serialize runs: the 30s timer and the udev SYSTEMD_WANTS hook can fire at the
# same time; without a lock they could double-load the module or unload it from
# under each other.
LOCK="${OVO_LOCK:-/run/lock/ovo-pa-ensure.lock}"
if exec 9>"$LOCK" 2>/dev/null; then
  flock -n 9 || { log "another instance holds $LOCK; skipping this run"; exit 0; }
else
  # Don't refuse to heal just because the lock can't be opened — running without
  # serialization is better than leaving the box silent.
  log "WARNING: cannot open lock $LOCK; running without serialization"
fi

# System daemon must be up; otherwise there is nothing to talk to yet.
"$PACTL" info >/dev/null 2>&1 || exit 0

# Is the OVO present at the ALSA level right now? (card name "OVO" is stable.)
device_present() { grep -qE '^[ ]*[0-9]+ \[OVO ' /proc/asound/cards 2>/dev/null; }

# Index of the module that owns the `ovo` sink (empty if none).
ovo_sink_module() {
  "$PACTL" list short modules 2>/dev/null \
    | awk '/module-alsa-sink/ && /sink_name=ovo/ {print $1; exit}'
}

# Match a sink named EXACTLY `ovo` (not e.g. alsa_output.ovo.analog-stereo).
sink_exists() { "$PACTL" list short sinks 2>/dev/null | awk '{print $2}' | grep -qx ovo; }

current_default() { "$PACTL" info 2>/dev/null | awk -F': ' '/^Default Sink:/{print $2}'; }

load_ovo() {
  # tsched=0 + 4x4800B fragments ≈ 100ms hardware buffer. The buffer rides out
  # WiFi jitter/latency spikes (seen up to ~46ms, now ~34ms after powersave off)
  # that would otherwise underrun the DAC and cause crackle/dropouts; 100ms keeps
  # ~3x headroom while cutting latency vs 200ms. Keep these args identical to the
  # module-alsa-sink line in /etc/pulse/system-ovo.pa so boot and self-heal match.
  local err
  if err="$("$PACTL" load-module module-alsa-sink device=hw:OVO sink_name=ovo \
      channels=2 rate=48000 tsched=0 fragments=4 fragment_size=4800 \
      sink_properties="device.description='OVO_USB_Speaker'" 2>&1)"; then
    return 0
  fi
  log "load-module module-alsa-sink failed: $err"
  return 1
}

# Make ovo the default, unmute it, and pull any in-flight streams onto it.
# Only called when we just (re)created the sink or rescued from the dummy sink.
take_over() {
  "$PACTL" set-default-sink ovo 2>/dev/null || log "set-default-sink ovo failed"
  "$PACTL" set-sink-mute ovo 0 2>/dev/null
  local si
  for si in $("$PACTL" list short sink-inputs 2>/dev/null | cut -f1); do
    "$PACTL" move-sink-input "$si" ovo 2>/dev/null
  done
}

if device_present; then
  if ! sink_exists; then
    log "OVO present but sink missing — loading module-alsa-sink"
    load_ovo || exit 0          # load_ovo already logged the failure
    log "OVO sink restored"
  fi
  # Sink now exists. Keep it unmuted, but don't fight deliberate routing: only
  # seize the default (and rescue stranded streams) when output is on the dummy
  # sink or there is none. If another real sink is chosen (e.g. Bluetooth), or
  # we just (re)created ovo while such a sink is active, leave it alone.
  "$PACTL" set-sink-mute ovo 0 2>/dev/null
  case "$(current_default)" in
    ovo) : ;;                                     # already correct
    auto_null|"") log "default is '$(current_default)' — reclaiming ovo"
                  take_over ;;
    *) : ;;                                       # another real sink chosen — leave it
  esac
else
  # Device gone: drop a stale sink so a clean one is built when it returns.
  mod="$(ovo_sink_module)"
  if [ -n "$mod" ]; then
    log "OVO absent — unloading stale sink module $mod"
    "$PACTL" unload-module "$mod" 2>/dev/null || log "unload-module $mod failed"
  fi
fi
exit 0
