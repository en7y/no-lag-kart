#!/usr/bin/env python3
"""From a `sample` report: self time and inclusive time by symbol for the thread named by a substring. usage: sample_self.py <report> <thread substring> [top n]"""
import sys, re, collections
rep, tname = sys.argv[1], sys.argv[2]; top = int(sys.argv[3]) if len(sys.argv) > 3 else 40
lines = open(rep, errors="replace").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("Call graph:"))
node = re.compile(r"^(\s+[+!:| ]*?)(\d+) (.+?)(?:  \(in ([^)]*)\))?(?: \+ [\d,.]+)?(?:  \[0x[0-9a-f,.x]+\])?\s*$")
cur = None; nodes = []; total = 0
for l in lines[start + 1:]:
    if l.startswith("Total number in stack") or l.startswith("Sort by top of stack"): break
    m = re.match(r"^    (\d+) (Thread_\S+.*)$", l)
    if m: cur = m.group(2); total = int(m.group(1)) if tname in cur else total; continue
    if cur and tname in cur:
        m = node.match(l)
        if m: nodes.append([len(m.group(1)), int(m.group(2)), re.sub(r"  \(in .*$", "", m.group(3)).strip(), m.group(4) or ''])
selfc = collections.Counter(); incl = collections.Counter(); lib = {}
stack = []
for i, (d, n, s, lb) in enumerate(nodes):
    while stack and stack[-1][0] >= d: stack.pop()
    if stack: stack[-1][4] += n
    ent = [d, n, s, lb, 0]; nodes[i].append(ent); stack.append(ent)
    if not any(x[2] == s for x in stack[:-1]): incl[s] += n
    lib[s] = lb
for d, n, s, lb, ent in nodes: selfc[s] += n - ent[4]
print(f"thread *{tname}*: {total} samples")
print("self time:")
for s, c in selfc.most_common(top): print(f"  {c:6d} {100.0 * c / total:5.1f}%  {s[:90]}  ({lib.get(s, '')[:28]})")
print("inclusive:")
for s, c in incl.most_common(top): print(f"  {c:6d} {100.0 * c / total:5.1f}%  {s[:90]}")
