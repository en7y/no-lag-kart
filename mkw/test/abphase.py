#!/usr/bin/env python3
# abphase.py <run dir> <phase frames> <from s> <to s> [<n configurations> [<names>]]: a DM_AB run's frames (frames.tsv) by phase: frame k is in phase k // <phase frames>,
# configuration phase % n (default 2: 0 = every ab switch off, 1 = on). Per configuration over [from, to) seconds: frames, frame time mean / p90 / p99, frames over 36 / 40 / 50 ms,
# frames shown for other than the usual time (@presented_ms off the median), GPU p50 / mean, replay wall and CPU per frame, the game's acquire wait.
# The first quarter of each phase is left out, as the [ab] lines do (the GPU clock and the frame step settle).
import sys, statistics
run, ph, t0, t1 = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
n = int(sys.argv[5]) if len(sys.argv) > 5 else 2
names = sys.argv[6].split(',') if len(sys.argv) > 6 else [str(i) for i in range(n)]
col = {}
for line in open(run + '/frames.tsv'):
    p = line.rstrip('\n').split('\t')
    if len(p) == 3 and p[1].startswith('@'):
        try: col.setdefault(p[1], {})[int(p[0])] = float(p[2])
        except ValueError: pass
t = col['@t_s']
sel = sorted(k for k, v in t.items() if t0 <= v < t1 and k % ph >= ph // 4)
g = lambda name, k: col.get(name, {}).get(k)
shown = [g('@presented_ms', k) for k in sel if g('@presented_ms', k) is not None and g('@presented_ms', k) > 0]
norm = statistics.median(shown) if shown else 33.33
def q(v, f): v = sorted(v); return v[min(len(v) - 1, int(f * len(v)))] if v else float('nan')
print(f'{run}: phases of {ph} frames, {n} configurations, {t0:g}-{t1:g} s, usual shown time {norm:.2f} ms')
print(f'{"config":>10} {"frames":>6} {"mean":>6} {"p90":>6} {"p99":>6} {">36":>4} {">40":>4} {">50":>4} {"uneven":>6} {"gpu50":>6} {"gpuavg":>6} {"wall":>6} {"cpu":>6} {"acq":>5}')
for c in range(n):
    ks = [k for k in sel if (k // ph) % n == c]
    ft = [g('@frame_ms', k) for k in ks if g('@frame_ms', k) is not None]
    gp = [g('@gpu_ms', k) for k in ks if g('@gpu_ms', k) is not None and g('@gpu_ms', k) > 0]
    pr = [g('@presented_ms', k) for k in ks if g('@presented_ms', k) is not None and g('@presented_ms', k) > 0]
    wall = [g('@sub_wall_ms', k) for k in ks if g('@sub_wall_ms', k) is not None]
    cpu = [g('@sub_cpu_ms', k) for k in ks if g('@sub_cpu_ms', k) is not None]
    acq = [g('@wait_ms', k) for k in ks if g('@wait_ms', k) is not None]
    un = sum(1 for v in pr if abs(v - norm) > 4)
    m = lambda v: statistics.mean(v) if v else float('nan')
    print(f'{names[c]:>10} {len(ft):6d} {m(ft):6.2f} {q(ft, .9):6.2f} {q(ft, .99):6.2f} {sum(v > 36 for v in ft):4d} {sum(v > 40 for v in ft):4d} {sum(v > 50 for v in ft):4d} {un:6d} {q(gp, .5):6.2f} {m(gp):6.2f} {m(wall):6.2f} {m(cpu):6.2f} {m(acq):5.2f}')
