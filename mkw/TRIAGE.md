# What is in `mkw-fin`, and what was measured and left out (2026-11-12, on upstream `352e4a6e`)

The rule: a change goes in only if a run on this Mac showed that it helps this game, or if it corrects wrong behaviour on a path the game takes and leaves the
shader chain alone. A change that could show no gain here stayed out, whatever its author measured on another Mac or game. Every figure is from this Mac
(16 GB M2 Pro, macOS 26.7.1), update 1.8.0, the routes of `dm/games/0400C3F00006E000/bench.tsv`, mostly one run a variant; the measurements with their runs
are in `dm/games/0400C3F00006E000/README.md` ("Frame rate") and `docs/reference/frame-rate.md`. 788 open upstream pull requests were listed by the files they
touch on 2026-11-11 (about 70 read at least as far as their summary), and the 98 that were new or changed by 2026-11-12 were listed again by title; everything
under "In" and "left out" was read in full, message and code.

## In: our own fixes (11)

| # | Fix | Commits | What it changed here |
|---|---|---|---|
| 1 | The frame step ends at the game's longest step (`fps_step_max 2`) | `bd3c1a07` | no hold of 3 vsyncs at two thirds of the game's speed |
| 2 | Update 1.8.0 gets the frame step: its frame-interval function is found by a second fingerprint | `17b21cb8` | no slow motion after a late frame on 1.8.0 |
| 3 | A prewarm line that names a shader at another stage than the shader map's is left out | `a8ea6379` | 19 rows of an online list stopped the prepare step |
| 4 | A table row after a control section is no BAHS program entry | `01866e0a` | 1.8.0's shader packages split cleanly |
| 5 | Render pipelines compiled whole (`pso_whole`) | `999d1a69` | GPU 14.1 → 12.6 ms a frame; late frames 48 → 1 to 6 a minute |
| 6 | Task and mesh draws join slice-merged passes | `3bae4c7a` `bb80e339` `bf483269` | sky cube map 13 passes a view → 6; GPU 13.0 → 12.3 ms; four players 26.8 → 28.8 fps |
| 7 | A memory pool's Finalize costs what the pool holds | `af955680` `c592270b` `4574601d` | the 50 to 70 ms freeze once per stretch of track: 14 of 17 runs → 1 of 12 |
| 8 | A sparse texture shares storage only with pools its pool has mapped pages of | `af5f0aca` | sky cube map 6 passes a view → 1; GPU 12.4 → 11.85 ms |
| 9 | Split outputs: the reflection filters drawn once for each cube face (`fs_split`) | `69b833e7` `35defcb7` | filters 1,440 → 950 µs a view; two players 54 → 19 late frames a minute |
| 10 | The timestamp pad counts from the frame's first submission | `69b833e7` `35defcb7` | the pad acts on this game at all: two players 19 → 0 late frames a minute, four 15 → 0 |
| 11 | A submission's commit walks the pages its shaders wrote, not the whole page set | `3e947644` | replay thread 1.4 ms a frame faster at a four-player race's start |

