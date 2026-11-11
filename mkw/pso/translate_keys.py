#!/usr/bin/env python3
# Rewrites the shader keys of a prewarm list recorded by a host with another key scheme into this host's keys, through two shader maps of the SAME game version:
# the list's own map and this host's map of that version, joined on (package, source location), which is unique in both and names the same bytes of the same file.
# Not on (package, index): two splits number the shaders of a package differently from some point on, and the stage still agrees, since a package holds one stage.
# Rows with a shader the join does not cover are dropped. Usage: translate_keys.py <list.tsv> <their shader_map.tsv> <our shader_map.tsv of that version> -o out.tsv
import argparse, sys
ap = argparse.ArgumentParser(); ap.add_argument('list'); ap.add_argument('theirs'); ap.add_argument('ours'); ap.add_argument('-o', required=True); a = ap.parse_args()
def rd(p):
    d = {}
    for l in open(p):
        if l.startswith('#') or l.startswith('package\t'): continue
        f = l.rstrip('\n').split('\t')
        if len(f) >= 5:
            assert (f[0], f[4]) not in d, 'a (package, source) twice in ' + p
            d[(f[0], f[4])] = (f[3], f[2])
    return d
theirs, ours = rd(a.theirs), rd(a.ours)
old2new = {}
for k, (key, stage) in theirs.items():
    if k in ours:
        assert ours[k][1] == stage, ('stage differs at', k)
        assert key not in old2new or old2new[key] == ours[k][0], ('one old key, two new keys', key)
        old2new[key] = ours[k][0]
def tr(k):
    n = old2new.get(k[:-2] if k.endswith('_b') else k)
    return n + '_b' if n and k.endswith('_b') else n
out = []; n = dropped = 0
for l in open(a.list):
    l = l.rstrip('\n')
    if not l or l.startswith('#'): continue
    c = l.split('\t')
    if c[0] not in ('S', 'C', 'R', 'M') or len(c) < 2: continue
    n += 1
    if c[0] in ('S', 'C'):
        k = tr(c[1])
        if not k: dropped += 1; continue
        out.append('\t'.join([c[0], k] + c[2:])); continue
    h = c[-1]; ok = True
    for off in (0, 48):
        name = bytes.fromhex(h[off:off + 48]).split(b'\0')[0].decode('ascii')
        if not name: continue
        k = tr(name)
        if not k: ok = False; break
        h = h[:off] + k.encode().ljust(24, b'\0').hex() + h[off + 48:]
    if c[0] == 'M' and c[1] != '-':
        k = tr(c[1])
        if not k: ok = False
        else: c[1] = k
    if not ok: dropped += 1; continue
    out.append('\t'.join(c[:-1] + [h]))
open(a.o, 'w').write('# ' + a.list.rsplit('/', 1)[-1] + ' with its shader keys rewritten to this host\'s (mkw/pso/translate_keys.py: ' + str(len(old2new)) + ' keys joined on package and source location)\n' + '\n'.join(out) + '\n')
print(f'{a.list}: {n:,} rows, {len(out):,} rewritten, {dropped:,} dropped (a shader outside the join); {len(old2new):,} keys joined', file=sys.stderr)
