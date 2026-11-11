#!/bin/sh
# Catches a freeze in the act. Start the game with DM_HITCH_DUMP=<ms> (mkw/test/run.sh DM_HITCH_DUMP=3000): when no frame has been presented for that long
# the host logs `hitch dump N: no present for … ms` and every game thread's pc. This script watches the log for that line and takes a `sample` of the host
# then (every thread's stack, host and game code), 4 s long. For upstream issue #1859, the 13 to 60 s freezes at the end of a race: the sample and the pcs
# name the code that has the CPU.
# Usage: mkw/test/stall_sample.sh <the run's log>          Samples go beside the log as <log>.stall-<n>.txt (at most 6).
LOG="$1"; seen=0; n=0
while pgrep -x dmhost >/dev/null; do
  c=$(grep -c 'hitch dump' "$LOG" 2>/dev/null || echo 0)
  if [ "$c" -gt "$seen" ] && [ $n -lt 6 ]; then
    seen=$c; n=$((n + 1)); out="$LOG.stall-$n.txt"
    echo "stall_sample $(date +%H:%M:%S): $(grep 'hitch dump' "$LOG" | tail -1 | cut -c1-80): sampling to $out"
    sample "$(pgrep -x dmhost | head -1)" 4 -mayDie -file "$out" >/dev/null 2>&1
  fi
  sleep 1
done