Ten have a test in `dm/gfx/tests` or `dm/tools/tests` that fails without the fix; the second is checked against the game's code by its fingerprint.
Tools that are not fixes: `DM_CTL` lines `p2:` … `p8:` (scripted controllers, from PR #1781's idea, `d65a64ff`), `DM_SUBPROF` (the queue worker's stacks in a
long frame), `DM_NVN_TS_LOG` (a frame's GPU timing reports), memory rows in `frames.tsv`, and `mkw/test`.

A build step that is not a fix either: the host is compiled with a profile of its own runs (`b629eec9`, `mkw/pgo/README.md`). With four players the replay
thread takes 7 to 11 % less time a draw, and a whole four-player Grand Prix had 24 late frames where it had 71.

## In: from other people (14 pull requests, 5 later upstream commits)

| Change | From | Why it is in |
|---|---|---|
| #1594, `mem_map_limit on` | seedds | the game frees its streaming blocks: no growth past the 9 GB pool in free roam |
| #2091 | cocoman93 | one long frame after a loading screen no longer lengthens the hold |
| #2249, #2228, #2226, #2182, #2225, #2194, #2273 | Pedro Nascimento, seedds, humanperzeus, FifteenPen | correctness on paths this game runs: argument blocks, handle tables, indirect dispatches, shared textures, dirty tracking, present timing, masked clears |
| #1437, `DM_NVN_GPU_TS_PAD` | upstream PR | the pad itself; fix 10 makes it act on this game |
| #1847 | seedds | slice-merged passes and the GPU clock keeper: four players 21.0 → 26.8 fps |
| #2408 | Sennbon-99 | a sparse mapping starts a new texture ID epoch only when it is new: replay thread 8 % faster |
| #2328 | dean0396 | a pool buffer retired while a submission commits waits for that submission |
| #2348 | PromethOps | fullscreen on a fixed 60 Hz screen (a TV) whose presents keep turning a refresh late; not measured here (no TV connected) |
| `f9cbc09f` `a80ac555` `44255e5b` `291f9337` `44287f11` | upstream `main` after the base | two controller fixes (the controller screen reopening, a Pro Controller counted twice), a storage takeover fix, a texture layout fix, a movie texture fix |

Data: the warm-up list, 15,062 rows merged from 10 lists of 6 repositories (`mkw/pso/README.md`).

## Measured and left out

| Change | What the run showed |
|---|---|
| PR #1970, passes overlap the previous one's fragments (`DM_NVN_BARRIER=game`) | four players 10 % slower, twice (24.1 against 26.8 fps) |
| A bundle of 9 speed pull requests at once | no gain over the fix set (59.0 to 59.4 fps either way), 5 % more CPU instructions a draw |
| PR #2341, replay ahead and a second cache of texture views | replay ahead never starts (this game parks no queue on an event its CPU signals); the cache made 2 % fewer views |
| Frame buffering (present snapshots) | no change with two or four players |
| Display link at frame latency 2 | 262 late frames a minute |
| The pad as upstream has it (from each submission), at 1.10, 1.20, 1.60 | no effect: this game times its frame across 23 to 42 submissions (hence fix 10) |
| Pad 1.35 in place of 1.25 | the same zero late frames, a lower render size |
| GPU clock keeper off / `auto` | off: four players 24.9 fps; `auto`: one player draws 20 to 25 % fewer pixels with the pad |
| Upstream `d2556cff`, partial texture re-upload | this game re-uploads no texture in a race |
| Segment size, pass merging off, compute hoisting off, submission-level timestamps, the Metal HUD | each within run-to-run noise |
| Reading a batch's upload sources and a new pool's memory on several cores before the residency commit (ours, 2026-11-12) | the cut to the starting grid got longer, 196 against 139 ms: its sources are resident already, and the commit's cost is its count (below) |

## Open: the long frame at a scene cut

The first frame of the starting grid takes 45 ms with one player and 117 to 170 ms in split screen; the cut to the results 86 to 117 ms. In that frame
(four players, one run with a log of every upload source): 618 textures first uploaded, each with two zero-copy source buffers; 100 memory pools made resident,
each with a residency commit of its own (26 ms together); 28 batch commits (16 ms); about a quarter of the replay's time creating those 2,000 Metal objects.
Candidates, none taken: PR #2342 and PR #2378 (the second source buffer only when the staging began a new batch: in our run the source calls halved, 8.8 → 4.3 ms,
which is inside the cut frame's run-to-run range), PR #2379 (residency changes under a lock of their own), and one residency commit for a submission's new pools
instead of one each (not tried: a pool the GPU reaches before its commit is a GPU fault). What would remove the frame is making these objects before the cut,
during the loading screen; that needs to know first how many registered textures are never drawn.

## Not tried

| Change | Why |
|---|---|
| Upstream `224ecb18` and PR #2198, #2199 | each changes the shader chain: all 11,601 shaders built again, for no fault seen in this game |
| PR #2413, task and mesh shaders as compute (`DM_NVN_MESH_COMPUTE=1`) | new on 2026-11-12, 528 lines, opt-in; its author measured 3.6 % of GPU time on another game's slow spot on an M1. This game has 25 task and mesh shaders (bushes and grass): worth one run |
| PR #2374, #2344, #2329, #2330, #2412 | real fixes whose fault no run of this game showed |
| Unretained locals in the replay's hot paths (12.6 % of the replay thread is Objective-C retain and release) | code changes in the hottest paths; to measure on `gp150-4p-r2` and a whole `gp150-4p-full` |

The first triage of 2026-11-11 (before the game ran here) and the earlier combined branches are in this file's history and in `old/…`.
