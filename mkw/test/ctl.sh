#!/bin/sh
# Drives a running game through its control file (DM_CTL), one step per argument, in order:
#   mkw/test/ctl.sh A  wait:2  L+R  shot:title  "A~9.5"  p2:A  sheet:menus:m1,m2,m3,m4
#   <keys>              a press as DM_CTL takes it (A, B, L+R, LUp~0.5, …; p2: … p8: with the test host)
#   wait:<s>            sleep
#   shot:<name>         a screenshot of the next frame: <shots>/<name>.png (the whole window texture) and <name>.jpg (the picture alone, 640 wide)
#   sheet:<name>:<a>,…  up to four shots side by side in one image, <shots>/<name>.jpg (to look at a sequence at once)
# CTL names the control file (default /tmp/mkw.ctl), SHOTS the folder (default /tmp/mkw-shots). The game draws into the top left of a 3840x2160 window
# texture: CROP is that part (handheld mode 1920:1080, the default; docked CROP=2048:1152). Needs ffmpeg.
CTL="${CTL:-/tmp/mkw.ctl}"; SHOTS="${SHOTS:-/tmp/mkw-shots}"; CROP="${CROP:-1920:1080}"; mkdir -p "$SHOTS"
for s in "$@"; do
  case "$s" in
    wait:*) sleep "${s#wait:}";;
    shot:*) n="${s#shot:}"; rm -f "$SHOTS/$n.png" "$SHOTS/$n.jpg"; echo "shot $SHOTS/$n.png" >> "$CTL"
            i=0; while [ ! -s "$SHOTS/$n.png" ] && [ $i -lt 40 ]; do sleep 0.25; i=$((i + 1)); done; sleep 0.3
            if [ -s "$SHOTS/$n.png" ]; then ffmpeg -loglevel error -y -i "$SHOTS/$n.png" -vf "crop=$CROP:0:0,scale=640:-1" -q:v 7 "$SHOTS/$n.jpg" && echo "shot $SHOTS/$n.jpg"; else echo "no screenshot $n (is the game presenting frames?)"; fi;;
    sheet:*) r="${s#sheet:}"; n="${r%%:*}"; set -f; IFS=,; in=""; k=0; for a in ${r#*:}; do in="$in -i $SHOTS/$a.jpg"; k=$((k + 1)); done; unset IFS; set +f
            if [ $k -ge 4 ]; then lay="xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0"; elif [ $k -eq 1 ]; then lay="copy"; else lay="hstack=inputs=$k"; fi
            # shellcheck disable=SC2086
            ffmpeg -loglevel error -y $in -filter_complex "$lay" -q:v 7 "$SHOTS/$n.jpg" && echo "sheet $SHOTS/$n.jpg";;
    *) echo "$s" >> "$CTL"; sleep 0.4;;
  esac
done
