#!/usr/bin/env python3
"""Merges a set of mkw/sets.tsv into the branch checked out HERE (the current directory's worktree), one merge commit per pull request.

  cd <a worktree> && python3 <repo>/mkw/assemble.py fixes|fast [--from <pr>]

A pull request already merged (its head is an ancestor) is skipped. One not fetched yet is fetched (pull/<n>/head → branch pr/<n>). A conflict is resolved by
mkw/resolve_pr.py / resolve_pr1847.py when they know the pull request; otherwise the script stops with the merge left open for a hand resolution.
Never run it in the checkout a build (mkw/test/pack.sh) is reading: use a worktree (git worktree add ../mkw-worktrees/assemble <branch>)."""
import pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[1]
TRAILER = '\n\nCo-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01JcmewFJDrDUooyBk9ygMAv'


def git(*a, check=True):
    r = subprocess.run(['git', *a], text=True, capture_output=True)
    if check and r.returncode: sys.exit(f'git {" ".join(a)}:\n{r.stdout}{r.stderr}')
    return r


def main():
    want = sys.argv[1]; start = sys.argv[sys.argv.index('--from') + 1] if '--from' in sys.argv else None
    rows = [l.split('\t') for l in (REPO / 'mkw/sets.tsv').read_text().splitlines() if l.strip() and not l.startswith('#')]
    todo = [(n, who, what) for s, n, who, what in rows if s == want]
    if start: todo = todo[[n for n, _, _ in todo].index(start):]
    for n, who, what in todo:
        ref = f'pr/{n}'
        if git('rev-parse', '-q', '--verify', f'refs/heads/{ref}', check=False).returncode: git('fetch', '-q', 'origin', f'pull/{n}/head:{ref}')
        if not git('merge-base', '--is-ancestor', ref, 'HEAD', check=False).returncode: print(f'#{n} already in'); continue
        msg = f'Merge PR #{n}: {what} ({who})' + TRAILER
        r = git('merge', '--no-ff', '-q', ref, '-m', msg, check=False)
        if r.returncode:
            res = REPO / 'mkw' / ('resolve_pr1847.py' if n == '1847' else 'resolve_pr.py')
            known = n == '1847' or f"'{n}'" in res.read_text()
            if not known or subprocess.run([sys.executable, str(res)] + ([] if n == '1847' else [n])).returncode: sys.exit(f'#{n} does not merge and no rule resolves it: the merge is left open here')
            left = [f for f in git('diff', '--name-only', '--diff-filter=U').stdout.split() if '<<<<<<<' in pathlib.Path(f).read_text(errors='replace')]
            if left: sys.exit(f'#{n}: conflicts left in {", ".join(left)}')
            git('add', '-A'); git('commit', '-q', '-m', msg)
            print(f'#{n} merged (resolved by {res.name})')
        else: print(f'#{n} merged')
    print(git('log', '--oneline', '-1').stdout.strip()[:90])


if __name__ == '__main__': main()
