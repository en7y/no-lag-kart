#!/bin/sh
# gmprobe.sh <app bundle>: does macOS's Game Mode daemon (gamepolicyd) take this bundle for a game? Starts it through LaunchServices and prints the daemon's lines of
# the moment; "Found game … labelReason=infoPlist" comes within a second of the start, before the app has drawn anything. A bare host in a bundle
# (mkw/test/mkbundle.sh) prints its usage and ends at once, so the probe costs nothing; a packed app is started with --no-launcher and SOUND OFF and keeps running:
# quit it yourself. What the probes of 2026-11-13 showed is in mkw/KNOWLEDGE.md, section 0: the daemon keeps its verdict on a bundle until the bundle folder's
# modification date changes, so after changing LSSupportsGameMode in place: touch "<App>.app".
A=$1
[ -d "$A/Contents" ] || { sed -n '2,6p' "$0"; exit 1; }
T0=$(date "+%Y-%m-%d %H:%M:%S")
plutil -p "$A/Contents/Info.plist" | grep -E "GameMode|CFBundleIdentifier\"" | tr '\n' ' '; echo
open -n -a "$A" --env DM_AUDIO=0 --args --no-launcher 2>&1
sleep 3
/usr/bin/log show --start "$T0" --predicate 'process == "gamepolicyd"' --style compact 2>/dev/null | grep "gamepolicyd:Common" | grep -v "session caches" | sed -E 's/gamepolicyd\[[0-9]+:[0-9a-f]+\] //' | cut -c1-200 | head -8
echo "$(basename "$A"): $(/usr/bin/log show --start "$T0" --predicate 'process == "gamepolicyd"' --style compact 2>/dev/null | grep -c "Found game") 'Found game' line(s) since $T0"
