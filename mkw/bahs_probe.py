#!/usr/bin/env python3
# What does shader_split.py's BAHS scan (agl's .sharcb shader files) read as program entries, and which of them are none?
#   bahs_probe.py <repo> <romfs dir or RomFS.img> <archive path in RomFS, .sarc or .sarc.zs>                       one line per .sharcb member: its entries, the control
#                                                                                                                  lengths they give, and every entry a rule takes out
#   bahs_probe.py <repo> <romfs dir or RomFS.img> <archive path> <member name ending> <entry address, hex>         one entry: its words, the other entries that name its
#                                                                                                                  control section or its code, and which rule takes it out
# An entry is (code offset, 0, control length, distance to the control section). A real one lies 0x68 before its own section or in a variation table that names a section
# before it; the code's header gives the same stage as the control section's stage byte (+0x56: 0 vertex, 1 pixel, 5 compute, 6 task, 7 mesh).
# Needs DM_GAME=<title id> and the Python the pack uses (zstd dictionaries).
import collections, os, struct, sys
repo, romfs, arc_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.path.insert(0, os.path.join(repo, 'dm/gfx/tools')); sys.path.insert(0, os.path.join(repo, 'dm/tools'))
import shader_split as ss
ropen = getattr(ss, 'open', open)   # the splitter's own open reads inside a RomFS image too
ss.ZDICTS = ss.zs_dicts(romfs); ss._ZD = {}
path = os.path.join(romfs, arc_path.lstrip('/'))
arc = ss.unzs(path) if path.endswith('.zs') else ropen(path, 'rb').read()
E = collections.namedtuple('E', 'a c csz off n st rel byte word key')
STAGE_BYTE = {'vs': 0, 'ps': 1, 'cs': 5, 'ts': 6, 'ms': 7}

def scan(d, member):   # the scan of bahs_shaders, before its two rules
    rsz, region = struct.unpack_from('<II', d, 0x18)
    found = []
    for a in range(0, region - 16, 4):
        off, z, csz, rel = struct.unpack_from('<IIIi', d, a)
        nvn2 = 0x48 <= csz < 0x10000 and 0 <= a + rel and a + rel + csz <= region and ss.nvn2_ctl(d[a + rel:a + rel + csz])
        if z or not (nvn2 or csz in (0x880, 0x88c) or 0x760 <= csz < 0x880) or off % 0x100: continue
        c = a + rel
        if c < 0 or c + csz > region or d[c:c + 4] != ss.CTL_MAGIC: continue
        n = struct.unpack_from('<I', d, c + (0x44 if nvn2 else 0x704))[0]
        if off + n > rsz: continue
        code, ctl = d[region + off:region + off + n], d[c:c + csz]
        st = ss.nvn2_stage(ctl, code) if nvn2 else None
        if not st or ss.check(member, st, ctl, code): continue
        found.append(E(a, c, csz, off, n, st, rel, ctl[0x56] if len(ctl) > 0x56 else -1, d[region + off:region + off + 4][::-1].hex(), ss.skey(ctl, code)))
    return found, region, rsz

def rules(d, found):   # → (entries the rule "one control section has one length" takes out, entries inside another section's key bytes, the usual length)
    usual = collections.Counter(e.csz for e in found).most_common(1)[0][0]
    named = collections.defaultdict(set)
    for e in found: named[e.c].add(e.csz)
    by_len = [e for e in found if e.csz != usual and usual in named[e.c]]
    spans = sorted({(e.c, e.c + ss.ctl_len(d[e.c:e.c + e.csz])) for e in found})
    inside = [e for e in found if any(lo <= e.a < hi for lo, hi in spans)]
    return by_len, inside, usual

def show(e, note=''):
    print(f'  entry {e.a:#x}: control {e.c:#x} (distance {e.rel:+#x}), control length {e.csz:#x}, code at +{e.off:#x} for {e.n:#x} bytes, first code word {e.word}, '
          f'stage {e.st}, control byte +0x56 = {e.byte}, key {e.key}{note}')

top = lambda it, k=6: ', '.join(f'{v} × {n}' for v, n in collections.Counter(it).most_common(k))
members = [(name, m) for name, m in ss.sarc_members(arc, arc_path) if m[:4] == b'BAHS']
if len(sys.argv) < 6:   # every member
    for name, d in members:
        found, _, _ = scan(d, name)
        if not found: print(f'{name}: no entry'); continue
        by_len, inside, usual = rules(d, found)
        wrong = [e for e in found if STAGE_BYTE.get(e.st) != e.byte]
        print(f'{name}: {len(found)} entries; control length {top(hex(e.csz) for e in found)}; stage by the code against the control byte differs for {len(wrong)}; '
              f'inside a control section {len(inside)}; another length than its section\'s other entry {len(by_len)}, of which not inside a section {len([e for e in by_len if e not in inside])}')
        for e in by_len:
            if e not in inside: show(e, '; the stages agree' if e not in wrong and e.st != 'cs' else '')
        left = [e for e in wrong if e not in by_len and e not in inside]
        if left: print(f'  {len(left)} entries stay whose code gives another stage than the control byte: ' + ', '.join(f'{e.a:#x} ({e.st}/{e.byte})' for e in left[:8]))
    sys.exit(0)
member, a0 = sys.argv[4], int(sys.argv[5], 16)
name, d = next((name, m) for name, m in members if name.endswith(member))
found, region, rsz = scan(d, name)
by_len, inside, usual = rules(d, found)
print(f'{name}: {len(d):#x} bytes, code region at {region:#x}, {rsz:#x} bytes; {len(found)} entries pass the scan, at {min(e.a for e in found):#x}..{max(e.a for e in found):#x}')
print('  control length an entry gives:', top(hex(e.csz) for e in found))
print('  entry to its control section :', top(f'{e.rel:+#x}' for e in found))
print('  stage by the code / control byte +0x56:', top((f'{e.st}/{e.byte}' for e in found), 12))
odd = [e for e in found if e.csz != usual]
print(f'entries that give another control length than the usual {usual:#x}: {len(odd)}')
for e in odd[:12]: show(e, ('; its section has an entry of the usual length too' if e in by_len else '') + ('; inside a control section' if e in inside else ''))
me = [e for e in found if e.a == a0]
if not me: sys.exit(f'no entry passes the scan at {a0:#x}')
me = me[0]
print('the entry asked about:'); show(me)
print('  the 4 words before it and its own:', ' '.join(f'{x:#x}' for x in struct.unpack_from('<4I', d, me.a - 16)), '|', ' '.join(f'{x:#x}' for x in struct.unpack_from('<4I', d, me.a)))
same = [e for e in found if e.c == me.c and e.a != me.a]
print(f'other entries that name control section {me.c:#x}: {len(same)}')
for e in same[:6]: show(e)
sharers = [e for e in found if e.off == me.off and e.a != me.a and e.c != me.c]
print(f'entries of other control sections whose code is at +{me.off:#x} too: {len(sharers)}')
for e in sharers[:3]: show(e)
print(f'rule "an entry never lies inside a control section": {"takes it out" if me in inside else "keeps it"}')
print(f'rule "one control section has one length": {"takes it out" if me in by_len else "keeps it"} (usual length {usual:#x})')
