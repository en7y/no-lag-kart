#!/usr/bin/env python3
# mempeak.py <DM_MEMSTAT tsv>...: for each run, the row at its highest footprint (every column, MiB; class columns as virtual/resident/charged), and the highest of
# Metal's allocated size, the compressed part and the graphics ledger, with the second they came at
import sys
for p in sys.argv[1:]:
    head = None; rows = []
    for l in open(p):
        if l.startswith('#'): continue
        c = l.rstrip('\n').split('\t')
        if head is None: head = c; continue
        try: float(c[0]); rows.append(c)
        except ValueError: pass
    ci = {h: i for i, h in enumerate(head)}
    num = lambda r, h: float(r[ci[h]].split('/')[-1])
    top = max(rows, key=lambda r: num(r, 'phys_footprint'))
    print(f'{p}: {len(rows)} rows; at the highest footprint ({float(top[0]):.0f} s):')
    print('   ' + '  '.join(f'{h}={top[ci[h]]}' for h in head[1:]))
    for h in ('metal_alloc', 'compressed', 'graphics', 'internal'):
        if h in ci:
            r = max(rows, key=lambda r: num(r, h)); print(f'   highest {h} {num(r, h):.0f} at {float(r[0]):.0f} s')
