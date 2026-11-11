#!/bin/sh
# Builds the Mac app from the dump next to this repo. Settings: mkw/env-m2pro-16gb.txt (BASELINE=1 builds with no settings file).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GAME="${GAME:-$ROOT/../MarioKartWorld}"
[ -f "$HOME/nup/.venv/bin/activate" ] && . "$HOME/nup/.venv/bin/activate"
python3 "$ROOT/mkw/verify_dump.py" "$GAME/updates/917504" || { echo "the dump is incomplete: see mkw/README.md"; exit 1; }
set -- "$GAME" --platform mac-app --allow-other-metal --progress lines -o "$GAME/Mario Kart World.app" "$@"
[ -n "${BASELINE:-}" ] || set -- "$@" --env-file "$ROOT/mkw/env-m2pro-16gb.txt"
exec nice -n 5 python3 "$ROOT/scripts/build_ipa_from_nsp.py" "$@"
