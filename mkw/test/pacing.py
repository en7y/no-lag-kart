#!/usr/bin/env python3
# What a benchmark run's frames looked like on screen and where their time went, from the run's frames.tsv (scripts/bench.py writes it with DM_NVN_TSV): one line per run.
#   late/min    presents that stayed on screen 25 ms or more (a frame that missed its 60 Hz refresh stays 33.3 ms), per minute: the stutter you see
#   shown       on-screen time, p50 / p99                gpu   summed GPU time of the frame, p50 / p95 / p99      span   first GPU start to last GPU end, p50 / p95
#   sub cpu     the host's translation of the frame's submissions, CPU p50 / p95      rt MB   render-target megabytes stored per frame, p50: follows the game's dynamic resolution
#   work        the game's time from one present to its next present call, p50 / p95      slack   how long the game waited for its display tick at the acquire, p50;
#   no slack    the share of frames that waited under 0.5 ms: they had nothing to spare
#   covered     the window was hidden at some time in the run (display asleep, screen saver): its on-screen numbers mean nothing
# Usage: mkw/test/pacing.py <bench folder> [--from 110] [--secs 90]      (the window of the route the folder was measured with; gp-race1: 110, 90)
import argparse, math, pathlib, sys
ap = argparse.ArgumentParser(); ap.add_argument('folder'); ap.add_argument('--from', dest='t0', type=float, default=110); ap.add_argument('--secs', type=float, default=90); a = ap.parse_args()
def pct(xs, p):
    if not xs: return float('nan')
    s = sorted(xs); return s[min(len(s) - 1, max(0, math.ceil(p / 100 * len(s)) - 1))]
print(f'{"run":<14}{"fps":>6}{"late/min":>9}{"shown p50/p99":>15}{"gpu p50/p95/p99":>20}{"span p50/p95":>14}{"sub cpu p50/p95":>17}{"work p50/p95":>14}{"slack p50":>10}{"no slack":>9}{"rt MB":>7}{"draws":>7}  notes')
for d in sorted(p for p in pathlib.Path(a.folder).iterdir() if (p / 'frames.tsv').exists()):
    rows = {}
    for ln in open(d / 'frames.tsv', errors='replace'):
        c = ln.rstrip('\n').split('\t')
        if len(c) != 3 or not c[1].startswith('@'): continue
        try: rows.setdefault(int(c[0]), {})[c[1]] = float(c[2])
        except ValueError: pass
    sel = [r for f, r in sorted(rows.items()) if '@t_s' in r and a.t0 <= r['@t_s'] < a.t0 + a.secs]
    if not sel: print(f'{d.name:<14} no frames in the window'); continue
    def col(k, lo=None): return [r[k] for r in sel if k in r and (lo is None or r[k] > lo)]
    shown, gpu = col('@presented_ms', 0), col('@gpu_ms', -0.5)
    span = [r['@gpu_end_ms'] - r['@gpu_beg_ms'] for r in sel if '@gpu_end_ms' in r and '@gpu_beg_ms' in r and r['@gpu_end_ms'] > r['@gpu_beg_ms'] > 0]
    late = sum(1 for x in shown if x >= 25)
    wait = col('@wait_ms')
    log = (d / 'log.txt').read_text(errors='replace') if (d / 'log.txt').exists() else ''
    notes = []
    if 'front end: window covered' in log: notes.append('covered')
    if 'CRASH sig' in log: notes.append('CRASH')
    pso = sum(1 for r in sel if r.get('@pso_new', 0) > 0)
    if pso: notes.append(f'{pso} frames built a pipeline')
    print(f'{d.name:<14}{len(sel) / a.secs:>6.1f}{late * 60 / a.secs:>9.1f}{pct(shown, 50):>8.1f}/{pct(shown, 99):<6.1f}{pct(gpu, 50):>8.2f}/{pct(gpu, 95):.2f}/{pct(gpu, 99):<6.2f}'
          f'{pct(span, 50):>7.1f}/{pct(span, 95):<6.1f}{pct(col("@sub_cpu_ms"), 50):>9.2f}/{pct(col("@sub_cpu_ms"), 95):<7.2f}{pct(col("@work_ms"), 50):>7.1f}/{pct(col("@work_ms"), 95):<6.1f}'
          f'{pct(wait, 50):>10.2f}{100 * sum(1 for x in wait if x < 0.5) / max(1, len(wait)):>8.0f}%{pct(col("@rt_store_mb"), 50):>7.0f}{pct(col("@draws"), 50):>7.0f}  {", ".join(notes)}')
