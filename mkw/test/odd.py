#!/usr/bin/env python3
# odd.py <from> <secs> <run name>...: the frames of a bench run's window whose on-screen interval is more than 2 ms off its step or that were never shown (what a
# player can see), the first 8 with their neighbours. The run: the newest <build>/bench/*/<name>-1 (the build folder as in fxsum.py).
import os, sys, pathlib, statistics
ROOT = pathlib.Path(__file__).resolve().parents[2]
B = pathlib.Path(os.environ.get('MKW_BUILD') or pathlib.Path(os.environ.get('MKW_DUMP') or ROOT.parent / 'MarioKartWorld') / '0400C3F00006E000_build') / 'bench'
if len(sys.argv) < 4: sys.exit('usage: odd.py <from> <secs> <run name>...')
t0, secs = float(sys.argv[1]), float(sys.argv[2])
for name in sys.argv[3:]:
    runs = sorted(B.glob(f'*/{name}-1'))
    if not runs: print(name, 'no run'); continue
    col = {}
    for line in (runs[-1] / 'frames.tsv').open():
        p = line.rstrip('\n').split('\t')
        if len(p) == 3 and p[1].startswith('@'):
            try: col.setdefault(p[1], {})[int(p[0])] = float(p[2])
            except ValueError: pass
    t = col['@t_s']; sel = sorted(k for k, v in t.items() if t0 <= v < t0 + secs)
    itv = [col['@itv'][k] for k in sel if k in col.get('@itv', {})]; step = 16.667 * (statistics.median(itv) if itv else 1)
    g = lambda n, k: col.get(n, {}).get(k, float('nan'))
    odd = [k for k in sel if g('@presented_ms', k) < 0 or abs(g('@presented_ms', k) - step) > 2]
    print(f'{name}: {len(odd)} of {len(sel)} frames off the {step:.1f} ms step or not shown')
    for k in odd[:8]:
        print(f'   {t[k]:7.2f} s frame {k}:')
        for j in range(k - 2, k + 3):
            print(f'      {j}: frame {g("@frame_ms", j):5.1f} on screen {g("@presented_ms", j):6.1f} GPU {g("@gpu_ms", j):5.1f} game work {g("@work_ms", j):5.1f} replay cpu {g("@sub_cpu_ms", j):5.1f} wall {g("@sub_wall_ms", j):5.1f} link lead {g("@link_lead_ms", j):5.1f} ticks {g("@link_ticks", j):3.0f} late {g("@late_ms", j):5.1f}')
