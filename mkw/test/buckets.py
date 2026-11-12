#!/usr/bin/env python3
"""A bench run's frames.tsv in buckets of time: frames, GPU time, attachment megabytes (the game's render size), late frames. usage: buckets.py <run folder> [--from T0] [--secs N] [--step S]"""
import sys, os, collections, argparse
ap = argparse.ArgumentParser(); ap.add_argument('runs', nargs='+'); ap.add_argument('--from', dest='t0', type=float, default=0); ap.add_argument('--secs', type=float, default=1e9); ap.add_argument('--step', type=float, default=10)
a = ap.parse_args()
def pct(v, p): v = sorted(v); return v[min(len(v) - 1, int(p * len(v)))] if v else 0
for r in a.runs:
    f = r if r.endswith('.tsv') else os.path.join(r, 'frames.tsv')
    rows = collections.defaultdict(dict)
    for l in open(f, errors='replace'):
        c = l.rstrip('\n').split('\t')
        if len(c) == 3 and c[1].startswith('@'):
            try: rows[int(c[0])][c[1]] = float(c[2])
            except ValueError: pass
    fr = [d for n, d in sorted(rows.items()) if a.t0 <= d.get('@t_s', -1) < a.t0 + a.secs]
    print(os.path.basename(os.path.dirname(f)) or f)
    print('   from s  frames  gpu p50   p95  rt MB p50  draws  shown: 16.7  25.0  33.3  41.7  50.0  other')
    b = collections.defaultdict(list)
    for d in fr: b[int((d['@t_s'] - a.t0) // a.step)].append(d)
    for k in sorted(b):
        v = b[k]; g = [d.get('@gpu_ms', 0) for d in v]; m = [d.get('@rt_load_mb', 0) + d.get('@rt_store_mb', 0) for d in v]; dr = [d.get('@draws', 0) for d in v]
        sh = collections.Counter(round(d.get('@presented_ms', -1), 1) for d in v)
        known = [16.7, 25.0, 33.3, 41.7, 50.0]
        print(f"  {a.t0 + k * a.step:7.0f} {len(v):7d} {pct(g, .5):8.2f} {pct(g, .95):5.2f} {pct(m, .5):10.0f} {pct(dr, .5):6.0f}        " + ' '.join(f'{sh.get(x, 0):5d}' for x in known) + f" {sum(n for x, n in sh.items() if x not in known and x > 0):6d}")
