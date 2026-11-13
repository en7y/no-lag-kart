#!/usr/bin/env python3
# lates.py <from> <secs> <run name>...: the late frames of a bench run's window (game frames over 1.5 steps), the first 14 each with its time, length, GPU work,
# replay CPU and wall time, waits, new pipelines, uploads, how long the screen showed it (16.7 or 33.3 = the player saw nothing), and the render-target megabytes.
# The run: the newest <build>/bench/*/<name>-1 (the build folder as in fxsum.py).
import os, sys, pathlib, statistics
ROOT = pathlib.Path(__file__).resolve().parents[2]
B = pathlib.Path(os.environ.get('MKW_BUILD') or pathlib.Path(os.environ.get('MKW_DUMP') or ROOT.parent / 'MarioKartWorld') / '0400C3F00006E000_build') / 'bench'
if len(sys.argv) < 4: sys.exit('usage: lates.py <from> <secs> <run name>...')
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
    late = [k for k in sel if g('@frame_ms', k) > step * 1.5]
    print(f'{name}: {len(late)} late of {len(sel)} frames (over {step * 1.5:.0f} ms)')
    for k in late[:14]:
        print(f'   {t[k]:7.2f} s frame {k}: {g("@frame_ms", k):5.1f} ms; GPU {g("@gpu_ms", k):5.1f}, replay CPU {g("@sub_cpu_ms", k):5.1f} wall {g("@sub_wall_ms", k):5.1f}, game work {g("@work_ms", k):5.1f}, acquire wait {g("@wait_ms", k):5.1f}, pq wait {g("@pq_wait_ms", k):4.1f}, sync {g("@sync_ms", k):4.1f}, new pso {g("@pso_new", k):.0f}, uploads {g("@upload_ms", k):4.1f} ms, shown {g("@presented_ms", k):5.1f}, rtMB {g("@rt_store_mb", k):4.0f}')
