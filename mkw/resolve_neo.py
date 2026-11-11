#!/usr/bin/env python3
# Resolves the cherry-pick of mkw-neo aaedc620 onto upstream main + PR #1599 (run in the repo root).
import re, pathlib, sys
def sub1(path, pat, rep, flags=re.S):
    p = pathlib.Path(path); s = p.read_text()
    s2, n = re.subn(pat, rep, s, count=1, flags=flags)
    if n != 1: sys.exit(f'{path}: pattern not found: {pat[:60]}')
    p.write_text(s2)
# 1. the CPU upload gate: soft textures (upstream, PR #1599) or a guest block in files (mkw-neo)
sub1('dm/gfx/nvn/nvn_mtl.m',
     r'<<<<<<< [^\n]*\n(.*?)int keep_cpu = tex_soft\(t\) && (.*?)\n=======\n.*?>>>>>>> [^\n]*\n',
     lambda m: m.group(1) + '// ... or while the guest block is in files (mkw-neo): a GPU upload would take a buffer over the guest\'s pages and Metal would wire the whole range\n'
               '    int keep_cpu = (tex_soft(t) || dm_guest_file_backed()) && ' + m.group(2) + '\n')
# 2. upstream already has mtl_pool_wrapped (not static): drop mkw-neo's copy
sub1('dm/gfx/nvn/nvn_mtl.m',
     r'// Whether a zero-copy buffer covers any of \[addr, addr\+len\): pages under one cannot be given back \(nvn_dirty_release\)\nstatic int mtl_pool_wrapped\(.*?\n}\n', '')
# 3. upstream already defines dm_guest_file_backed
sub1('dm/host/hle_svc.c', r'<<<<<<< [^\n]*\n(.*?)=======\n.*?>>>>>>> [^\n]*\n', lambda m: m.group(1))
# 4. the profile keeps upstream's keys (+ PR #1594's mem_map_limit); handheld mode is a player setting (DM_OPMODE=0), not a profile default
sub1('dm/games/0400C3F00006E000/game.tsv', r'\n# What a 1\.0\.0 dump needs on 8 GB of Mac.*?op_mode\thandheld\n', '\n')
print('resolved')
