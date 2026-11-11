#!/bin/sh
# Drives a running game through its control file (DM_CTL), one step per argument, in order:
#   mkw/test/ctl.sh A  wait:2  L+R  shot:title  "A~9.5"  p2:A
#   <keys>        a press as DM_CTL takes it (A, B, L+R, LUp~0.5, …; p2: … p8: with the test host)
#   wait:<s>      sleep
#   shot:<name>   a screenshot of the next frame, saved as <shots>/<name>.png and, 640 wide, <name>.jpg (for a quick look)
# CTL names the control file (default /tmp/mkw.ctl), SHOTS the folder (default /tmp/mkw-shots).
CTL="${CTL:-/tmp/mkw.ctl}"; SHOTS="${SHOTS:-/tmp/mkw-shots}"; mkdir -p "$SHOTS"
for s in "$@"; do
  case "$s" in
    wait:*) sleep "${s#wait:}";;
    shot:*) n="${s#shot:}"; rm -f "$SHOTS/$n.png"; echo "shot $SHOTS/$n.png" >> "$CTL"
            i=0; while [ ! -s "$SHOTS/$n.png" ] && [ $i -lt 40 ]; do sleep 0.25; i=$((i + 1)); done; sleep 0.3
            if [ -s "$SHOTS/$n.png" ]; then sips -s format jpeg -s formatOptions 60 -Z 640 "$SHOTS/$n.png" --out "$SHOTS/$n.jpg" >/dev/null 2>&1 && echo "shot $SHOTS/$n.jpg"; else echo "no screenshot $n (is the game presenting frames?)"; fi;;
    *) echo "$s" >> "$CTL"; sleep 0.4;;
  esac
done
