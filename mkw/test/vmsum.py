#!/usr/bin/env python3
"""Memory pressure rows of a bench run's frames.tsv (@majflt, @minflt, @decomp, @swapin_kb, @compressed_mb): their rates over a window and the frames that took longest.
usage: vmsum.py <run folder or frames.tsv> ... [--from T0] [--secs N] [--long MS]"""
import sys, os, collections, argparse
ap = argparse.ArgumentParser(); ap.add_argument('runs', nargs='+'); ap.add_argument('--from', dest='t0', type=float, default=0); ap.add_argument('--secs', type=float, default=1e9); ap.add_argument('--long', type=float, default=0)
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
    fr = [(n, d) for n, d in sorted(rows.items()) if a.t0 <= d.get('@t_s', -1) < a.t0 + a.secs]
    if not fr: print(f, 'no frames in the window'); continue
    span = fr[-1][1]['@t_s'] - fr[0][1]['@t_s'] or 1
    tot = lambda k: sum(d.get(k, 0) for _, d in fr)
    dec = [d.get('@decomp', 0) for _, d in fr]; mn = [d.get('@minflt', 0) for _, d in fr]
    cm = [d['@compressed_mb'] for _, d in fr if '@compressed_mb' in d]
    print(f"{os.path.basename(os.path.dirname(f)) or f}: {len(fr)} frames over {span:.1f} s; a second: {tot('@decomp') / span:.0f} decompressions, {tot('@majflt') / span:.1f} page-ins, {tot('@minflt') / span:.0f} other faults, "
          f"{tot('@swapin_kb') / span:.0f} KB from swap; decompressions a frame p50 {pct(dec, .5):.0f} p95 {pct(dec, .95):.0f} max {max(dec):.0f}; other faults p50 {pct(mn, .5):.0f} p95 {pct(mn, .95):.0f} max {max(mn):.0f}; "
          f"compressed {cm[0]:.0f} -> {cm[-1]:.0f} MB" if cm else f"{f}: no memory rows")
    ms = [d.get('@frame_ms', 0) for _, d in fr]; lim = a.long or max(pct(ms, .5) * 1.4, pct(ms, .99))
    worst = sorted(fr, key=lambda x: -x[1].get('@frame_ms', 0))[:12]
    print(f"  longest frames (at least {lim:.1f} ms shown, 12 at most): time s / frame ms / replay ms / decompressions / page-ins / other faults / swap KB")
    for n, d in sorted(worst):
        if d.get('@frame_ms', 0) < lim: continue
        print(f"    {d['@t_s']:8.2f} {d.get('@frame_ms', 0):7.1f} {d.get('@sub_wall_ms', 0):7.1f} {d.get('@decomp', 0):7.0f} {d.get('@majflt', 0):5.0f} {d.get('@minflt', 0):7.0f} {d.get('@swapin_kb', 0):7.0f}")
    # do long frames carry more decompressions than the others?
    lo = [d.get('@decomp', 0) for _, d in fr if d.get('@frame_ms', 0) < lim]; hi = [d.get('@decomp', 0) for _, d in fr if d.get('@frame_ms', 0) >= lim]
    if hi and lo: print(f"  decompressions a frame: {sum(hi) / len(hi):.0f} in the {len(hi)} frames of {lim:.1f} ms or more, {sum(lo) / len(lo):.0f} in the other {len(lo)}")
