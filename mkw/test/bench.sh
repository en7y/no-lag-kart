#!/bin/sh
# scripts/bench.py on the packed game, with this project's settings and the memory watchdog. Each variant runs the same route from a copy of the same save, in turn,
# and the results are medians with their range: compare the variants of one invocation, never two invocations (load on the Mac moves the numbers).
# Usage: mkw/test/bench.sh [--route gp-race1] [--runs 2] [--variant 'label:host=<path>,KEY=VALUE'] ...   (every option of scripts/bench.py; routes: dm/games/<id>/bench.tsv)
# Examples (a host per variant comes from mkw/test/host.py, which prints its --variant):
#   mkw/test/bench.sh --variant 'fixes:' --variant 'upstream:host=<build>/variants/upstream/dmhost'
#   mkw/test/bench.sh --variant 'hold:' --variant 'nohold:DM_FPS_HOLD=off'
# The settings of mkw/env-m2pro-16gb.txt go to every variant (BENCH_ENV names another file; BENCH_ENV= for none). Results: <build>/bench/<time>/results.md
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DUMP="${MKW_DUMP:-$ROOT/../MarioKartWorld}"
BUILD="${MKW_BUILD:-$DUMP/0400C3F00006E000_build}"
PY="${MKW_PYTHON:-$HOME/nup/.venv/bin/python3}"
ENVF="${BENCH_ENV-$ROOT/mkw/env-m2pro-16gb.txt}"
[ -x "$BUILD/tools/dmhost" ] || { echo "no packed game in $BUILD: run mkw/test/pack.sh first"; exit 1; }
[ -d "$BUILD/run/save" ] || { echo "no save in $BUILD/run/save: start the game once by hand, reach the main menu, quit"; exit 1; }
pmset -g batt | grep -q "AC Power" || echo "warning: on battery, the numbers will be lower and less steady"
# The game stays in focus whichever app is active (DM_FOCUS_KEEP), so a click elsewhere does not pause it; BENCH_TOP=1 also keeps its window above the others without
# activating it, as scripts/regress.py does (a window that is not the active app's got no display ticks for half a second at a time here: leave it off to measure).
# Every run takes the build's pipeline archive and this Mac's prewarm list (<build>/run), so no run compiles what play has already met. By default the runs of one
# invocation share a copy of the two (APFS clones, no disk space until they change; removed at the end): what a run adds does not reach the game's own files, and
# every invocation starts from the same state. BENCH_STATE=shared takes the game's own files in place, for a warm-up run whose pipelines should stay.
STATE="$BUILD/run"
if [ "${BENCH_STATE:-clone}" = clone ]; then
  STATE="$BUILD/bench/.state.$$"; rm -rf "$STATE"; mkdir -p "$STATE"
  cp -cR "$BUILD/run/pso_archive" "$STATE/pso_archive"; [ ! -f "$BUILD/run/pso_user.tsv" ] || cp -c "$BUILD/run/pso_user.tsv" "$STATE/pso_user.tsv"
  rm -f "$STATE/pso_archive/compacting"
fi
set -- "$BUILD" --lock /tmp/mkw-measure.lock --env DM_FOCUS_KEEP=1 --pso-archive "$STATE/pso_archive" --env "DM_PSO_USER=$STATE/pso_user.tsv" "$@"
[ -z "${BENCH_TOP:-}" ] || set -- "$@" --env DM_WINDOW_TOP=1
if [ -n "$ENVF" ] && [ -f "$ENVF" ]; then
  while IFS= read -r l; do case "$l" in ''|\#*) ;; *) set -- "$@" --env "$l";; esac; done < "$ENVF"
fi
"$ROOT/mkw/test/watchdog.sh" & WD=$!
trap 'kill $WD 2>/dev/null; [ "$STATE" = "$BUILD/run" ] || rm -rf "$STATE"' EXIT INT TERM
# A display that sleeps (or a screen saver) covers the window: macOS then calls the game's display link about once a second, the host presents without it, and the frame
# times of that run measure nothing. caffeinate -d keeps the display from sleeping but does not wake one that sleeps already, so wake it first (-u: as if the user did
# something; no password while the lock delay has not passed), and name every run whose window was covered at any time.
caffeinate -u -t 3
RC=0; caffeinate -dim "$PY" "$ROOT/scripts/bench.py" "$@" || RC=$?
LAST=$(ls -dt "$BUILD"/bench/*/ 2>/dev/null | head -1)
for l in "$LAST"*/log.txt; do
  [ -f "$l" ] || continue
  n=$(grep -c "front end: window covered" "$l" || true)
  [ "$n" = 0 ] || echo "warning: $(basename "$(dirname "$l")"): the window was covered $n time(s) during the run (display asleep, screen saver or another window): its frame times measure nothing, its GPU times still do"
done
exit $RC
