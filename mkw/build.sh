#!/bin/sh
# Builds the Mac app from the dump next to this repo. The settings are the game profile's defaults (dm/games/0400C3F00006E000/game.tsv).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GAME="${GAME:-$ROOT/../MarioKartWorld}"
[ -f "$HOME/nup/.venv/bin/activate" ] && . "$HOME/nup/.venv/bin/activate"
python3 "$ROOT/mkw/verify_dump.py" "$GAME/updates/917504" || { echo "the dump is incomplete: see mkw/README.md"; exit 1; }
set -- "$GAME" --platform mac-app --allow-other-metal --progress lines -o "$GAME/Mario Kart World.app" "$@"
exec nice -n 5 python3 "$ROOT/scripts/build_ipa_from_nsp.py" "$@"
