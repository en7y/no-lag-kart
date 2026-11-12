#!/usr/bin/env python3
"""From a `sample` report: for a thread (substring), who calls the given symbols: samples by (caller, callee). usage: sample_callers.py <report> <thread> <symbol>[,<symbol>...] [top n]"""
import sys, re, collections
rep, tname, syms = sys.argv[1], sys.argv[2], set(sys.argv[3].split(',')); top = int(sys.argv[4]) if len(sys.argv) > 4 else 30
lines = open(rep, errors='replace').read().split('\n')
start = next(i for i, l in enumerate(lines) if l.startswith('Call graph:'))
node = re.compile(r'^(\s+[+!:| ]*?)(\d+) (.+?)(?:  \(in ([^)]*)\))?(?: \+ ([\d,.]+))?(?:  \[0x[0-9a-f,.x]+\])?\s*$')
cur = None; stack = []; by = collections.Counter(); tot = collections.Counter()
for l in lines[start + 1:]:
    if l.startswith('Total number in stack') or l.startswith('Sort by top of stack'): break
    m = re.match(r'^    (\d+) (Thread_\S+.*)$', l)
    if m: cur = m.group(2); stack = []; continue
    if cur is None or tname not in cur: continue
    m = node.match(l)
    if not m: continue
    d, n, s = len(m.group(1)), int(m.group(2)), m.group(3).strip()
    while stack and stack[-1][0] >= d: stack.pop()
    if s in syms:
        k = len(stack) - 1
        while k >= 0 and (stack[k][1] in syms or stack[k][1].startswith('objc_') or stack[k][1].startswith('DYLD-STUB')): k -= 1
        by[(stack[k][1] if k >= 0 else '?', s)] += n; tot[s] += n
    stack.append((d, s))
for s in sorted(tot, key=lambda x: -tot[x]): print(f'{s}: {tot[s]}')
agg = collections.Counter()
for (c, s), n in by.items(): agg[c] += n
print('by caller (all the symbols together):')
for c, n in agg.most_common(top): print(f'  {n:6d}  {c}')
