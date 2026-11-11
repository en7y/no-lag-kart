#!/usr/bin/env python3
"""Is the frame-interval function of the profile's frame-step rule in this main? Run before a build: without a match the game keeps its own interval choice.

  ~/nup/.venv/bin/python3 mkw/check_frame_fn.py <dump>/updates/917504/exefs/main [--dis]

It loads the module as the rewriter does (dm/tools/nso.py), asks the rewriter's own matcher (dm/tools/nso_match.py) for the rule's function, and with --dis
prints the function's code around the interval choice (capstone), so what the game does with a slow frame can be read from the game itself."""
import importlib.util, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'dm/tools'))
import nso, nso_match   # noqa: E402

ID = '0400C3F00006E000'
spec = importlib.util.spec_from_file_location('patches', REPO / 'dm/games' / ID / 'patches.py')
P = importlib.util.module_from_spec(spec)
try: spec.loader.exec_module(P)
except Exception as e: sys.exit(f'cannot load the profile\'s patches.py outside the rewriter: {e!r}')
rules = P.MATCH_FRAME_STEP['main']
mod = nso.read(sys.argv[1])
print(f'main build ID {mod.build_id[:16].hex()}, text {mod.text_end:#x} bytes')
img = nso_match.Image(mod.image, mod.text_end)
print(f'{len(img.functions)} functions with unwind information')
for r in rules:
    try: start = img.locate(r['size'], r['fingerprints'])
    except nso_match.MatchError as e:
        print(f'NO MATCH for {r["name"]!r} (size {r["size"]:#x}): {e}'); start = None
        same = [s for s, e2 in img.functions.items() if e2 - s == r['size']]
        print(f'  functions of that size in this main: {len(same)}')
    else: print(f'MATCH: {r["name"]!r} is the function at main+{start:#x}')
    if start is not None and '--dis' in sys.argv:
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        for i in md.disasm(bytes(mod.image[start + 0x80:start + 0x170]), start + 0x80): print(f'  +{i.address - start:#05x}  {i.mnemonic:8s}{i.op_str}')
