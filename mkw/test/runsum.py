#!/usr/bin/env python3
# runsum.py <bench folder>... [--from T0] [--secs N]: one line a run: GPU time, passes, how long frames stayed on screen, long frames
import sys, re, pathlib, argparse, statistics
ap = argparse.ArgumentParser(); ap.add_argument('folders', nargs='+'); ap.add_argument('--from', dest='t0', type=float, default=100); ap.add_argument('--secs', type=float, default=35)
a = ap.parse_args()
def pct(v, p): v = sorted(v); return v[min(len(v) - 1, int(len(v) * p / 100))] if v else float('nan')
print(f'{"run":<12}{"fps":>6}{"gpu p50/p95":>14}{"sub cpu p50":>12}{"passes":>7}{"draws":>7}  {"on screen (ms x frames)":<44} {"max frame":>9}  long frames (s:frame/submit ms)')
for f in a.folders:
    for run in sorted(pathlib.Path(f).glob('*-[0-9]*')):
        ft = run / 'frames.tsv'
        if not ft.exists(): continue
        col = {}
        for line in ft.open():
            p = line.rstrip('\n').split('\t')
            if len(p) == 3 and p[1].startswith('@'):
                try: col.setdefault(p[1], {})[int(p[0])] = float(p[2])
                except ValueError: pass
        t = col.get('@t_s', {}); sel = [k for k, v in t.items() if a.t0 <= v < a.t0 + a.secs]
        if not sel: continue
        g = lambda name: [col[name][k] for k in sel if k in col.get(name, {})]
        shown = {}
        for x in g('@presented_ms'): shown[round(x, 1)] = shown.get(round(x, 1), 0) + 1
        sh = ' '.join(f'{k:g}x{v}' for k, v in sorted(shown.items()) if k != 16.7)
        log = (run / 'log.txt').read_text(errors='replace') if (run / 'log.txt').exists() else ''
        longs = [(float(m.group(1)), m.group(2), m.group(3)) for m in re.finditer(r'longframe\] frame \d+ \(([0-9.]+) s\) whole frame ([0-9.]+) ms, submit\+present ([0-9.]+) ms', log)]
        ls = ' '.join(f'{s:.1f}:{w}/{u}' for s, w, u in longs if a.t0 <= s < a.t0 + a.secs)
        note = (' COVERED' if 'window covered' in log else '') + (f' hitch dumps {log.count("hitch dump ")}' if 'hitch dump ' in log else '')
        gpu = g('@gpu_ms'); fr = g('@frame_ms')
        print(f'{run.name:<12}{len(sel) / a.secs:>6.1f}{pct(gpu, 50):>8.2f}/{pct(gpu, 95):<5.2f}{pct(g("@sub_cpu_ms"), 50):>12.2f}{pct(g("@passes"), 50):>7.0f}{pct(g("@draws"), 50):>7.0f}  {sh:<44} {max(fr) if fr else 0:>9.1f}  {ls}{note}')
