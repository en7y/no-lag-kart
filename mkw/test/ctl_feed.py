#!/usr/bin/env python3
"""Appends lines to the host's control file (DM_CTL) at fixed seconds from now: the scripted input of players 2 to 8 (the test host's "p<n>:keys~hold" lines,
branch mkw-test), screenshots ("shot <path>") and anything else DM_CTL takes. Player 1 keeps DM_KEYS.

  ctl_feed.py <control file> <script>        script: one line per step, "<seconds> <control line>", # comments; e.g.
      40   p2:A
      40.5 p3:A
      41   p4:A
      120  p2:A~60
  It ends with its last line, or when the process that started it is gone (the host, when mkw/test/host_with_ctl.sh starts it)."""
import os, sys, time

ctl, script = sys.argv[1], sys.argv[2]
steps = []
for ln in open(script):
    ln = ln.strip()
    if not ln or ln.startswith('#'): continue
    t, _, line = ln.partition(' ')
    steps.append((float(t), line.strip()))
steps.sort(key=lambda s: s[0])
t0, parent = time.monotonic(), os.getppid()
for t, line in steps:
    while time.monotonic() - t0 < t:
        if os.getppid() != parent: sys.exit(0)   # the host ended
        time.sleep(0.05)
    with open(ctl, 'a') as f: f.write(line + '\n')
