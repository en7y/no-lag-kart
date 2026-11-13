#!/usr/bin/env python3
# soaksum.py <from> <secs> <run name>...: a long bench run (a whole Grand Prix) in one screen. Of its window: frames and frame rate; the frames on screen off their
# step (longer or shorter by more than 2 ms: what a player can see) and never shown; late game frames; the longer ones by kind (beside a cut: a frame within 3 of it
# uploads textures, takes over 60 ms or draws a near-empty screen; else while driving) and by minute; the GPU's median by minute; new pipelines; swap-ins and
# compressed memory; the footprint lines of the log. The frames it names (time: ms on screen / the game frame's ms) are the ones to look up in the system's log:
# on a 16 GB Mac a frame of 80 to 220 ms with next to no work in it fell each time into a sweep of the kernel ending idle daemons for memory
# (`log show --predicate 'process == "kernel" AND eventMessage CONTAINS "killing_idle_process"'`; mkw/KNOWLEDGE.md, section 0).
# The run: the newest <build>/bench/*/<name>-1 (the build folder as in fxsum.py).
import os, sys, re, pathlib, statistics, collections
ROOT = pathlib.Path(__file__).resolve().parents[2]
B = pathlib.Path(os.environ.get('MKW_BUILD') or pathlib.Path(os.environ.get('MKW_DUMP') or ROOT.parent / 'MarioKartWorld') / '0400C3F00006E000_build') / 'bench'
if len(sys.argv) < 4: sys.exit('usage: soaksum.py <from> <secs> <run name>...')
t0, secs = float(sys.argv[1]), float(sys.argv[2])
def pct(v, p): v = sorted(v); return v[min(len(v) - 1, int(len(v) * p / 100))] if v else float('nan')
for name in sys.argv[3:]:
    runs = sorted(B.glob(f'*/{name}-1'))
    if not runs: print(name, 'no run'); continue
    run = runs[-1]; col = {}
    for line in (run / 'frames.tsv').open():
        p = line.rstrip('\n').split('\t')
        if len(p) == 3 and p[1].startswith('@'):
            try: col.setdefault(p[1], {})[int(p[0])] = float(p[2])
            except ValueError: pass
    t = col['@t_s']; sel = sorted(k for k, v in t.items() if t0 <= v < t0 + secs)
    if not sel: print(name, 'no frames in the window'); continue
    g = lambda n, k: col.get(n, {}).get(k, float('nan'))
    itv = [g('@itv', k) for k in sel if k in col.get('@itv', {})]; step = 16.667 * (statistics.median(itv) if itv else 1)
    shown = {k: g('@presented_ms', k) for k in sel if k in col.get('@presented_ms', {})}
    odd = [k for k, x in shown.items() if x >= 0 and abs(x - step) > 2]; longer = [k for k in odd if shown[k] > step + 2]; drop = [k for k, x in shown.items() if x < 0]
    late = [k for k in sel if g('@frame_ms', k) > step * 1.5]
    near = lambda k: any(g('@upload_ms', j) > 0.5 or g('@frame_ms', j) > 60 or g('@gpu_ms', j) < 0.27 * step for j in range(k - 3, k + 4))
    cut = [k for k in longer if near(k)]
    idle = [k for k in sel if g('@frame_ms', k) > 2.4 * step and g('@work_ms', k) < 12 and not (g('@link_gap_ms', k) > 50 or g('@link_gap_ms', k - 1) > 50)]
    print(f'{name}: {t[sel[0]]:.0f} to {t[sel[-1]]:.0f} s, {len(sel)} frames, step {step:.1f} ms, {len(sel) / (t[sel[-1]] - t[sel[0]]):.2f} fps')
    print(f'   on screen off the step: {len(odd)} ({len(longer)} longer, {len(odd) - len(longer)} shorter); never shown {len(drop)}; late game frames {len(late)} (longest {max(g("@frame_ms", k) for k in sel):.0f} ms)')
    print(f'   of the {len(longer)} longer: {len(cut)} beside a cut, {len(longer) - len(cut)} while driving')
    pm = collections.Counter(int((t[k] - t0) // 60) for k in longer)
    print(f'   worst minute: {max(pm.values()) if pm else 0} longer frames; minutes with any: {len(pm)} of {int(secs // 60)}; by minute: ' + ' '.join(str(pm.get(i, 0)) for i in range(int(secs // 60))))
    gm = collections.defaultdict(list)
    for k in sel:
        if k in col.get('@gpu_ms', {}): gm[int((t[k] - t0) // 60)].append(col['@gpu_ms'][k])
    med = [pct(v, 50) for i, v in sorted(gm.items())]; allg = [x for v in gm.values() for x in v]
    print(f'   GPU median by minute: {min(med):.1f} to {max(med):.1f} ms; whole window p50 {pct(allg, 50):.2f} p95 {pct(allg, 95):.2f}')
    cm = [g('@compressed_mb', k) for k in sel if k in col.get('@compressed_mb', {})]
    print(f'   new pipelines {int(sum(g("@pso_new", k) for k in sel if k in col.get("@pso_new", {})))}; swap-ins {int(sum(g("@swapin_kb", k) for k in sel if k in col.get("@swapin_kb", {})))} kB; major faults {int(sum(g("@majflt", k) for k in sel if k in col.get("@majflt", {})))}; compressed MB first/max/last ' + (f'{cm[0]:.0f}/{max(cm):.0f}/{cm[-1]:.0f}' if cm else '-'))
    print('   frames with next to no work in them (over 2.4 steps, under 12 ms of game work, no display link gap): ' + (', '.join(f'{t[k]:.1f} s: {g("@frame_ms", k):.0f} ms' for k in idle) or 'none'))
    print('   longer while driving (s: ms on screen / frame ms): ' + (', '.join(f'{t[k]:.0f}: {shown[k]:.0f}/{g("@frame_ms", k):.0f}' for k in longer if k not in cut)[:900] or 'none'))
    print('   beside a cut: ' + ', '.join(f'{t[k]:.0f}: {shown[k]:.0f}/{g("@frame_ms", k):.0f}' for k in cut)[:900])
    logf = run / 'log.txt'; log = logf.read_text(errors='replace') if logf.exists() else ''
    fp = [int(b) for a, b in re.findall(r'on-screen up to frame (\d+):.*?footprint (\d+) MiB', log)]
    if fp: print(f'   footprint MiB: first {fp[0]}, highest {max(fp)}, last {fp[-1]}')
