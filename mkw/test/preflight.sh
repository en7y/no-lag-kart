#!/bin/sh
# What a build and a measurement need on this Mac, checked without the game: the list of scripts/build_ipa_from_nsp.py check_prereqs for --platform mac,
# plus disk space, the dump and the things that move frame times (power, Low Power Mode, Game Mode's record of earlier runs).
# Usage: mkw/test/preflight.sh      Exit code 0 when nothing a build needs is missing.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DUMP="${MKW_DUMP:-$ROOT/../MarioKartWorld}"
PY="${MKW_PYTHON:-$HOME/nup/.venv/bin/python3}"
bad=0
ok()   { printf '  ok    %s\n' "$1"; }
miss() { printf '  MISS  %s\n' "$1"; bad=1; }
note() { printf '  note  %s\n' "$1"; }

echo "Build tools"
[ -x "$PY" ] && ok "python: $PY ($("$PY" --version 2>&1))" || miss "python venv at $PY (MKW_PYTHON names another)"
for m in lz4.block capstone fontTools zbic; do
  "$PY" -c "import $m" 2>/dev/null && ok "python module $m" || miss "python module $m (pip install lz4 'capstone>=5,<6' fonttools zbic backports.zstd)"
done
"$PY" -c "import compression.zstd" 2>/dev/null || "$PY" -c "import backports.zstd" 2>/dev/null && ok "python zstd" || miss "python module backports.zstd"
"$PY" -c "import capstone,sys; sys.exit(0 if capstone.__version__.split('.')[0]=='5' else 1)" 2>/dev/null && ok "capstone 5.x" || miss "capstone must be 5.x"
for t in xcodebuild zstd make glslangValidator; do
  command -v $t >/dev/null 2>&1 && ok "$t" || miss "$t (zstd, glslang: brew install; the others: Xcode)"
done
xcrun -sdk macosx metal --version >/dev/null 2>&1 && ok "Metal compiler ($(xcrun -sdk macosx metal --version 2>&1 | head -1))" || miss "Metal compiler: xcodebuild -downloadComponent MetalToolchain"
X="$ROOT/dm/gfx/tools/dmsh_xlate_bin/dmsh_xlate"
[ -x "$X" ] && "$X" --source-sha >/dev/null 2>&1 && ok "shader translator runs" || miss "shader translator does not run: $X"
[ -x "$ROOT/dm/gfx/tools/spirv_cross_bin/spirv-cross" ] && ok "spirv-cross" || miss "spirv-cross in dm/gfx/tools/spirv_cross_bin"
xcrun -f metal-tt >/dev/null 2>&1 && ok "metal-tt (offline pipeline archive, --gpu)" || note "metal-tt not found: only the offline pipeline archive needs it"

echo "Disk and dump"
free=$(df -g "$DUMP" 2>/dev/null | awk 'NR==2{print $4}')
[ "${free:-0}" -ge 34 ] && ok "$free GB free (the build writes a 21.7 GB RomFS image, shader libraries and caches: about 30 GB)" || miss "only ${free:-?} GB free on the dump's volume; about 34 GB wanted"
if [ -f "$DUMP/updates/917504/exefs/main.npdm" ]; then ok "exefs/main.npdm"; else miss "exefs/main.npdm is not in the dump"; fi
"$PY" "$ROOT/mkw/verify_dump.py" "$DUMP/updates/917504" >/tmp/mkw_verify.txt 2>&1 && ok "dump complete" || miss "dump incomplete: $(tail -1 /tmp/mkw_verify.txt)"

echo "This Mac"
ok "$(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
pmset -g batt | grep -q "AC Power" && ok "on AC power" || note "on battery: macOS lowers CPU and GPU clocks; measure on AC power"
[ "$(pmset -g | awk '/lowpowermode/{print $2}')" = "1" ] && note "Low Power Mode is ON: turn it off before measuring" || ok "Low Power Mode off"
sw=$(sysctl -n vm.swapusage | sed 's/.*used = \([0-9.]*\)M.*/\1/')
note "swap in use now: ${sw} MB (close other apps before a measurement; the game wires 7 to 10 GB)"
if log show --last 1d --predicate 'process == "gamepolicyd"' 2>/dev/null | grep -qi "dmhost\|Mario Kart"; then note "gamepolicyd has seen the game in the last day: check Game Mode (docs/reference/frame-rate.md)"; else ok "no Game Mode record of the game in the last day"; fi
[ $bad = 0 ] && echo "Ready to build." || echo "Something a build needs is missing (MISS lines)."
exit $bad
