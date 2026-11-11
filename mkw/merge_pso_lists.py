#!/usr/bin/env python3
# Merges pipeline prewarm lists (pso_manifest.tsv / pso_user.tsv / switch2mac shader lists) into one, in the order given: the first list's rows first, each later
# list adding only rows not seen yet. Rows: S<TAB>shader key<TAB>stage, C<TAB>compute shader key, R<TAB>render pipeline key (hex), M<TAB>object key<TAB>mesh key (hex).
# The host reads R and M keys of several older lengths by padding them with zeros (nvn_pso_skey.h pso_skey_parse), so two rows that differ only in trailing zeros are one.
# --map <shader_map.tsv>: only reports how many rows name shaders that are not in that map (the host skips those at load; nothing is removed here).
# Usage: merge_pso_lists.py [--map shader_map.tsv] -o out.tsv list1.tsv list2.tsv ...
import argparse, sys
def canon(c):
    if c[0] in ('R', 'M'): return (c[0],) + tuple(c[1:-1]) + (c[-1].lower().rstrip('0'),)
    return tuple(c)
def shader_keys(c):   # the shader keys a row names (S / C: the key; R / M: the two 24-byte names at the head of the hex key)
    if c[0] in ('S', 'C'): return [c[1]]
    h = c[-1]; out = []
    for off in (0, 48):
        try: s = bytes.fromhex(h[off:off + 48]).split(b'\0')[0].decode('ascii')
        except ValueError: s = ''
        if s: out.append(s)
    if c[0] == 'M' and c[1] != '-': out.append(c[1])
    return out
ap = argparse.ArgumentParser(); ap.add_argument('--map'); ap.add_argument('-o', required=True); ap.add_argument('lists', nargs='+'); a = ap.parse_args()
known = None
if a.map:
    known = set()
    for l in open(a.map):
        f = l.rstrip('\n').split('\t')
        if not l.startswith('#') and len(f) >= 4: known.update(x for x in f if len(x) == 16 and all(ch in '0123456789abcdef' for ch in x))
seen, out, unknown = set(), [], 0
for path in a.lists:
    n = added = 0
    for l in open(path):
        l = l.rstrip('\n')
        if not l or l.startswith('#'): continue
        c = l.split('\t')
        if c[0] not in ('S', 'C', 'R', 'M') or len(c) < 2: continue
        n += 1; k = canon(c)
        if k in seen: continue
        seen.add(k); out.append(l); added += 1
        if known is not None and any(s.split('_')[0] not in known for s in shader_keys(c)): unknown += 1
    print(f'{path}: {n:,} rows, {added:,} new', file=sys.stderr)
kinds = {t: sum(1 for l in out if l.startswith(t + '\t')) for t in 'SCRM'}
open(a.o, 'w').write('# Prewarm seed list, merged by mkw/merge_pso_lists.py from: ' + ', '.join(p.rsplit('/', 1)[-1] for p in a.lists) + '\n' + '\n'.join(out) + '\n')
print(f'{a.o}: {len(out):,} rows ({", ".join(f"{v:,} {k}" for k, v in kinds.items())})' + (f'; {unknown:,} name a shader that is not in {a.map}' if known is not None else ''), file=sys.stderr)
