#!/usr/bin/env python3
# Finds the rows of a pipeline prewarm list that this Mac cannot build without a crash (the host's, or Metal's compiler service), by halving: each try is one
# mkw/test/prep_probe.sh run on a part of the list. Rows of --good lists (ones this Mac has built already, such as its own pso_user.tsv) are not tried.
# Usage: mkw/test/list_bisect.py <list.tsv> [--good <list.tsv>]... [--kinds C,R,S,M] [-o bad_rows.tsv] [--after 4] [KEY=VALUE ...]
# Prints each try; writes the rows that fail alone to -o. A part that fails while both its halves pass is reported as it is (rows that only fail together).
import argparse, os, re, shutil, subprocess, sys, time
ap = argparse.ArgumentParser()
ap.add_argument('list'); ap.add_argument('--good', action='append', default=[]); ap.add_argument('--kinds', default='C,R,S,M'); ap.add_argument('-o')
ap.add_argument('--after', default='4'); ap.add_argument('env', nargs='*')
a = ap.parse_args()
here = os.path.dirname(os.path.abspath(__file__)); probe = os.path.join(here, 'prep_probe.sh')
def rows_of(path): return [l.rstrip('\n') for l in open(path) if l.strip() and not l.startswith('#')]
def canon(l):
    c = l.split('\t')
    return (c[0],) + tuple(c[1:-1]) + (c[-1].lower().rstrip('0'),) if c[0] in ('R', 'M') else tuple(c)
good = set()
for g in a.good: good.update(canon(l) for l in rows_of(g))
kinds = set(a.kinds.split(','))
cand = [l for l in rows_of(a.list) if l.split('\t')[0] in kinds and canon(l) not in good]
print(f'{len(cand)} rows to try ({len(good)} known good left out)', flush=True)
root = f'/tmp/mkw-probe/bisect-{time.strftime("%H%M%S")}'; os.makedirs(root, exist_ok=True); tries = 0
def ok(rows, label):
    global tries; tries += 1
    work = f'{root}/{tries:03d}'; os.makedirs(work, exist_ok=True); lst = f'{work}/list.tsv'
    open(lst, 'w').write('\n'.join(rows) + '\n')
    env = dict(os.environ, WORK=work, AFTER=a.after)
    out = subprocess.run([probe, lst] + a.env, env=env, capture_output=True, text=True).stdout
    crash = int(re.search(r'host crash lines: (\d+)', out).group(1)) if 'host crash lines' in out else -1
    reports = re.search(r'crash reports since the start: (.*)', out); reports = reports.group(1).strip() if reports else '?'
    red = int(re.search(r'red lines: (\d+)', out).group(1)) if 'red lines' in out else -1
    status = re.search(r'exit status (\d+)', out); status = int(status.group(1)) if status else -1
    good_run = crash == 0 and reports == 'none' and status == 0
    secs = re.search(r', (\d+) s;', out); secs = secs.group(1) if secs else '?'
    print(f'try {tries}: {label}: {len(rows)} rows -> {"ok" if good_run else "CRASH"} ({secs} s, red lines {red}, exit {status}, reports {"none" if reports == "none" else len(reports.split())})', flush=True)
    if good_run and red == 0: shutil.rmtree(work, ignore_errors=True)
    return good_run
bad, together = [], []
def find(rows, label):
    if not rows or ok(rows, label): return
    if len(rows) == 1: bad.append(rows[0]); print('  bad row: ' + rows[0][:120], flush=True); return
    h = len(rows) // 2; n0 = len(bad) + len(together)
    find(rows[:h], label + 'L'); find(rows[h:], label + 'R')
    if len(bad) + len(together) == n0: together.append(rows); print(f'  {len(rows)} rows fail only together ({label})', flush=True)
find(cand, '')
print(f'{len(bad)} rows fail alone; {len(together)} groups fail only together; {tries} tries; logs of the failing tries: {root}')
if a.o: open(a.o, 'w').write('\n'.join(bad) + ('\n' if bad else ''))
for g in together: print('together:\n  ' + '\n  '.join(r[:100] for r in g[:20]))
