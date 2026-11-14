#!/usr/bin/env python3
# host_open.py: a host for scripts/bench.py's `host=` that starts the game as macOS starts an app (LaunchServices, `open`), not as a child process.
# Why: a host started by a background process is not the active app; the host enters fullscreen (DM_FULLSCREEN=1) only as the active app, and Game Mode
# needs a fullscreen game. MKW_REAL_HOST names the host binary inside an app bundle (<bundle>/Contents/MacOS/dmhost, the bundle's CFBundleExecutable;
# mkw/test/mkbundle.sh makes such a bundle around any host). Every DM_*, MKW_*, MTL_* and METAL_* variable of this process goes to the game (`open --env`);
# the game's output goes to host.out in the run's folder and to this process's stdout at the end (bench.py's log.txt). Players 2 to 8 come from
# MKW_CTL_SCRIPT, as with mkw/test/host_with_ctl.sh. A SIGTERM here ends the game. With the screen locked nothing can be the active app: unlock it first.
# The game's process ID is found once, when it has started (the dmhost that was not running before the start), and written to game.pid in the run's folder: the stop
# signals that ID, so ending the game does not depend on listing processes. On 13 Nov a list (pgrep) hung while a macOS service was stuck, the stop never reached the
# game, and it went on running beside the next runs' starts, which failed. Every process list here has a time limit.
import os, sys, signal, subprocess, time, pathlib
real = os.environ['MKW_REAL_HOST']; app = str(pathlib.Path(real).resolve().parents[2]); out = pathlib.Path.cwd() / 'host.out'
pidf = pathlib.Path.cwd() / 'game.pid'
if os.environ.get('MKW_CTL_SCRIPT') and os.environ.get('DM_CTL'):
    subprocess.Popen(['python3', str(pathlib.Path(__file__).resolve().parent / 'ctl_feed.py'), os.environ['DM_CTL'], os.environ['MKW_CTL_SCRIPT']])
# MKW_NO_TSV=1: no per-frame rows (bench.py's DM_NVN_TSV is dropped). The host writes those rows on the thread that presents, 4 KB at a time, and a write to a file can
# wait: with the rows on, a Grand Prix had two or three frames held 70 to 210 ms inside a present call, each while macOS restarted services after ending idle ones
# for memory. Without the rows the run has no frames.tsv and bench.py reports no frames; read the long frames from the host's own lines (mkw/test/longlog.py).
if os.environ.get('MKW_NO_TSV'):
    for k in ('DM_NVN_TSV', 'DM_NVN_TSV_CALLS'): os.environ.pop(k, None)
def game_pids():   # the hosts running from an app bundle; None when the list did not answer within 5 s
    try: r = subprocess.run(['pgrep', '-f', 'Contents/MacOS/dmhost /'], capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired: print('host_open: the process list did not answer in 5 s', file=sys.stderr); return None
    return [int(x) for x in r.stdout.split()]
def alive(pid):
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False
    except PermissionError: return True
before = set(game_pids() or [])
cmd = ['open', '-n', '-W', '-a', app, '--stdout', str(out), '--stderr', str(out)]
for k, v in sorted(os.environ.items()):
    if k.startswith(('DM_', 'MKW_', 'MTL_', 'METAL_')): cmd += ['--env', f'{k}={v}']
cmd += ['--args', *sys.argv[1:]]
p = subprocess.Popen(cmd)
game = None
def stop(*_):
    pids = [game] if game else (game_pids() or [])
    for pid in pids:
        try: os.kill(pid, signal.SIGTERM)
        except OSError: pass
signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
t0 = time.time()
while game is None and p.poll() is None and time.time() - t0 < 60:   # the game's ID, once it has started
    new = [x for x in (game_pids() or []) if x not in before]
    if new: game = max(new); pidf.write_text(f'{game}\n'); break
    time.sleep(0.5)
if game is None: print('host_open: no game process ID found in 60 s', file=sys.stderr)
while p.poll() is None:
    try: p.wait(0.5)
    except subprocess.TimeoutExpired: pass
for _ in range(40):   # up to 10 s for the game to be gone after `open` returned
    if not (alive(game) if game else game_pids()): break
    time.sleep(0.25)
try: sys.stdout.write(out.read_text(errors='replace')); sys.stdout.flush()
except OSError as e: print(f'host_open: no output file: {e}')
