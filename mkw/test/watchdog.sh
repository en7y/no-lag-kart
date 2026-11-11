#!/bin/sh
# Stops the game before the Mac does: GPU memory is wired, and a game that takes all of it can freeze macOS until the power button (upstream issue #1326).
# Every 2 s it reads the system's memory pressure level and the swap in use; at the critical level, or once swap has grown by more than the limit since
# the start, it ends every dmhost (SIGTERM, then SIGKILL after 5 s) and says why. mkw/test/bench.sh starts it; for a run by hand: mkw/test/watchdog.sh &
# Usage: mkw/test/watchdog.sh [swap growth limit in MB, default 6000]
LIMIT="${1:-6000}"
swap() { sysctl -n vm.swapusage | sed 's/.*used = \([0-9]*\).*/\1/'; }
base=$(swap)
echo "watchdog: swap now ${base} MB, limit +${LIMIT} MB, stops dmhost at memory pressure level 4"
while :; do
  lvl=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)   # 1 normal, 2 warning, 4 critical
  sw=$(swap); grown=$((sw - base))
  if [ "$lvl" -ge 4 ] || [ "$grown" -gt "$LIMIT" ]; then
    if pgrep -x dmhost >/dev/null; then
      echo "watchdog $(date +%H:%M:%S): memory pressure level $lvl, swap +${grown} MB: stopping the game"
      pkill -TERM -x dmhost; sleep 5; pkill -KILL -x dmhost 2>/dev/null
    fi
  fi
  sleep 2
done
