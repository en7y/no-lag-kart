#!/usr/bin/env python3
"""From a `sample` report: for the thread named by a substring, the samples by symbol under a given ancestor symbol (inclusive, each node counted at its topmost
occurrence under that ancestor), at a given depth below it.  usage: sample_kids.py <report> <thread substring> <ancestor symbol prefix> [levels below, default 1] [min samples]"""
import sys, re, collections
rep, tname, anc = sys.argv[1], sys.argv[2], sys.argv[3]; lev = int(sys.argv[4]) if len(sys.argv) > 4 else 1; mn = int(sys.argv[5]) if len(sys.argv) > 5 else 10
lines = open(rep, errors="replace").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("Call graph:"))
node = re.compile(r"^(\s+[+!:| ]*?)(\d+) (.+?)(?:  \(in ([^)]*)\))?(?: \+ [\d,.]+)?(?:  \[0x[0-9a-f,.x]+\])?\s*$")
cur = None; nodes = []
for l in lines[start + 1:]:
    if l.startswith("Total number in stack") or l.startswith("Sort by top of stack"): break
    m = re.match(r"^    (\d+) (Thread_\S+.*)$", l)
    if m: cur = m.group(2); continue
    if cur and tname in cur:
        m = node.match(l)
        if m: nodes.append((len(m.group(1)), int(m.group(2)), re.sub(r"  \(in .*$", "", m.group(3)).strip()))
tot = collections.Counter(); stack = []
for d, n, s in nodes:
    while stack and stack[-1][0] >= d: stack.pop()
    # position of the nearest ancestor that matches, counting levels below it
    idx = max((i for i, x in enumerate(stack) if x[2].startswith(anc)), default=None)
    if idx is not None and len(stack) - idx == lev and not s.startswith(anc): tot[s] += n
    stack.append((d, n, s))
allanc = sum(n for i, (d, n, s) in enumerate(nodes) if s.startswith(anc) and not any(True for _ in ()))  # rough
print(f"thread *{tname}*: {len(nodes)} nodes; samples by symbol {lev} level(s) below {anc}* (>= {mn}):")
for s, n in tot.most_common(60):
    if n >= mn: print(f"{n:7d}  {s[:110]}")
