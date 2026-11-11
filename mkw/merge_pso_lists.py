#!/usr/bin/env python3
# Merges pipeline prewarm lists (pso_manifest.tsv / pso_user.tsv of any host) into one, in the order given: the first list's rows first, each later list adding only
# rows not seen yet. Rows: S<TAB>shader key<TAB>stage, C<TAB>compute shader key, R<TAB>render pipeline key (hex), M<TAB>task key or -<TAB>mesh pipeline key (hex).
# The host reads R and M keys of several older lengths by padding them with zeros (nvn_pso_skey.h pso_skey_parse), so two rows that differ only in trailing zeros are one.
# --map <shader_map.tsv>: keeps only the rows this host takes with that map, and says how many of each list went for which reason:
#   version  a shader key the map does not have (another version of the game; the host drops these at load)
#   stage    a shader at another stage than the map gives it: an S row's number, a C row for a shader that is not a compute shader, an R or M key's vs_stage / fs_stage.
#            Lists of hosts that numbered NVN2's task and mesh stages 6 and 7, or ran them as compute shaders, hold such rows; a host without the check in warm_parse
#            (nvn_mtl.m warm_stage_differs) loads those shaders at the wrong stage, and a C row of a mesh shader crashed Metal's compiler service (mkw/KNOWLEDGE.md)
#   length   an R or M key of a length pso_skey_parse does not read
# Usage: merge_pso_lists.py [--map shader_map.tsv] -o out.tsv list1.tsv list2.tsv ...
import argparse, collections, sys
STAGE = {'vertex': 0, 'pixel': 1, 'geometry': 2, 'hull': 3, 'domain': 4, 'task': 3, 'mesh': 4, 'compute': 5}   # nvn_mtl.m stage_of
KEY_LENGTHS = (1024, 1008, 880, 864)   # pso_skey in hex: now, before the border field, before the high attributes, before the alpha test field
def canon(c):
    if c[0] in ('R', 'M'): return (c[0],) + tuple(c[1:-1]) + (c[-1].lower().rstrip('0'),)
    return tuple(c)
def name(h, off):   # one of the two 24-byte shader names at the head of a hex key
    try: return bytes.fromhex(h[off:off + 48]).split(b'\0')[0].decode('ascii')
    except ValueError: return '?'
def refuse(c, stage):   # why this host does not take the row with that map (None: it takes it); stage: map key -> stage number
    def st(k): return stage.get(k[:-2] if k.endswith('_b') else k)
    if c[0] in ('S', 'C'):
        if c[0] == 'S' and len(c) < 3: return 'length'
        if st(c[1]) is None: return 'version'
        want = 5 if c[0] == 'C' else int(c[2]) if c[2].lstrip('-').isdigit() else -1
        return None if st(c[1]) == want else 'stage'
    h = c[-1]
    if len(h) not in KEY_LENGTHS: return 'length'
    vs, fs = name(h, 0), name(h, 48); vst, fst = int(h[96:98], 16), int(h[98:100], 16)
    if not vs or st(vs) is None or (fs and st(fs) is None): return 'version'
    if c[0] == 'M':
        if len(c) != 3: return 'length'
        if c[1] != '-' and st(c[1]) is None: return 'version'
        if vst != 4 or st(vs) != 4 or (fs and (fst != 1 or st(fs) != 1)) or (c[1] != '-' and st(c[1]) != 3): return 'stage'
        return None
    return 'stage' if st(vs) != vst or (fs and st(fs) != fst) else None
ap = argparse.ArgumentParser(); ap.add_argument('--map'); ap.add_argument('-o', required=True); ap.add_argument('lists', nargs='+'); a = ap.parse_args()
stage = None
if a.map:
    stage = {}
    for l in open(a.map):
        f = l.rstrip('\n').split('\t')
        if not l.startswith('#') and len(f) > 3 and f[2] in STAGE: stage[f[3]] = STAGE[f[2]]
seen, out = set(), []
for path in a.lists:
    n = added = 0; gone = collections.Counter()
    for l in open(path):
        l = l.rstrip('\n')
        if not l or l.startswith('#'): continue
        c = l.split('\t')
        if c[0] not in ('S', 'C', 'R', 'M') or len(c) < 2: continue
        n += 1
        why = refuse(c, stage) if stage is not None else None
        if why: gone[why] += 1; continue
        k = canon(c)
        if k in seen: continue
        seen.add(k); out.append(l); added += 1
    left = ''.join(f', {v:,} left out ({k})' for k, v in sorted(gone.items()))
    print(f'{path}: {n:,} rows, {added:,} new{left}', file=sys.stderr)
kinds = {t: sum(1 for l in out if l.startswith(t + '\t')) for t in 'SCRM'}
head = '# Prewarm seed list, merged by mkw/merge_pso_lists.py from: ' + ', '.join(p.rsplit('/', 1)[-1] for p in a.lists)
if stage is not None: head += '\n# Only rows the host takes with ' + a.map.rsplit('/', 1)[-1] + ' of that build: every shader in the map, at the stage the map gives it'
open(a.o, 'w').write(head + '\n' + '\n'.join(out) + '\n')
print(f'{a.o}: {len(out):,} rows ({", ".join(f"{v:,} {k}" for k, v in kinds.items())})', file=sys.stderr)
