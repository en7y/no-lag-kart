#!/usr/bin/env python3
"""The replay's cost of bench runs in a window: instructions, CPU and wall time a frame and a draw (medians). usage: instr.py <from> <secs> <run name>..."""
import sys, os, glob, collections
B = os.environ.get('MKW_BENCH') or os.path.join(os.environ.get('MKW_DUMP') or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'MarioKartWorld'), '0400C3F00006E000_build', 'bench')   # as prep_probe.sh finds the dump
t0, secs = float(sys.argv[1]), float(sys.argv[2])
def med(v): v = sorted(v); return v[len(v) // 2] if v else 0
print(f"{'run':10s} frames  instr M/frame  instr/draw  cpu ms  wall ms  cpu us/draw   draws  late(>1 step)")
for name in sys.argv[3:]:
    d = sorted(glob.glob(f'{B}/*/{name}-1'))
    if not d: print(f'{name:10s} no run'); continue
    rows = collections.defaultdict(dict)
    for l in open(d[-1] + '/frames.tsv', errors='replace'):
        c = l.rstrip('\n').split('\t')
        if len(c) == 3 and c[1].startswith('@'):
            try: rows[int(c[0])][c[1]] = float(c[2])
            except ValueError: pass
    fr = [r for _, r in sorted(rows.items()) if t0 <= r.get('@t_s', -1) < t0 + secs and r.get('@draws', 0) > 0]
    ins = [r.get('@sub_instr', 0) / 1e6 for r in fr]; ipd = [r.get('@sub_instr', 0) / r['@draws'] for r in fr]
    cpu = [r.get('@sub_cpu_ms', 0) for r in fr]; wall = [r.get('@sub_wall_ms', 0) for r in fr]; upd = [r.get('@sub_cpu_ms', 0) * 1000 / r['@draws'] for r in fr]
    sh = sorted(r.get('@presented_ms', 0) for r in fr); step = med(sh); late = sum(1 for x in sh if x > step * 1.2)
    print(f"{name:10s} {len(fr):6d} {med(ins):13.1f} {med(ipd):11.0f} {med(cpu):7.2f} {med(wall):8.2f} {med(upd):12.2f} {med([r['@draws'] for r in fr]):7.0f}  {late}")
