#!/usr/bin/env python3
# Checks a dump folder downloaded over FTP against the server's own directory listings (.listing files):
# every listed file must exist with the listed size. Usage: verify_dump.py <dump>/updates/917504 [missing.txt]
import os, sys
root = sys.argv[1]; out = sys.argv[2] if len(sys.argv) > 2 else None
miss, bad, listed, nolist = [], [], 0, []
for d, _, fs in os.walk(root):
    if '.listing' not in fs: nolist.append(d); continue
    for line in open(os.path.join(d, '.listing'), errors='replace'):
        p = line.split(None, 8)
        if len(p) < 9 or p[8].strip() in ('.', '..'): continue
        name, size, isdir = p[8].rstrip('\r\n'), int(p[4]), p[0].startswith('d'); listed += 1
        path = os.path.join(d, name)
        if not os.path.lexists(path): miss.append(os.path.relpath(path, root))
        elif not isdir and os.path.getsize(path) != size: bad.append(os.path.relpath(path, root))
print(f'{listed:,} listed entries: {len(miss):,} missing, {len(bad):,} with another size; {len(nolist)} folders have no listing (not checked)')
if not os.path.isfile(os.path.join(root, 'exefs/main.npdm')): print('exefs/main.npdm is missing: the build stops without it')
if out: open(out, 'w').write('\n'.join(miss + bad) + '\n'); print('list written to', out)
sys.exit(1 if miss or bad else 0)
