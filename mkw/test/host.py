#!/usr/bin/env python3
"""A host binary per variant, for scripts/bench.py's `host=` (one change measured at a time against the same shader libraries and game files).

  mkw/test/host.py <label> [--base <ref>] [--key name=value ...] [--list <prewarm list>] [pr/<n> | <ref> ...]

  <label>        the variant's name: its host goes to <build>/variants/<label>/dmhost
  --base <ref>   the revision it starts from (default mkw-fixes; origin/main for upstream as it is)
  pr/<n>, <ref>  merged on top, in order. A pull request not fetched yet is fetched. A conflict stops the script unless mkw/resolve_pr.py knows that pull request
  --key k=v      a profile key for this variant's host (game.tsv row; k= removes the row): fps_step_max=3, mem_map_limit=off ...
  --list <file>  the variant's prewarm list (pso_manifest.tsv): bench.py then takes the variant's profile copy (shmap=, printed at the end)

The source is checked out into <worktrees>/<label> (a git worktree, made again each time), so this checkout is never touched.
The profile: the build folder's derived profile when there is one (1.8.0 is packed from a profile derived for it), with the base revision's own keys laid over it,
else the base revision's profile. A profile key reaches the host only through its generated header, so the shader libraries stay as they are.
Environment: MKW_DUMP (default ../MarioKartWorld), MKW_BUILD (default <dump>/0400C3F00006E000_build), MKW_WORKTREES (default ../mkw-worktrees)."""
import argparse, os, pathlib, re, shutil, subprocess, sys

ID = '0400C3F00006E000'
REPO = pathlib.Path(__file__).resolve().parents[2]
DUMP = pathlib.Path(os.environ.get('MKW_DUMP', REPO.parent / 'MarioKartWorld')).resolve()
BUILD = pathlib.Path(os.environ.get('MKW_BUILD', DUMP / f'{ID}_build')).resolve()
WTS = pathlib.Path(os.environ.get('MKW_WORKTREES', REPO.parent / 'mkw-worktrees')).resolve()
DERIVED_ROWS = ('build', 'package', 'shader_versions', 'modules', 'title_id', 'program_id')   # what scripts/build_ipa_from_nsp.py derive_profile writes for the packed version


def git(*a, cwd=REPO, check=True, quiet=False):
    r = subprocess.run(['git', *a], cwd=cwd, text=True, capture_output=True)
    err = '\n'.join(l for l in r.stderr.splitlines() if 'not our ref' not in l)   # noise of a blobless clone with several remotes
    if check and r.returncode: sys.exit(f'git {" ".join(a)} failed:\n{r.stdout}{err}')
    if not quiet and err.strip(): print(err.strip(), file=sys.stderr)
    return r


def rows(text):   # [(key or None, line)] of a game.tsv
    return [(None if not l.strip() or l.lstrip().startswith('#') else l.split('\t', 1)[0].strip(), l) for l in text.splitlines()]


