#!/bin/sh
# Runs the packed game by hand or under a control file, as scripts/bench.py runs it but on the real save, with the memory watchdog and a log.
# Usage: mkw/test/run.sh [KEY=VALUE ...]            e.g.  mkw/test/run.sh                      play (window, sound)
#                                                         mkw/test/run.sh DM_AUDIO=0 DM_CTL=/tmp/mkw.ctl DM_HITCH_DUMP=3000
#   HOST=<path> picks another host binary (a variant of mkw/test/host.py). The settings of mkw/env-m2pro-16gb.txt apply first, then the KEY=VALUE given here.
#   The log goes to mkw/logs/run-<time>.log (its path is printed first). The save is <build>/run/save and is written to: this is the real save, not a copy.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ID=0400C3F00006E000
DUMP="${MKW_DUMP:-$ROOT/../MarioKartWorld}"
B="${MKW_BUILD:-$DUMP/${ID}_build}"
HOST="${HOST:-$B/tools/dmhost}"
[ -x "$HOST" ] || { echo "no host at $HOST: run mkw/test/pack.sh first"; exit 1; }
PATCHED=$(ls -d "$B"/patched_v*[0-9] | sort -t v -k 2 -n | tail -1)   # the folder, not patched_v<n>.key beside it
VER=${PATCHED##*patched_}
PROF="$B/profile/$ID"; [ -f "$PROF/shader_map.tsv" ] || PROF="$ROOT/dm/games/$ID"
mkdir -p "$B/run/save" "$B/run/temp" "$ROOT/mkw/logs"
LOG="$ROOT/mkw/logs/run-$(date +%Y%m%d-%H%M%S).log"
echo "log: $LOG"
export DM_ROOT="$B" DM_ROMFS="$B/extract/$VER/RomFS.img" DM_SAVE="$B/run/save" DM_TEMP="$B/run/temp" DM_MSL_DIR="$B/shader/cache" DM_FONT_DIR="$B/font"
export DM_NVN_SHMAP="$PROF/shader_map.tsv" DM_LANG="${DM_LANG:-en-US}" DM_WINDOW=1 DM_AUDIO=1
while IFS= read -r l; do case "$l" in ''|\#*) ;; *) export "$l";; esac; done < "$ROOT/mkw/env-m2pro-16gb.txt"
for kv in "$@"; do export "$kv"; done
"$ROOT/mkw/test/watchdog.sh" >> "$LOG.watchdog" 2>&1 & WD=$!
trap 'kill $WD 2>/dev/null' EXIT INT TERM
cd "$B/run"
"$HOST" "$PATCHED" > "$LOG" 2>&1
echo "the host ended with $?"
