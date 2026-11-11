#!/usr/bin/env python3
# Resolves the merge of nxnative PR #1847 (the maintainer's heavy-frame performance branch) onto a tree that has PR #1179 and #1437 (run in the repo root, mid-merge).
# Three places where both sides added lines: both are kept, and the mesh run function keeps upstream's geo_mesh_entry with the branch's generation counter.
import re, pathlib
def fix(path, fn):
    p = pathlib.Path(path); s = p.read_text()
    hs = list(re.finditer(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', s, re.S))
    out = []; last = 0
    for i, h in enumerate(hs):
        out.append(s[last:h.start()]); out.append(fn(i, h.group(1), h.group(2))); last = h.end()
    out.append(s[last:]); p.write_text(''.join(out)); return len(hs)
def geo(i, ours, theirs):
    if i == 0: return ours + theirs
    assert 'geo_mesh_entry(lib,' in ours and theirs.lstrip().startswith('g_geo_mesh_runfn_gen++;')
    return ours.replace('g_geo_mesh_runfn[[NSValue', 'g_geo_mesh_runfn_gen++; g_geo_mesh_runfn[[NSValue', 1)
n = fix('dm/gfx/nvn/nvn_geometry.inc', geo), fix('dm/gfx/nvn/nvn_mtl.m', lambda i, o, t: o + t)
assert n in ((2, 1), (2, 0)), n   # (2, 0): on upstream 352e4a6e and later nvn_mtl.m merges by itself
print('resolved 1847')