def overlay(derived, own, keys):
    """The variant's game.tsv: the derived profile's rows for the packed version, every other row from the base revision's own profile, then --key"""
    keep = [l for k, l in rows(derived) if k in DERIVED_ROWS]
    out, put = [], False
    for k, l in rows(own):
        if k in DERIVED_ROWS:
            if not put: out += keep; put = True
            continue
        out.append(l)
    if not put: out += keep
    for kv in keys:
        k, _, v = kv.partition('=')
        out = [l for l in out if not (l.split('\t', 1)[0].strip() == k and not l.lstrip().startswith('#'))]
        if v: out.append(f'{k}\t{v}')
    return '\n'.join(out) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('label'); ap.add_argument('--base', default='mkw-fixes'); ap.add_argument('--key', action='append', default=[])
    ap.add_argument('--list'); ap.add_argument('merge', nargs='*')
    a = ap.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9._-]+', a.label): sys.exit('the label: letters, digits, . _ -')
    wt, var = WTS / a.label, BUILD / 'variants' / a.label
    git('worktree', 'remove', '--force', str(wt), check=False, quiet=True)
    if wt.exists(): shutil.rmtree(wt)
    WTS.mkdir(parents=True, exist_ok=True)
    git('worktree', 'add', '--detach', str(wt), a.base, quiet=True)
    for m in a.merge:
        n = m[3:] if m.startswith('pr/') else None
        if n and git('rev-parse', '-q', '--verify', f'refs/heads/{m}', check=False, quiet=True).returncode: git('fetch', '-q', 'origin', f'pull/{n}/head:{m}')
        r = git('-c', 'user.name=mkw', '-c', 'user.email=mkw@local', 'merge', '--no-edit', '-q', m, cwd=wt, check=False, quiet=True)
        if r.returncode:
            res = REPO / 'mkw' / ('resolve_pr1847.py' if n == '1847' else 'resolve_pr.py')   # this checkout's rules, run in the variant's tree
            known = n and res.is_file() and (n == '1847' or f"'{n}'" in res.read_text())
            if not known or subprocess.run([sys.executable, str(res)] + ([] if n == '1847' else [n]), cwd=wt).returncode: sys.exit(f'{m} does not merge onto {a.base}' + ('' if known else ' and mkw/resolve_pr.py has no rule for it') + f': see {wt}')
            left = git('diff', '--name-only', '--diff-filter=U', cwd=wt).stdout.split()
            bad = [f for f in left if '<<<<<<<' in (wt / f).read_text(errors='replace')]
            if bad: sys.exit(f'{m}: conflicts left in {", ".join(bad)} ({wt})')
            git('add', '-A', cwd=wt); git('-c', 'user.name=mkw', '-c', 'user.email=mkw@local', 'commit', '-q', '--no-edit', cwd=wt)
        print(f'merged {m}')
    # the profile
    env = dict(os.environ)
    derived = BUILD / 'profile' / ID
    prof = wt / 'dm/games' / ID
    if (derived / 'game.tsv').is_file():
        vp = var / 'profile' / ID
        if vp.exists(): shutil.rmtree(vp)
        vp.parent.mkdir(parents=True, exist_ok=True); shutil.copytree(derived, vp)
        (vp / 'game.tsv').write_text(overlay((derived / 'game.tsv').read_text(), (prof / 'game.tsv').read_text(), a.key))
        if a.list: shutil.copyfile(a.list, vp / 'pso_manifest.tsv')
        env.update(DM_GAMES_DIR=str(vp.parent), DM_GAMES_FIRST='1'); prof = vp
    else:
        print(f'no derived profile in {BUILD} yet (the game is not packed): building against {a.base}\'s own profile, which serves to check that the variant compiles')
        if a.key or a.list: sys.exit('--key and --list need the packed game\'s profile')
    host = wt / 'dm/host'
    log = var / 'build.log'; var.mkdir(parents=True, exist_ok=True)
    with open(log, 'w') as fh: r = subprocess.run(['make', '-C', str(host), f'GAME={ID}', 'dmhost'], env=env, stdout=fh, stderr=subprocess.STDOUT)
    if r.returncode: sys.exit(f'the host does not build: {log}')
    shutil.copy2(host / 'dmhost', var / 'dmhost')
    head = git('rev-parse', '--short', 'HEAD', cwd=wt).stdout.strip()
    hdr = (host / 'gen' / ID / 'game_profile.h').read_text()
    keys = ' '.join(f'{m[1].lower()}={m[2]}' for m in re.finditer(r'#define DM_GAME_(MEM_MAP_LIMIT|FPS_TARGET|FPS_HOLD|FPS_STEP_MAX|ENC_THREAD|PRESENT_SNAP) (\S+)', hdr))
    (var / 'about.txt').write_text(f'{a.label}: {a.base} {head}' + ''.join(f' + {m}' for m in a.merge) + f'\nprofile: {prof}\n{keys}\nwarnings: {log.read_text(errors="replace").count("warning:")}\n')
    print((var / 'about.txt').read_text().strip())
    v = f"{a.label}:host={var / 'dmhost'}" + (f",shmap={prof / 'shader_map.tsv'}" if a.list else '')
    print(f"\nbench variant:  --variant '{v}'")


if __name__ == '__main__': main()
