#!/bin/sh
# What a run's log says, by the tags the host writes: errors, the frame step (holds, game time against real time), long frames, memory, pipelines.
# Usage: mkw/test/logsum.sh <log.txt> [<log.txt> ...]     (a bench run's logs are <build>/bench/<time>/<variant>-<run>/log.txt)
# The line formats are the host's own and change with it: this script only counts and shows lines, it computes nothing from them.
for f in "$@"; do
  echo "=== $f ($(wc -l < "$f" | tr -d ' ') lines)"
  n=$(grep -c '\[RED\]' "$f"); echo "[RED] lines: $n"
  grep '\[RED\]' "$f" | sed 's/[0-9][0-9.]*/N/g' | sort | uniq -c | sort -rn | head -8 | cut -c1-220
  echo "-- frame step"
  grep -c 'frame step: hold' "$f" | sed 's/^/hold changes: /'
  grep 'frame step: the game takes steps\|frame step: frames are not held' "$f" | head -2 | cut -c1-200
  grep 'frame step: game time' "$f" | tail -4 | sed 's/.*frame step: //' | cut -c1-230
  grep -c 'one-off frame' "$f" | sed 's/^/one-off frames logged: /'
  echo "-- long frames"
  grep -c '\[longframe\]' "$f" | sed 's/^/[longframe] lines: /'
  grep '\[longframe\]' "$f" | tail -3 | cut -c1-230
  echo "-- memory"
  grep '\[mem\]' "$f" | tail -4 | cut -c1-230
  grep -i 'MapPhysicalMemory.*refused' "$f" | wc -l | sed 's/^ */map refusals (mem_map_limit at work): /'
  grep -i 'out of memory\|OutOfMemory\|residency' "$f" | tail -3 | cut -c1-230
  echo "-- pipelines and shaders"
  grep 'pipeline prewarm list\|pipeline prepare:\|prewarm done\|pipeline archive' "$f" | head -8 | cut -c1-260
  grep 'pipelines up to frame' "$f" | tail -2 | cut -c1-400
  grep -ci 'compiled at first use\|first-use\|built at its first draw' "$f" | sed 's/^/first-use compile lines: /'
  echo "-- resolution and pacing"
  grep -i 'dynamic resolution\|scene [0-9]*x[0-9]*\|display link\|Game Mode\|GPU clock' "$f" | tail -5 | cut -c1-230
  echo "-- controllers"
  grep -i "controller '\|controller connected\|controller applet\|hid supported\|DM_CTL: player" "$f" | tail -6 | cut -c1-200
done
