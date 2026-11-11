#!/usr/bin/env python3
# What is different about the frames that came late? For one run's frames.tsv: the frames whose predecessor stayed on screen 25 ms or more (they missed their refresh)
# against the others, column by column (medians), with the columns that differ most first.
# Usage: mkw/test/late.py <run folder with frames.tsv> [--from 110] [--secs 90]
import argparse, math, pathlib, statistics, sys
ap = argparse.ArgumentParser(); ap.add_argument('run'); ap.add_argument('--from', dest='t0', type=float, default=110); ap.add_argument('--secs', type=float, default=90); a = ap.parse_args()
rows = {}
for ln in open(pathlib.Path(a.run) / 'frames.tsv', errors='replace'):
    c = ln.rstrip('\n').split('\t')
    if len(c) != 3 or not c[1].startswith('@'): continue
    try: rows.setdefault(int(c[0]), {})[c[1]] = float(c[2])
    except ValueError: pass
fs = sorted(f for f, r in rows.items() if '@t_s' in r and a.t0 <= r['@t_s'] < a.t0 + a.secs)
for f in fs:
    r = rows[f]
    if '@gpu_end_ms' in r and '@gpu_beg_ms' in r: r['span'] = r['@gpu_end_ms'] - r['@gpu_beg_ms']
    if '@gpu_end_ms' in r and '@call_ms' in r: r['gpu end after present call'] = r['@gpu_end_ms'] - r['@call_ms']
    if '@gpu_beg_ms' in r and '@call_ms' in r: r['gpu begin before present call'] = r['@call_ms'] - r['@gpu_beg_ms']
late = [f for f in fs if rows[f].get('@presented_ms', 0) >= 25]
# the frame that missed is the one after a frame that stayed up long; look at both it and the one before it
print(f'{a.run}: {len(fs)} frames, {len(late)} stayed on screen 25 ms or more')
for name, pick in (('the frame that stayed up long', 0), ('the frame after it (the one that came late)', 1), ('the frame before it', -1)):
    sel = [rows[f + pick] for f in late if f + pick in rows]; rest = [rows[f] for f in fs if f not in set(x + pick for x in late)]
    cols = sorted(set(k for r in sel for k in r) - {'@t_s', '@call_ms', '@gpu_beg_ms', '@gpu_end_ms', '@pres_at_ms', '@link_target_ms'})
    out = []
    for k in cols:
        x = [r[k] for r in sel if k in r]; y = [r[k] for r in rest if k in r]
        if len(x) < 5 or len(y) < 5: continue
        mx, my = statistics.median(x), statistics.median(y)
        iqr = (sorted(y)[3 * len(y) // 4] - sorted(y)[len(y) // 4]) or 1e-9
        out.append((abs(mx - my) / iqr, k, mx, my))
    print(f'  {name}: median there / median of the other frames (the columns that differ most, in units of the others\' spread)')
    for d, k, mx, my in sorted(out, reverse=True)[:9]: print(f'     {k:<30} {mx:>10.2f} / {my:<10.2f} ({d:.1f})')
