#!/bin/sh
# A host for scripts/bench.py's `host=` that also plays a control script (mkw/test/ctl_feed.py) from the host's start: players 2 to 8 with the test host.
#   mkw/test/bench.sh --route <route> --env MKW_REAL_HOST=<build>/variants/test/dmhost --env MKW_CTL_SCRIPT=$PWD/mkw/test/routes/<file>.ctl \
#                     --variant "4p:host=$PWD/mkw/test/host_with_ctl.sh"
# bench.py sets DM_CTL (its own control file, where it also asks for its screenshots); the feeder appends to the same file. The host replaces this shell
# (exec), so bench.py's signals reach it, and the feeder ends when the host does. Both paths absolute: the host runs in the run's own folder.
set -eu
: "${MKW_REAL_HOST:?MKW_REAL_HOST: the host binary to run}"
if [ -n "${MKW_CTL_SCRIPT:-}" ] && [ -n "${DM_CTL:-}" ]; then
  python3 "$(dirname "$0")/ctl_feed.py" "$DM_CTL" "$MKW_CTL_SCRIPT" &
fi
exec "$MKW_REAL_HOST" "$@"
