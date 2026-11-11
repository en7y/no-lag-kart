"""shader_split: bahs_shaders finds an agl BAHS file's program entries (code offset, 0, control length, control distance) by scanning its table area, and a control section's own
words can read as one. An NVN2 section's +0x38..+0x47 (instruction length, c1 start and end, code length, here 0x100, 0, 0x100, 0x100) is such an entry: its control distance lands on
the next program's control section, its offset on that program's code, and the shader it made paired one program's control with whatever code lay there. Ocarina of Time's
agl_common.sharcb@0x357f0 gave a compute control and a vertex shader's code, whose SPH the translator read as an instruction ("Ampere instruction 481 at 0x0"); six such entries in
its agl and terrain files, none ever loaded. The terrain file's lowest one also kept bahs_variations from finding the binary array, so tera_common gave no variation pairs. No game files."""
import struct
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/tools/fuzz'))
import fuzz_shader_split as fz   # shader_split with a profile
ss = fz.ss

REGION, CODE = 0x400, 0x100   # the code region's start; each program's code area length


def nvn2_ctl(stage):
    """An NVN2 control section (0xe0 bytes): magic, version 0xc9, +0x38 instruction length, +0x40 / +0x44 c1 start and end (= the code area's length), +0x56 the stage byte"""
    c = bytearray(0xe0); c[:4] = ss.CTL_MAGIC; c[4:8] = b'\xc9\0\0\0'
    struct.pack_into('<4I', c, 0x38, CODE, 0, CODE, CODE); c[0x56] = stage
    return c


def bahs():
    """Two vertex programs: entries at 0x100 and 0x238, each with its control 0x68 after it (0x168, 0x2a0), code at the region's +0 and +0x100. A's control words at
    0x1a0 read (0x100, 0, 0x100, 0x100): an entry whose control is B's (0x1a0 + 0x100) and whose code is B's"""
    d = bytearray(REGION + 2 * CODE)
    struct.pack_into('<II', d, 0x18, 2 * CODE, REGION)   # code region length, its start
    for entry, off in ((0x100, 0), (0x238, CODE)):
        struct.pack_into('<IIIi', d, entry, off, 0, 0xe0, 0x68)
        d[entry + 0x68:entry + 0x68 + 0xe0] = nvn2_ctl(0)
        code = bytearray(CODE); struct.pack_into('<I', code, 0, 0x000c0481 + off)   # an SPH, vertex (word 0: type 1, stage 1 in bits 10..13), told apart by its offset
        d[REGION + off:REGION + off + CODE] = code
    assert struct.unpack_from('<IIIi', d, 0x1a0) == (CODE, 0, CODE, CODE) and 0x1a0 + CODE == 0x2a0
    return bytes(d)


class ControlWordsAreNoEntry(unittest.TestCase):
    def test_only_the_two_programs(self):
        got = ss.bahs_shaders(bahs(), 'f.sharcb')
        self.assertEqual([w for w, *_ in got], ['f.sharcb#BAHS@0x100', 'f.sharcb#BAHS@0x238'])
        self.assertEqual([st for _, st, _, _ in got], ['vs', 'vs'])

    def test_the_false_entry_is_a_candidate_without_the_rule(self):   # the scan's own checks take it: the rule is what leaves it out
        d = bahs()
        off, z, csz, rel = struct.unpack_from('<IIIi', d, 0x1a0)
        c = 0x1a0 + rel
        self.assertTrue(ss.nvn2_ctl(d[c:c + csz]) and not z and off % 0x100 == 0 and ss.check('f', 'vs', d[c:c + csz], d[REGION + off:REGION + off + CODE]) is None)


def bahs_table_row():
    """A vertex program and a compute program, each entry 0x68 before its control section (0x168 and 0x3a0), code at the region's +0 and +0x100. Four bytes past the vertex
    program's control section a table row, (0, 0, 0x150, the distance to the compute control section), reads as an entry: the compute control at a length of 0x150 with the code
    at the region's +0, the vertex shader's. Mario Kart World 1.8.0's DrivePassShaderDefault.sharcb@0xa1de4 is such a row, and it lies in no control section"""
    region = 0x600
    d = bytearray(region + 2 * CODE)
    struct.pack_into('<II', d, 0x18, 2 * CODE, region)
    for entry, off, stage, word in ((0x100, 0, 0, 0x000c0481), (0x338, CODE, 5, 0x0000794d)):   # the vertex code starts with its SPH, the compute code with an instruction
        struct.pack_into('<IIIi', d, entry, off, 0, 0xe0, 0x68)
        d[entry + 0x68:entry + 0x68 + 0xe0] = nvn2_ctl(stage)
        code = bytearray(CODE); struct.pack_into('<I', code, 0, word)
        d[region + off:region + off + CODE] = code
    row = 0x168 + 0xe0 + 4
    struct.pack_into('<IIIi', d, row, 0, 0, 0x150, 0x3a0 - row)
    return bytes(d), row, region


class TableRowIsNoEntry(unittest.TestCase):
    def test_only_the_two_programs(self):
        d, _, _ = bahs_table_row()
        got = ss.bahs_shaders(d, 'f.sharcb')
        self.assertEqual([w for w, *_ in got], ['f.sharcb#BAHS@0x100', 'f.sharcb#BAHS@0x338'])
        self.assertEqual([st for _, st, _, _ in got], ['vs', 'cs'])
        self.assertEqual(struct.unpack_from('<I', got[1][3], 0)[0], 0x0000794d)   # the compute program has its own code, not the vertex shader's
        self.assertEqual({len(ctl) for _, _, ctl, _ in got}, {0xe0})

    def test_the_row_is_a_candidate_without_the_rule(self):   # it passes the scan's own checks and lies in no control section: only the section's length tells
        d, row, region = bahs_table_row()
        off, z, csz, rel = struct.unpack_from('<IIIi', d, row)
        c = row + rel
        self.assertTrue(ss.nvn2_ctl(d[c:c + csz]) and not z and off % 0x100 == 0 and c + csz <= region)
        self.assertIsNone(ss.check('f', 'cs', d[c:c + csz], d[region + off:region + off + CODE]))
        self.assertEqual(ss.nvn2_stage(d[c:c + csz], d[region + off:region + off + CODE]), 'cs')
        self.assertFalse(any(lo <= row < lo + ss.ctl_len(d[lo:lo + 0xe0]) for lo in (0x168, 0x3a0)))

    def test_a_file_whose_sections_have_two_lengths_keeps_both(self):   # a length is only wrong against the same section's other entries
        d, row, region = bahs_table_row()
        d = bytearray(d); struct.pack_into('<IIIi', d, row, 0, 0, 0, 0)   # no table row
        struct.pack_into('<IIIi', d, 0x338, CODE, 0, 0x150, 0x68)        # the compute program's own entry gives its section 0x150
        got = ss.bahs_shaders(bytes(d), 'f.sharcb')
        self.assertEqual([(w, st, len(ctl)) for w, st, ctl, _ in got], [('f.sharcb#BAHS@0x100', 'vs', 0xe0), ('f.sharcb#BAHS@0x338', 'cs', 0x150)])


if __name__ == '__main__':
    unittest.main()
