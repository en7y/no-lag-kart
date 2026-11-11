#!/usr/bin/env python3
# Resolves the merge conflicts of nxnative pull requests on this branch (run in the repo root, mid-merge): resolve_pr.py 1179 | 1437
import re, pathlib, subprocess, sys
pr = sys.argv[1]
M = pathlib.Path('dm/gfx/nvn/nvn_mtl.m'); s = M.read_text()
hunks = list(re.finditer(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', s, re.S))
if pr == '1179':
    # upstream gave the mesh draw its grid limit (DMSH_MESH_GRID); the pull request lets the scan run with no current draw (mdx_prescan)
    assert len(hunks) == 1, len(hunks)
    ours = hunks[0].group(1)
    a = 'else MDX_TAKE(di->ind, di->mdi_cnt, di->mdi_i, 5);'; b = '    if (g_mdx_range) {\n'
    assert ours.count(a) == 1 and ours.endswith(b), ours[:200]
    ours = ours.replace(a, 'else if (di) MDX_TAKE(di->ind, di->mdi_cnt, di->mdi_i, 5);')[:-len(b)] + '    if (g_mdx_range && (dw || di)) {   // neither: mdx_prescan, only the draws after this one\n'
    s = s[:hunks[0].start()] + ours + s[hunks[0].end():]
elif pr == '1437':
    # upstream rewrote the segment timestamps since; only the pull request's stretch (ts_pad) is taken
    assert len(hunks) == 2, len(hunks)
    h1, h2 = hunks
    pad = h2.group(2).split('\n', 1)[1]
    assert pad.lstrip().startswith('double pad = ts_pad();'), pad[:80]
    s = s[:h2.start()] + h2.group(1) + pad + s[h2.end():]
    s = s[:h1.start()] + h1.group(1) + s[h1.end():]
    s, n = re.subn(r'// The GPU idles between segments while the host translates and commits the next one;.*?static uint64_t seg_gap_before\(.*?\n}\n', '', s, count=1, flags=re.S)
    assert n == 1
    docs = ['dm/games/0400C3F00006E000/README.md', 'docs/reference/frame-rate.md', 'docs/env_switches.tsv']   # upstream's text stands; one row for the new switch
    subprocess.run(['git', 'checkout', 'HEAD', '--'] + docs, check=True)
    E = pathlib.Path(docs[2]); L = E.read_text().split('\n')
    i = max(k for k, l in enumerate(L) if l.startswith('DM_NVN_GPU_TS\t'))
    L.insert(i + 1, "DM_NVN_GPU_TS_PAD\tswitch\t`=<factor>` (1.0 to 2.0, default 1) stretches each submission's reported GPU times by the factor, GPU headroom for a game's dynamic resolution (`nvn_mtl.m` `ts_pad`)")
    E.write_text('\n'.join(L))
else: sys.exit('unknown pull request')
assert '<<<<<<<' not in s and '>>>>>>>' not in s
M.write_text(s); print('resolved', pr)
