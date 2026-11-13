#!/usr/bin/env python3
# longlog.py <from s> <seconds> <run>...: a run's long frames as the host itself logs them (its "[longframe]" lines in host.out: every frame over about 1.4 frame
# times, present call to present call), for runs with and without the per-frame rows (MKW_NO_TSV=1 in mkw/test/host_open.py). For each run: how many frames of
# 25, 40, 60 and 100 ms or more the window has, and each frame of 40 ms or more with its texture uploads: one with none is not a scene cut's upload frame.
# The newest folder <build>/bench/*/<run>-1 is read; MKW_BUILD or MKW_DUMP name the build folder when the dump is not beside the repository.
import os, re, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
B = pathlib.Path(os.environ.get('MKW_BUILD') or pathlib.Path(os.environ.get('MKW_DUMP') or ROOT.parent / 'MarioKartWorld') / '0400C3F00006E000_build') / 'bench'
if len(sys.argv) < 4: sys.exit(f'usage: {sys.argv[0]} <from s> <seconds> <run>...')
t0, t1 = float(sys.argv[1]), float(sys.argv[1]) + float(sys.argv[2])
pat = re.compile(r'\[longframe\] frame (\d+) \(([\d.]+) s\) whole frame ([\d.]+) ms, submit\+present ([\d.]+) ms, GPU ([\d.]+) ms; new pipelines (\d+) \+ shader libraries (\d+), ([\d.]+) ms in all; '
                 r'texture uploads (\d+) first \+ (\d+) re-uploads, ([\d.]+) MB / ([\d.]+) ms')
for name in sys.argv[3:]:
    runs = sorted(B.glob(f'*/{name}-1'))
    if not runs: print(f'{name}: no run'); continue
    rows = []
    for line in (runs[-1] / 'host.out').open(errors='replace'):
        m = pat.search(line)
        if m and t0 <= float(m.group(2)) < t1: rows.append((float(m.group(2)), float(m.group(3)), float(m.group(4)), int(m.group(6)), int(m.group(9)) + int(m.group(10)), float(m.group(11)), float(m.group(12))))
    n = lambda ms: sum(1 for r in rows if r[1] >= ms)
    print(f'{name}: {t0:.0f} to {t1:.0f} s: frames of 25 ms or more {n(25)}, of 40 {n(40)}, of 60 {n(60)}, of 100 {n(100)}; of 40 ms or more with no texture upload: {sum(1 for r in rows if r[1] >= 40 and r[6] < 1)}')
    print('   40 ms or more (s: frame ms / uploads ms): ' + ', '.join(f'{r[0]:.0f}: {r[1]:.0f}/{r[6]:.0f}' + ('*' if r[3] else '') for r in rows if r[1] >= 40))
