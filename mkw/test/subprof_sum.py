#!/usr/bin/env python3
"""DM_SUBPROF's stacks in a log, by frame: for the frames with the most stacks, the time by innermost symbol and inclusive by symbol (a stack is 0.4 ms).
usage: subprof_sum.py <log.txt> [frames to show, default 1] [rows, default 22]"""
import sys, re, collections
log = sys.argv[1]; NF = int(sys.argv[2]) if len(sys.argv) > 2 else 1; ROWS = int(sys.argv[3]) if len(sys.argv) > 3 else 22
fr = collections.defaultdict(list); cur = None
for l in open(log, errors='replace'):
    if '[subprof]' not in l: continue
    m = re.search(r'\[subprof\] frame (\d+): ([0-9.]+) ms of replays so far', l)
    if m: cur = int(m.group(1)); continue
    m = re.search(r'\[subprof\]\s+([0-9.]+) ms x(\d+)\s+(.*)$', l)
    if m and cur is not None: fr[cur].append((float(m.group(1)), int(m.group(2)), [s.strip() for s in m.group(3).split(' < ')]))
tot = {f: sum(n for _, n, _ in v) for f, v in fr.items()}
for f in sorted(tot, key=lambda f: -tot[f])[:NF]:
    v = fr[f]; n = tot[f]
    print(f"frame {f}: {n} stacks ({n * 0.4:.1f} ms) from {v[0][0]:.1f} to {v[-1][0]:.1f} ms into its replays")
    inner = collections.Counter(); incl = collections.Counter()
    for _, k, st in v:
        inner[st[0]] += k
        for s in set(st): incl[s] += k
    print("  innermost:"); [print(f"    {c * 0.4:6.1f} ms  {s[:110]}") for s, c in inner.most_common(ROWS)]
    print("  inclusive:"); [print(f"    {c * 0.4:6.1f} ms  {s[:110]}") for s, c in incl.most_common(ROWS + 12)]
