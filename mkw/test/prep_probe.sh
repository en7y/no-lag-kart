#!/bin/sh
# Builds every line of a pipeline prewarm list on this Mac, away from the game's own files: the game starts on a copy of the save with a pipeline archive of its own,
# runs its prepare step on that list alone (DM_PSO_MANIFEST=<list>), and is stopped a little after the step has finished. Prints the prepare lines, the red lines, and
# whether the host or Metal's compiler service crashed. A list from elsewhere goes through this before it goes into the profile.
# Usage: mkw/test/prep_probe.sh <list.tsv> [KEY=VALUE ...]
#   ARCH=prebuilt   the probe's archive starts as the pack's prebuilt files alone (default; no run files, so no compaction)
#   ARCH=all        it starts as a copy of the build's whole archive without the "compacting" marker (more than 8 run files in it: a compacting start)
#   ARCH=empty      it starts empty
#   WORK=<folder>   work folder (default /tmp/mkw-probe/<time>); AFTER=<s> run this long after the prepare step (default 25, time for the archive's flush)
#   TIMEOUT=<s>     give up after this long (default 1800); HOST=<path> another host; KEEP=1 keeps the probe's archive (default: removed, the log stays)
# The copies are APFS clones (cp -c): they take no disk space until they change.
set -eu
[ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 2; }
LIST=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ID=0400C3F00006E000
DUMP="${MKW_DUMP:-$ROOT/../MarioKartWorld}"
B="${MKW_BUILD:-$DUMP/${ID}_build}"
HOST="${HOST:-$B/tools/dmhost}"
PATCHED=$(ls -d "$B"/patched_v*[0-9] | sort -t v -k 2 -n | tail -1)
VER=${PATCHED##*patched_}
PROF="$B/profile/$ID"
WORK="${WORK:-/tmp/mkw-probe/$(date +%H%M%S)}"
mkdir -p "$WORK/temp" "$WORK/pso_archive"
cp -cR "$B/run/save" "$WORK/save"
case "${ARCH:-prebuilt}" in
  prebuilt) for f in "$B"/run/pso_archive/p[0-9]*.mtl4a "$B"/run/pso_archive/p[0-9]*.keys "$B"/run/pso_archive/prebuilt.tsv; do cp -c "$f" "$WORK/pso_archive/"; done;;
  all) for f in "$B"/run/pso_archive/*.mtl4a "$B"/run/pso_archive/*.keys "$B"/run/pso_archive/prebuilt.tsv; do cp -c "$f" "$WORK/pso_archive/"; done;;
  empty) ;;
  *) echo "ARCH: prebuilt, all or empty"; exit 2;;
esac
LOG="$WORK/log.txt"
export DM_ROOT="$B" DM_ROMFS="$B/extract/$VER/RomFS.img" DM_SAVE="$WORK/save" DM_TEMP="$WORK/temp" DM_MSL_DIR="$B/shader/cache" DM_FONT_DIR="$B/font"
export DM_NVN_SHMAP="$PROF/shader_map.tsv" DM_LANG=en-US DM_WINDOW=1 DM_AUDIO=0 DM_FOCUS_KEEP=1
export DM_PSO_MANIFEST="$LIST" DM_PSO_USER="$WORK/pso_user.tsv" DM_PSO_ARCHIVE="$WORK/pso_archive"
while IFS= read -r l; do case "$l" in ''|\#*) ;; *) export "$l";; esac; done < "$ROOT/mkw/env-m2pro-16gb.txt"
for kv in "$@"; do export "$kv"; done
T0=$(date +%s); touch "$WORK/start"
( cd "$WORK" && exec "$HOST" "$PATCHED" > "$LOG" 2>&1 ) & HP=$!
END=""; DONE_AT=0
while :; do
  sleep 1; NOW=$(date +%s)
  kill -0 $HP 2>/dev/null || { END="the host ended by itself"; break; }
  if [ $DONE_AT -eq 0 ] && grep -q "pipeline prepare: [0-9]* lines\|pipeline prepare: the prewarm lists hold nothing" "$LOG" 2>/dev/null; then DONE_AT=$NOW; fi
  if [ $DONE_AT -ne 0 ] && [ $((NOW - DONE_AT)) -ge "${AFTER:-25}" ]; then END="stopped ${AFTER:-25} s after the prepare step"; break; fi
  if [ $((NOW - T0)) -ge "${TIMEOUT:-1800}" ]; then END="timeout after ${TIMEOUT:-1800} s"; break; fi
done
if kill -0 $HP 2>/dev/null; then kill -TERM $HP; i=0; while kill -0 $HP 2>/dev/null && [ $i -lt 90 ]; do sleep 1; i=$((i + 1)); done; kill -0 $HP 2>/dev/null && { kill -KILL $HP; END="$END (did not end on SIGTERM within 90 s: killed)"; }; fi
wait $HP 2>/dev/null && RC=0 || RC=$?
echo "probe: $LIST ($(grep -vc '^#' "$LIST") rows), archive ${ARCH:-prebuilt}, $(( $(date +%s) - T0 )) s; $END; exit status $RC"
grep "pipeline prewarm list\|pipeline prepare:\|pipeline prewarm done\|pipeline bases so far\|compaction\|compacting" "$LOG" | cut -c1-420 || true
echo "archive files written: $(grep -c "pipeline archive: .* written to" "$LOG" || true); red lines: $(grep -c "\[RED\]" "$LOG" || true); host crash lines: $(grep -c "CRASH sig" "$LOG" || true)"
grep "\[RED\]" "$LOG" | sed 's/[0-9][0-9]*/N/g' | cut -c1-200 | sort | uniq -c | sort -rn | head -12 || true
grep -A3 "failed assertion" "$LOG" | head -8 || true
NEW=$(find "$HOME/Library/Logs/DiagnosticReports" -name "*.ips" -newer "$WORK/start" 2>/dev/null | sed 's|.*/||' | sort | tr '\n' ' ')
echo "crash reports since the start: ${NEW:-none}"
echo "log: $LOG"
[ -n "${KEEP:-}" ] || rm -rf "$WORK/pso_archive" "$WORK/save" "$WORK/save.work" "$WORK/temp"
