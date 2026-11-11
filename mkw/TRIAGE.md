# Which changes are in, and why the others are not (2026-11-11, against upstream `352e4a6e`)

The rule: a change goes into `mkw-fixes` only if (1) it corrects wrong behaviour (it is not a speed-up, a feature or a tool), (2) there is evidence that
this game on this Mac meets the fault (measured on the game, or shown with the host's own code on a path the game takes), and (3) it leaves the shader
chain alone. Everything else waits as a candidate until a run shows its symptom, and is then measured alone against `mkw-fixes` (`mkw/test/host.py`).
788 open upstream pull requests were listed by the files they touch (399 touch code this game runs). About 70 were read at least as far as their summary.
Read in full, message and code: everything under "In", "speed" and "left out", and #2240, #1482, #1781. The symptom candidates were read by their summary only:
read each in full before it is tried.

## In `mkw-fixes`

| Change | From | The fault | Evidence for this game |
|---|---|---|---|
| `mem_map_limit on` | PR #1594 (seedds) | the host mapped memory past the 9 GB pool where the console refuses, so the game never freed its streaming blocks | measured on the game: free roam 7.8 → 9.4 GB in 12 minutes on a 16 GB M1 Pro without it |
| One-off frames do not raise the hold | PR #2091 (cocoman93) | one long frame after a loading screen led to three late frames and a longer hold | found on Ocarina; the code path is every game's with a frame step, and this game has one. `t_fstep` |
| `fps_step_max 2` | ours | the host held 3 vsyncs and paid back with steps of 3, the game takes at most 2: 20 fps at two thirds speed | upstream's own note: game time 0.977 "in the one window with 3-vsync holds"; `t_fstep` with and without (32.5 vsyncs of game time lost after three 42 ms frames, now 0.5) |

## In `mkw-test` only (a tool, not a fix)

`DM_CTL` lines `p2:` … `p8:` (scripted controllers for players 2 to 8), from PR #1781 (uncraftablexd), with holds that run side by side.

## Candidates: speed (each a variant that builds today; measure one at a time)

| Variant | Change | Its author's measurement |
|---|---|---|
| `c1179` | PR #1179, multi-draws copied when their pass opens | this game, M4 Pro: GPU p50 13.0 ms against 13.65-14.1 |
| `c1437` | PR #1437, `DM_NVN_GPU_TS_PAD` (only its stretch; off unless set) | steadier 60 through an earlier resolution step |
| `c1847` | PR #1847, the maintainer's heavy-frame branch | Donkey Kong Bananza (same engine) |
| `c1970` | PR #1970, passes overlap the previous one's fragments | Ocarina, M1: GPU p50 39.5 → 37.2 ms. Carries a one-line ordering fix for mesh stages that its relaxed barriers need |
| `perfstack` | #1179 + #1437 + #1847 | to run only after each alone |
| data | PR #2097's prewarm list; `mkw/pso/pso_manifest_merged_180.tsv` | iPhone, 1.8.0: 115 long frames in 7,800 → 23 in 28,700. `host.py --list` |

## Candidates: real fixes whose fault has not been seen on this game (symptom → change)

| If a run shows | Then try | Merges today? |
|---|---|---|
| the cup movie stutters; `[RED] … packet refused with N pictures waiting` (seen on 1.8.0, PR #2064) | PR #2240, video decoders on their own threads | yes: variant `c2240` |
| 30 fps for seconds after a hitch while the GPU is nearly idle (menus, loading) | PR #1942, late frames with an idle GPU do not raise the hold | no: same function as #2091, needs a port |
| a material flickers between two looks; wrong texture on one variant of a shader | PR #2249 (argument block reused after another variant), PR #2228 (texture handle tables after inline updates) | yes, both |
| holes in bushes or grass | PR #2226, an indirect dispatch joined a copy encoder | yes |
| a texture misses an update that a GPU copy made | PR #2182 | yes |
| vertices stretched to the origin, flickering meshes | PR #2219, Switch 2 uniform reads bounded by the binding's size | no |
| a wrong texture after many textures were made (storage takeover, sRGB twin) | PR #2323 | no (upstream changed the function today) |
| black dots on alpha-tested surfaces (fur, foliage) | PR #2198, discard then early return | changes the chain |
| GPU memory grows while the resolution moves | PR #2312, moved render targets leave memory | no |
| the controller screen reopens for ever with more controllers than players | PR #1781's second commit | not tried |
| the Mac freezes at the GPU memory limit | PR #1482, a guard inside the host | no; `mkw/test/watchdog.sh` stands in |
| distant surfaces flicker at the far plane | PR #2199 (found on Mario Kart 8 Deluxe) | changes the chain |
| wrong shading where a surface meets a reflection or uses screen derivatives | the FSWZADD sign table (mkw/KNOWLEDGE.md, section 8) | ours to write; changes the chain |

## Read and left out

| Change | Why |
|---|---|
| PR #1599, soft textures | only with `DM_NVN_TEX_SOFT=1`, which lowers texture quality to save memory we have |
| PR #1713, #1709, #2126 | opt-in measuring switches and a shorter log; take one when a measurement needs it |
| PR #2064, #2098 | notes. Their facts are in mkw/KNOWLEDGE.md; merging them would re-derive the profile |
| mkw-neo `aaedc620` | a keyboard map, an icon, a build script; its upload gate matters only with `DM_GUEST_FILE=1` |
| PR #1873, macOS 26's indexed draws drop an index | real macOS fault, but by its own text no draw of the host has the losing shape: a guard for the future |
| PR #1978, a GPU time read in its own clock tick | needs two clock reads within one 42 ns tick; it fixes a flaky test |
| PR #2176 | only under Metal's validation layer |
| PR #1230 as written | its NaN-guard rewrite removes the pattern upstream's readable-tile rewrite matches |
| PR #1245, #1247, #1252, #1407, #1143 | 28 to 110 conflict hunks each against today's upstream; #1252's purpose (1.8.0) is served by the derived profile |

The earlier combined branches (`old/mkw-m2pro`, `old/mkw-m2pro-perf`, `old/mkw-m2pro-perf2`, on upstream `084f5aa5`) are kept for reference only.
