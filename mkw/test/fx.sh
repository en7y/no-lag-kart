#!/bin/sh
# fx.sh <out file> <run> [<run> ...]: bench runs in turn, each started as macOS starts an app (mkw/test/host_open.py), so that the game is the active app: the host
# enters fullscreen (DM_FULLSCREEN=1) only then, and Game Mode needs a fullscreen game. A run is "label|route|host|KEY=VAL,KEY=VAL":
#   route  1 = gp-start-150 (one player), 2 / 3 / 4 = gp150-<n>p (split screen), or a route's name; players 2 to 4 come from mkw/test/routes/<route>.ctl when it exists
#   host   gm (the packed host in a bundle that allows Game Mode), nogm (the same host in a bundle that does not), gm-<variant> (a host of mkw/test/host.py in a
#          Game Mode bundle), or the absolute path of a host inside an app bundle (<bundle>/Contents/MacOS/dmhost)
# The bundles are made under <build>/gm (mkw/test/mkbundle.sh), again when their host is newer. The settings of mkw/env-m2pro-16gb.txt go to every run (mkw/test/bench.sh).
# FX_ENV=KEY=VAL gives every run one more setting, for a value with a comma in it (DM_NVN_FS_SPLIT's list).
# After each run the lines of macOS's Game Mode daemon go to stdout. Read a run with fxsum.py, odd.py and lates.py, a whole Grand Prix with soaksum.py. For a
# long run add MKW_NO_TSV=1 (host_open.py: no per-frame rows, whose writes hold frames of their own) and read its long frames with longlog.py.
# Example: mkw/test/fx.sh /tmp/fx.out "one|1|gm|DM_FULLSCREEN=1" "four|4|gm|DM_FULLSCREEN=1" "window|1|nogm|"
# Leave minutes between fullscreen starts, as these runs do (upstream's docs/reference/frame-rate.md: eight scripted fullscreen starts in three minutes ended in a
# WindowServer watchdog panic). The screen must be unlocked, and the Mac otherwise left alone: a build or a log search beside a run shows in its frame times.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DUMP="${MKW_DUMP:-$ROOT/../MarioKartWorld}"; B="${MKW_BUILD:-$DUMP/0400C3F00006E000_build}"
[ $# -ge 2 ] || { sed -n '2,12p' "$0"; exit 1; }
O=$1; shift; : > "$O"
clean() { rm -rf "$(getconf DARWIN_USER_CACHE_DIR)com.apple.gpuarchiver"/gpuarchiver-* 2>/dev/null; }
bundle() {   # <folder under <build>/gm> <bundle id> <true|false> <host binary>: prints the bundle's host
  A="$B/gm/$1/MKW Test.app"
  if [ ! -x "$A/Contents/MacOS/dmhost" ] || [ "$4" -nt "$A/Contents/MacOS/dmhost" ]; then "$ROOT/mkw/test/mkbundle.sh" "$A" "$2" "$3" "$4" > /dev/null || return 1; fi
  echo "$A/Contents/MacOS/dmhost"
}
cd "$ROOT" || exit 1
for r in "$@"; do
  label=${r%%|*}; rest=${r#*|}; route=${rest%%|*}; rest=${rest#*|}; host=${rest%%|*}; extra=${rest#*|}; [ "$extra" = "$rest" ] && extra=""
  case $host in
    gm) H=$(bundle gm org.nxnative.mkwgmtest true "$B/tools/dmhost");;
    nogm) H=$(bundle nogm org.nxnative.mkwnogmtest false "$B/tools/dmhost");;
    gm-*) H=$(bundle "v-${host#gm-}" org.nxnative.mkwgmtest true "$B/variants/${host#gm-}/dmhost");;
    /*) H=$host;;
    *) echo "unknown host $host" >> "$O"; continue;;
  esac
  [ -n "$H" ] && [ -x "$H" ] || { echo "no host for $label ($host)" >> "$O"; continue; }
  case $route in 1) R=gp-start-150;; 2|3|4) R=gp150-${route}p;; *) R=$route;; esac
  C=""; [ -f "$ROOT/mkw/test/routes/$R.ctl" ] && C="--env MKW_CTL_SCRIPT=$ROOT/mkw/test/routes/$R.ctl"
  echo "start $label $(date +%H:%M:%S)" >> "$O"
  # shellcheck disable=SC2086
  mkw/test/bench.sh --route "$R" --runs 1 --no-hud $C ${FX_ENV:+--env "$FX_ENV"} --variant "$label:host=$ROOT/mkw/test/host_open.py,MKW_REAL_HOST=$H${extra:+,$extra}" >> "$O" 2>&1
  /usr/bin/log show --last 30m --predicate 'process == "gamepolicyd"' --style compact 2>/dev/null | grep "gamepolicyd:Common" | grep -E "Found game|Game mode status|Full screen gaming" | tail -6 | sed -E 's/gamepolicyd\[[0-9]+:[0-9a-f]+\] //' | cut -c1-200
  clean; echo "finished $label $(date +%H:%M:%S)" >> "$O"
done
echo done >> "$O"
