#!/bin/sh
# The development build every measurement runs on: scripts/build_ipa_from_nsp.py --platform mac, from this checkout (mkw-fixes).
# It extracts the dump, rewrites the modules, splits and builds the 11,604 shaders once, and builds the host into <dump>/0400C3F00006E000_build/tools/dmhost.
# The last line it prints is the command that runs the game. Hosts of other revisions are then built by mkw/test/host.py against the same build folder.
# Usage: mkw/test/pack.sh [more options of the packing script]       The log goes to mkw/logs/pack-<time>.log as well.
# Do not edit files in dm/games/0400C3F00006E000/ between builds without reason: the derived 1.8.0 profile is keyed by their content, and a change makes the
# script derive it again and split the shaders again (the compiled shaders come back from the cache).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DUMP="${MKW_DUMP:-$ROOT/../MarioKartWorld}"
PY="${MKW_PYTHON:-$HOME/nup/.venv/bin/python3}"
"$ROOT/mkw/test/preflight.sh" || { echo "preflight failed: nothing was built"; exit 1; }
mkdir -p "$ROOT/mkw/logs"
LOG="$ROOT/mkw/logs/pack-$(date +%Y%m%d-%H%M%S).log"
echo "log: $LOG"
caffeinate -i nice -n 5 "$PY" "$ROOT/scripts/build_ipa_from_nsp.py" "$DUMP" --platform mac --allow-other-metal --progress lines --env-file "$ROOT/mkw/env-tested.txt" "$@" 2>&1 | tee "$LOG"
