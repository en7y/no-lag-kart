#!/usr/bin/env python3
# host_open.py: a host for scripts/bench.py's `host=` that starts the game as macOS starts an app (LaunchServices, `open`), not as a child process.
# Why: a host started by a background process is not the active app; the host enters fullscreen (DM_FULLSCREEN=1) only as the active app, and Game Mode
# needs a fullscreen game. MKW_REAL_HOST names the host binary inside an app bundle (<bundle>/Contents/MacOS/dmhost, the bundle's CFBundleExecutable;
# mkw/test/mkbundle.sh makes such a bundle around any host). Every DM_*, MKW_*, MTL_* and METAL_* variable of this process goes to the game (`open --env`);
# the game's output goes to host.out in the run's folder and to this process's stdout at the end (bench.py's log.txt). Players 2 to 8 come from
# MKW_CTL_SCRIPT, as with mkw/test/host_with_ctl.sh. A SIGTERM here ends the game. With the screen locked nothing can be the active app: unlock it first.
import os, sys, signal, subprocess, time, pathlib
real = os.environ['MKW_REAL_HOST']; app = str(pathlib.Path(real).resolve().parents[2]); out = pathlib.Path.cwd() / 'host.out'
if os.environ.get('MKW_CTL_SCRIPT') and os.environ.get('DM_CTL'):
    subprocess.Popen(['python3', str(pathlib.Path(__file__).resolve().parent / 'ctl_feed.py'), os.environ['DM_CTL'], os.environ['MKW_CTL_SCRIPT']])
# MKW_NO_TSV=1: no per-frame rows (bench.py's DM_NVN_TSV is dropped). The host writes those rows on the thread that presents, 4 KB at a time, and a write to a file can
# wait: with the rows on, a Grand Prix had two or three frames held 70 to 210 ms inside a present call, each while macOS restarted services after ending idle ones
# for memory. Without the rows the run has no frames.tsv and bench.py reports no frames; read the long frames from the host's own lines (mkw/test/longlog.py).
if os.environ.get('MKW_NO_TSV'):
    for k in ('DM_NVN_TSV', 'DM_NVN_TSV_CALLS'): os.environ.pop(k, None)
cmd = ['open', '-n', '-W', '-a', app, '--stdout', str(out), '--stderr', str(out)]
for k, v in sorted(os.environ.items()):
    if k.startswith(('DM_', 'MKW_', 'MTL_', 'METAL_')): cmd += ['--env', f'{k}={v}']
cmd += ['--args', *sys.argv[1:]]
p = subprocess.Popen(cmd)
def game_pids():
    r = subprocess.run(['pgrep', '-f', 'Contents/MacOS/dmhost /'], capture_output=True, text=True)
    return [int(x) for x in r.stdout.split()]
def stop(*_):
    for pid in game_pids():
        try: os.kill(pid, signal.SIGTERM)
        except OSError: pass
signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
while p.poll() is None:
    try: p.wait(0.5)
    except subprocess.TimeoutExpired: pass
for _ in range(20):
    if not game_pids(): break
    time.sleep(0.25)
try: sys.stdout.write(out.read_text(errors='replace')); sys.stdout.flush()
except OSError as e: print(f'host_open: no output file: {e}')
