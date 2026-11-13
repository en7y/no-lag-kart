#!/usr/bin/env python3
# fxsum.py <from> <secs> <run name>...: one line a bench run (the newest <build>/bench/*/<name>-1) over the window [from, from + secs) of its seconds:
#   fps; late = game frames over 1.5 steps; max = the longest, ms; shown!= = frames whose on-screen interval was more than 2 ms off the step (what a player can
#   see); drop = frames never shown; GPU p50/p95, ms; the present pass's GPU time; replay = the replay thread's CPU a frame, ms, and its mean clock; lat = from the
#   game's present call to the frame on screen, ms; rtMB = render-target megabytes a frame (follows the game's render size); draws; and the run's state: window or
#   fullscreen (fs fixed60: the built-in screen switched to a fixed 60 Hz), the MetalFX present scaling, how often the window was covered (once, at the start, is
#   the move into fullscreen), [RED] lines. The build folder: MKW_BUILD, else <MKW_DUMP or ../MarioKartWorld>/0400C3F00006E000_build.
import os, sys, re, pathlib, statistics
ROOT = pathlib.Path(__file__).resolve().parents[2]
B = pathlib.Path(os.environ.get('MKW_BUILD') or pathlib.Path(os.environ.get('MKW_DUMP') or ROOT.parent / 'MarioKartWorld') / '0400C3F00006E000_build') / 'bench'
if len(sys.argv) < 4: sys.exit('usage: fxsum.py <from> <secs> <run name>...')
t0, secs = float(sys.argv[1]), float(sys.argv[2])
def pct(v, p): v = sorted(v); return v[min(len(v) - 1, int(len(v) * p / 100))] if v else float('nan')
print(f'{"run":<11}{"fps":>6}{"late":>5}{"max":>6} {"shown!=":>8}{"drop":>5} {"GPU p50/p95":>12} {"present GPU":>11} {"replay":>7} {"GHz":>5} {"lat p50/p95":>12} {"rtMB":>6} {"draws":>6}  state')
for name in sys.argv[3:]:
    runs = sorted(B.glob(f'*/{name}-1'))
    if not runs: print(f'{name:<11} no run'); continue
    run = runs[-1]; col = {}
    for line in (run / 'frames.tsv').open():
        p = line.rstrip('\n').split('\t')
        if len(p) == 3 and p[1].startswith('@'):
            try: col.setdefault(p[1], {})[int(p[0])] = float(p[2])
            except ValueError: pass
    t = col.get('@t_s', {}); sel = [k for k, v in t.items() if t0 <= v < t0 + secs]
    if not sel: print(f'{name:<11} no frames in the window'); continue
    g = lambda n: [col[n][k] for k in sel if k in col.get(n, {})]
    fr = g('@frame_ms'); itv = g('@itv'); step = 16.667 * (statistics.median(itv) if itv else 1)
    late = sum(1 for x in fr if x > step * 1.5)
    shown = [x for x in g('@presented_ms')]; odd = sum(1 for x in shown if x >= 0 and abs(x - step) > 2); drop = sum(1 for x in shown if x < 0)
    lat = [col['@pres_at_ms'][k] - 1000 * t[k] for k in sel if k in col.get('@pres_at_ms', {})]
    logf = run / 'host.out' if (run / 'host.out').exists() else run / 'log.txt'
    log = logf.read_text(errors='replace') if logf.exists() else ''
    st = []
    if 'switched to fixed 60 Hz' in log: st.append('fs fixed60')
    elif re.search(r'frame latency \d \(fullscreen', log): st.append('fullscreen')
    else: st.append('window')
    m = re.findall(r'present upscaling: MetalFX spatial scaler (\d+x\d+) → (\d+x\d+)', log)
    if m: st.append(f'{m[-1][0]}→{m[-1][1]}')
    pg = re.findall(r'present command buffer GPU time over \d+ presents[^:]*: p50 ([\d.]+) ms', log)
    clk = []
    for mm in re.finditer(r'translation detail up to frame (\d+):.*?mean clock ([\d.]+) GHz', log):
        f = int(mm.group(1))
        if f in t and t0 <= t[f] < t0 + secs + 5: clk.append(float(mm.group(2)))
    covered = log.count('window covered'); red = sum(1 for l in log.splitlines() if '[RED]' in l)
    if covered: st.append(f'covered x{covered}')
    if red: st.append(f'RED x{red}')
    if 'rescue' in log: st.append(f'rescue x{log.count("rescue ended")}')
    gpu = g('@gpu_ms')
    print(f'{name:<11}{len(sel) / secs:>6.1f}{late:>5}{max(fr):>6.0f} {odd:>8}{drop:>5} {pct(gpu, 50):>6.2f}/{pct(gpu, 95):<5.2f} {(pg[-1] if pg else "-"):>11} {pct(g("@sub_cpu_ms"), 50):>7.2f} {(statistics.median(clk) if clk else float("nan")):>5.2f} {pct(lat, 50):>6.1f}/{pct(lat, 95):<5.1f} {pct(g("@rt_store_mb"), 50):>6.0f} {pct(g("@draws"), 50):>6.0f}  {", ".join(st)}')
