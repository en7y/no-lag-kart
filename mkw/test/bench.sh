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
set -- "$BUILD" --lock /tmp/mkw-measure.lock "$@"
if [ -n "$ENVF" ] && [ -f "$ENVF" ]; then
  while IFS= read -r l; do case "$l" in ''|\#*) ;; *) set -- "$@" --env "$l";; esac; done < "$ENVF"
fi
"$ROOT/mkw/test/watchdog.sh" & WD=$!
trap 'kill $WD 2>/dev/null' EXIT INT TERM
caffeinate -dim "$PY" "$ROOT/scripts/bench.py" "$@"
