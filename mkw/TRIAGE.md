# What is in `mkw-fin3`, and what was measured and left out (2026-11-14, on upstream `352e4a6e`)

The rule: a change goes in only if a run on this Mac showed that it helps this game, or if it corrects wrong behaviour on a path the game takes and leaves the
shader chain alone. A change that could show no gain here stayed out, whatever its author measured on another Mac or game. No setting that lowers the picture
counts as a fix: the two that did on 2026-11-13 (the GPU-time pad at 1.25 and handheld mode for a split screen) are gone from the settings. PR #1230, which
changes the shader chain, came last, with every shader built again. Every figure is from this Mac (16 GB M2 Pro, macOS 26.7.1), update 1.8.0, the routes of
`dm/games/0400C3F00006E000/bench.tsv`, mostly one run a variant; the measurements with their runs are in `dm/games/0400C3F00006E000/README.md` ("Frame rate"),
`mkw/KNOWLEDGE.md` (section 0) and `docs/reference/frame-rate.md`. 788 open upstream pull requests were listed by the files they touch on 2026-11-11 (about 70 read
at least as far as their summary), and the 98 that were new or changed by 2026-11-12 were listed again by title, as were those opened up to 2026-11-13 (#2418 to
#2537) and the eleven of a Reddit post for M1 and M2 Macs (2026-11-13); everything under "In" and "left out" was read in full, message and code.

## In: our own fixes of 2026-11-11 to 13 (12)

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
| 10 | The timestamp pad counts from the frame's first submission | `69b833e7` `35defcb7` | the pad acts on this game at all: two players 19 → 0 late frames a minute, four 15 → 0 (the pad is not set since 2026-11-14) |
| 11 | A submission's commit walks the pages its shaders wrote, not the whole page set | `3e947644` | replay thread 1.4 ms a frame faster at a four-player race's start |
| 12 | The operation mode changes once the controller applet has found two or more players (`DM_OPMODE_MULTI`) | `1aed041f` | one player plays in console mode; a split screen holds 60, 30 and 30 fps where console mode gave 58.4, 29.6 and 29.3 (not set since 2026-11-14: console mode holds a split screen with fixes 13, 17 and 18) |

Eleven have a test in `dm/gfx/tests`, `dm/host/tests` or `dm/tools/tests` that fails without the fix; the second is checked against the game's code by its fingerprint.
Tools that are not fixes: `DM_CTL` lines `p2:` … `p8:` (scripted controllers, from PR #1781's idea, `d65a64ff`), `DM_SUBPROF` (the queue worker's stacks in a
long frame), `DM_NVN_TS_LOG` (a frame's GPU timing reports), memory rows in `frames.tsv`, `mkw/test`, and the profile key `mac_game_mode on` (the Mac app declares `LSSupportsGameMode`, `05531bd2`).

A build step that is not a fix either: the host is compiled with a profile of its own runs (`b629eec9`, `mkw/pgo/README.md`). With four players the replay
thread takes 7 to 11 % less time a draw, and a whole four-player Grand Prix had 24 late frames where it had 71. Recorded again on 2026-11-14 (fix 23).

## In: our own fixes since `mkw-fin` (2026-11-13 and 14)

Measured fullscreen on the built-in screen (fixed 60 Hz), Game Mode on, console mode, 150cc, one run each unless said, A/B on one host where a switch allows it. Runs before 2026-11-13 20:47 had the GPU-time pad on, in both arms of an A/B.

| # | Fix | Commit | What it changed here |
|---|---|---|---|
| 13 | The streamed submission: a submit call's copy of the game's commands no longer holds the submission lock, and each cut hands its nodes to the replay worker at once (`DM_NVN_SUBMIT_STREAM`, on) | `1395290e` | the GPU starts on a frame 0.9 ms after the game submits it, where it waited for the whole frame's copy; console mode, one host (2026-11-13, the pad still on in both arms): two players 58.7 → 59.9 fps (frames shown off their step 80 → 7 a minute), four players 29.4 → 29.9 (90 → 10) |
| 14 | MetalFX up to a player count (`DM_PRESENT_UPSCALE_PLAYERS`) | `75663f6b` | a switch only; not set: MetalFX stays on for every player count (plain present gave the game GPU time back as resolution, not frames) |
| 15 | The operation mode changes from a given player count (`DM_OPMODE_MULTI_FROM`) | `846881d6` | a switch for `DM_OPMODE_MULTI`; neither is set |
| 16 | A period's archive write and the pipeline compiles do not overlap (port of upstream `cc8f4490`) | `b5ee34b9` | Metal crashed when an archive write met a compile; this game fills its archive in bulk after a shader rebuild |
| 17 | Upload sources copied into a 128 MB resident ring (`DM_NVN_UP_COPY=128`) in place of a zero-copy buffer made resident for each upload | `3f9d1139` | a scene cut's residency work halves; cut frames 20 to 28 ms shorter (2026-11-13, the pad on in both arms) |
| 18 | The reflection filters' face-layered pass: a listed shader's draw into the faces of one cube map level up to 64x64 runs as one layered pass (`DM_NVN_FS_LAYER`, on) | `4d34eaf8` | a cube filter chain (64x64 to 2x2) 386 → 296 µs in a Metal harness; with the array filter split up to 64x64 two players hold 60 fps in console mode |
| 19 | The per-draw feedback checks read each binding's serial once and look a texture up only for an attachment | `1bbee5ac` | four players: the replay thread 0.5 to 0.8 ms less CPU a frame |
| 20 | `t_feedback`'s cut case waits for the earlier cases' command buffers (a test that read the queue's count too early) | `634ab294` | 279 checks pass, three runs of three |
| 21 | This Mac's settings without the two stopgaps; `DM_NVN_CUT=8` and `DM_NVN_UP_COPY=128`; the cube array filter split up to 64x64 (`fs_split 765844f5609bb11b:4096`) | `55beb3a8` | the before/after table in README.md; `DM_NVN_CUT` 64 against 8 on one host, four players, the heaviest minute: 10 and 38 frames off their step against 0 and 0, GPU 30.2 and 30.5 ms against 28.9 and 28.5 |
| 22 | The bench's `host_open.py` stops the game by its process ID; no process list without a time limit | `981c9aab` | a hung `pgrep` (a stuck macOS service) no longer leaves a game running beside the next start |
| 23 | The host's profile recorded again on this code | `399efa7d` | four players, the heaviest minute, one run each: the replay's CPU 24.58 → 24.44 ms a frame, GPU 28.67 → 28.93 ms: no measurable difference; kept because it matches the code it was made from (`mkw/pgo/README.md`) |

Fixes 10 (the timestamp pad counts from the frame's first submission) and 12 (`DM_OPMODE_MULTI`) stay in the code with their tests, and the settings no longer
use them: the pad and handheld mode for a split screen were stopgaps that lowered the picture, and since fixes 13, 17 and 18 with `DM_NVN_CUT=8`, split screen holds in console mode without them.

## In: from other people (15 pull requests, 5 later upstream commits)

| Change | From | Why it is in |
|---|---|---|
| #1594, `mem_map_limit on` | seedds | the game frees its streaming blocks: no growth past the 9 GB pool in free roam |
| #2091 | cocoman93 | one long frame after a loading screen no longer lengthens the hold |
| #2249, #2228, #2226, #2182, #2225, #2194, #2273 | Pedro Nascimento, seedds, humanperzeus, FifteenPen | correctness on paths this game runs: argument blocks, handle tables, indirect dispatches, shared textures, dirty tracking, present timing, masked clears |
| #1437, `DM_NVN_GPU_TS_PAD` | upstream PR | the pad itself; fix 10 makes it act on this game; not set since 2026-11-14 |
| #1847 | seedds | slice-merged passes and the GPU clock keeper: four players 21.0 → 26.8 fps |
| #2408 | Sennbon-99 | a sparse mapping starts a new texture ID epoch only when it is new: replay thread 8 % faster |
| #2328 | dean0396 | a pool buffer retired while a submission commits waits for that submission |
| #2348 | PromethOps | fullscreen on a fixed 60 Hz screen (a TV) whose presents keep turning a refresh late; not measured here (no TV connected) |
| `f9cbc09f` `a80ac555` `44255e5b` `291f9337` `44287f11` | upstream `main` after the base | two controller fixes (the controller screen reopening, a Pro Controller counted twice), a storage takeover fix, a texture layout fix, a movie texture fix |
| #1230, `shader_border_emu 0` and `shader_nan_coord cube` (`942b8e59`; the backport adds `cube`, tested and noted in `97312730`) | IshaanKalra2103 | the last change, with every shader built again: its author's M1 Pro got the samples' overlap back (the cube prefilter 2.2 → 0.7 ms a chain); on this M2 Pro the cube and cube-array filters took 3 to 9 % less in a Metal harness, and in play the GPU's time a frame within run-to-run noise (one player 13.38 → 13.28 and 13.71 ms, two 14.15 → 14.07, four 28.93 → 28.41; one run each, two with one player), no frame off its step with two and four players before or after, and no fault in the pictures. `cube` changes only the cube and cube-array guards, so `dmsh_fetch.fold` keeps the 2D ones' readable-tile versions |

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
| Console mode for a split screen (fullscreen on the built-in screen at a fixed 60 Hz, 2026-11-12) | two players 58.4 fps, three 29.6 and four 29.3 of the game's 30, with 95, 48 and 81 frames a minute a refresh late; the dynamic resolution at its floor. Hence fix 12 then; since 2026-11-14 fixes 13, 17 and 18 hold it (README.md) |
| Console mode's split screen made cheaper: graphics scale tier 1 (`DM_GFX_SCALE=1`), the pad at 1.40, `DM_UPSCALER=metalfx`, the array filter split up to 64x64 (`fs_split 765844f5609bb11b:4096`) | two players: 59.7 fps with tier 1 (18 uneven frames a minute), 59.0 with the wider split (GPU 14.27 for 14.55 ms; one player 0.1 ms); the pad and the upscaler changed nothing |
| The performance mode fixed apart from the operation mode (`exp/perfmode`) | nothing changed either way: the operation mode alone picks the picture |
| PR #2467, the frame standing in the display link's queue drained (`exp/drain`) | fullscreen: the picture is on screen 17 to 19 ms sooner (one player 65 → 48 ms from the game's present call, four players 95 → 77), and the late frames it covered show: four players 3 uneven frames a minute for 0, one player in console mode 2 for 1 |
| PR #2495, a frame workgroup, with the replay thread joined (`exp/fwg`) | four players: replay 18.3 for 19.7 ms a frame in one run each (2.5 % fewer draws in it), 30.0 fps and no late frame either way |
| PR #2526 of 2026-11-13, a submission's first segment committed after 8 draws (`DM_NVN_CUT_FIRST`, `exp/cutfirst`) | on and off on one host: two players in console mode, four in handheld mode, one in console mode: the same frame rates, GPU times and late frames |
| `DM_PRESENT_LINK=0` in fullscreen | the built-in screen stays in variable refresh; the picture is on screen 24 to 37 ms sooner (one player 41 for 65 ms, four players 59 for 95), no uneven frame in either run. Left out: no run could be made on a fixed 60 Hz TV, where the link is what the owner's own sessions held 60 fps with |
| The GPU clock keeper off or `auto` in fullscreen with Game Mode | the clock follows the load (1,199 MHz of 1,398 on average); the game draws about 3 % less (render targets 501 to 504 MB for 514 to 527) |
| Pad 1.35 with one player in console mode | a whole race each: 4 late frames for 6, 1 uneven for 3, render targets 504 MB for 526: nothing one run can show |
| The guest's memory in files (`DM_GUEST_FILE=1`, 2026-11-13) | a Grand Prix with one player and one with four: footprint 6,021 and 6,347 MiB at its highest for 12,142 and 12,001, no idle daemon ended by the kernel; but 311,073 and 333,848 major faults, a frame of 106 ms while driving with one player and two of 240 and 249 ms at the four-player award scene, 8.5 and 10.2 GB of logical writes in 20 minutes, and 10 GB of free disk needed at the start. Left off (KNOWLEDGE.md, section 0) |
| PR #2534 of 2026-11-12, texture pool tables hold a view of a texture read through another layered type (`exp/pr2534`) | a run each way: the same frame rate, GPU time and log lines, and the fly-over's pictures looked the same; no sign that this game reads cube maps by handle |
| Reading a batch's upload sources and a new pool's memory on several cores before the residency commit (ours, 2026-11-12) | the cut to the starting grid got longer, 196 against 139 ms: its sources are resident already (a residency commit costs the memory it wires, "Open" below) |
| `DM_NVN_CUT` left at 64 (2026-11-14, no stopgap, one host, the two values in turn) | four players, the cup's heaviest minute: frames off their step 10 and 38 with 64, 0 and 0 with 8; GPU time a frame 30.2 and 30.5 ms against 28.9 and 28.5; 1,795 and 1,781 frames of 1,800. Two players: 18 off their step and 17 frames missing with 64, none with 8 |
| Upload copies on worker threads (ours, `exp/upasync`, 2026-11-14, ABBA) | the cut frame's upload time fell (four players 100 → 70-75 ms) but not the frames: excess over the step at the four-player cut 115 / 105 / 101 / 99 ms (off, on, on, off), the one-player cut frame 78 / 98 / 98 / 83 ms |
| The commit's GPU state read from a shared event (ours, `exp/cutev`, `DM_NVN_CUT_EVENT`) | two, three and four players, in-run A/B: within run-to-run noise |
| PR #2441 (passes deferred and reordered, `DM_NVN_PASS_DEFER`), #2561 (texture clear waits, `DM_NVN_TEXCLEAR_WAIT`; counters, `DM_NVN_LC_COUNTERS`), #2560 (a dry cut, `DM_NVN_CUT_DRY`), #2577 (task and mesh pipelines declare a threadgroup size), 2026-11-13 to 14, a Reddit post's list for M1 and M2 | in-run A/B on one host with four, two and one players: no consistent effect. #2577's pipelines come from the archive, built without it, so no run here could show it. #2441 merges no pass group in this game and fails 4 checks of `t_reorder_chain` (its two stencil cases; all pass with `DM_NVN_PASS_DEFER=0`); this game makes no texture clear #2561 waits on; its counters save 1 to 4 passes a frame. Not applicable here: #2559 (an NVN upscaler this game does not use), #2574 (this game makes no occlusion queries), #2593 (no bindless texture pool tables) |
| Lossless compression for resolution families (PR #2573's idea, `DM_NVN_FAMILY_NOCOMPRESS=0`, 2026-11-14) | the game makes them; four players, ABBA: GPU 29.02 / 28.72 / 27.98 / 28.51 ms in the heaviest minute, no difference in the minutes before it; the risk is a member decoding another size's compressed blocks as garbage |
| PR #2379 (residency changes under a lock of their own) and one residency commit for a submission's new pools (ours, `DM_NVN_POOL_RES_DEFER`; 2026-11-13, the pad on in both arms) | commits 5 to 10 times fewer, their time and the cut frames the same: the time is the memory wired, not the count |
| PR #2491 (a submission's lag measured; 2026-11-13, the pad on in both arms) | two players: 60.0 fps and GPU time within noise either way |

## Open: the long frame at a scene cut

The first frame of the starting grid takes about 70 to 115 ms in the four Grands Prix of 2026-11-14 (the same at the cut to the results). A profile of that frame with one player (2026-11-14, Time Profiler, the final settings: 88 ms, 63 ms of it on the
replay thread, 727 textures and 148 MB first used): copying the textures' storage into the upload ring 17 ms, part of it macOS taking 4,665 of the game's pages back
out of its compressor; the copies from staging into the textures 14 ms (Apple's driver makes a temporary texture and a compute dispatch for each of about 5,000
levels); memory pools made resident the first time the GPU reaches them 11 ms (wiring them, which is their memory's time, not the count of commits); creating the
textures 10 ms, each its own allocation in the kernel; the edge copies the write tracking keeps 8 ms; the deswizzle dispatches 4 ms. Measured and left out against it:
upload copies on worker threads, PR #2379, one residency commit for a submission's new pools (above). What would remove the frame is making these textures before the
cut; the game keeps about 33,000 textures (900 MB) loaded that it never draws (a census of 2026-11-13), so uploading ahead by what is loaded costs that much memory, on
a Mac whose memory the game already fills (KNOWLEDGE.md, section 0). Two parts could shrink without that: textures cut from shared heaps instead of allocations of their
own (about 10 ms), and hashes in place of the edge copies (about 5 ms, and their memory).

## Open: split screen on the heavier courses

On the courses no earlier test used, console mode reaches this GPU's limit in places (2026-11-14, a whole Grand Prix each on the final host before PR #1230, one run
each). Two players, Star Cup: 231 frames stayed on screen a refresh longer than their step in 18 minutes, 176 of them while driving, 160 in three minutes of one race
(70, 47 and 43). In the worst of those minutes the GPU took 15.1 ms a frame at the median and 16.3 ms at the 90th percentile of the 16.7 it has, against 13.9 and 14.7
in a quiet minute, with 10 % more render passes (216 against 197); the replay thread was not the limit (11.2 ms of wall time a frame, the same as in the quiet
minute), and the game's thread waited on the GPU (SyncWait 7.3 ms a frame against 0.9). Four players, Banana Cup: 101 longer frames, 55 of them while driving,
46 in one minute and 35 in another; there the GPU took 30.6 and 29.9 ms of the 33.3 and the replay thread 27.7 and 23.3 ms (90th percentile 35.6 and 29.4), with 16 %
more draws than a quiet minute (10,550 against 9,100). Three players, Shell Cup: 5 while driving. On the final host (after PR #1230) the two Grands Prix with the heavier minutes again, one run each: two players, Star Cup: 199 longer (46 beside a cut, 153 while driving) against 231, the worst minute the same one (780-840 s: 111 against 70; GPU 15.46 ms a frame at the median against 15.12), no pipeline compiled, the footprint at its highest 11,056 MiB; four players, Banana Cup, with the wait ledger (`DM_NVN_WAITS=1`): 50 longer (27 beside a cut, 23 while driving) against 101, the worst minutes the same two (29 and 14 against 35 and 46), 5 pipelines compiled in play with no frame off its step at them, the footprint at its highest 12,083 MiB. In the four-player run's heaviest ten seconds the game's thread waited on the GPU's newest fence 7.6 to 12.0 ms a frame (a quiet minute: 0.4 to 3.8), and the replay thread waited for the encode thread 43 times a frame, every one blocked, about 2 ms a frame in heavy and quiet minutes alike. So the heavy minutes are the GPU's with four players as with two; the encode wait is a fixed 2 ms of every four-player frame.
Short of a smaller picture, the time has to come out of the host's own work. What is left to gain:
every render pass costs about 30 µs of GPU time on this Mac whatever its size (a 2026-11-13 harness: an empty pass 30 µs), and a two-player frame has about 200 of
them; four players' frames have about 80 compute encoders of about 45 µs each; the replay thread waits for the encode thread at each of a frame's submissions (four
players: 43 waits a frame, every one blocked, about 2 ms) and spent 12.6 % of its time in Objective-C retain and release (a profile of 2026-11-12). Each is a structural change to how the
host builds a frame's passes or hands work to the encode thread.

## Not tried

| Change | Why |
|---|---|
| Upstream `224ecb18` and PR #2198, #2199 | each changes the shader chain, for no fault seen in this game; PR #1230's rebuild was the one chain change taken |
| PR #2413, task and mesh shaders as compute (`DM_NVN_MESH_COMPUTE=1`) | 528 lines, opt-in, a start-up flicker known to its author; this game has 12 task and mesh pipelines (bushes and grass) |
| PR #2374, #2344, #2329, #2330, #2412 | real fixes whose fault no run of this game showed |
| PR #2525 (image-heap aliases flushed less often), PR #2530 (frame generation), PR #2536 (the visibility ring grows on demand) | #2525 acts under `DM_NVN_BARRIER=game` only and keeps the flush for large chunked pools, which this game's are; #2530 is for a game at 20 fps; #2536 mends a phone that ran out of counter buffers ("a Mac never ran dry of the ring", its author) |
| Fewer render passes (about 30 µs of GPU time a pass on this Mac whatever its size; about 200 passes a two-player frame) | the lever for the two-player stretches above, if passes can be merged at all: PR #2441's pass deferral found no group to merge in this game, so which passes could share one is the first question |
| The replay thread's wait for the encode thread at each submission's end (about 2 ms a frame with four players: 43 waits, every one of them blocked, `DM_NVN_WAITS=1`) | a change to the order in which the replay and the encode thread commit; the first lever for the four-player stretches above |
| Unretained locals in the replay's hot paths (12.6 % of the replay thread was Objective-C retain and release in a profile of 2026-11-12) | code changes in the hottest paths; to measure on `gp150-4p-banana` |
| Fewer compute encoders (four players: 79 dispatch encoders a frame, about 45 µs of GPU time each, in runs of 9) | each needs the barriers between its dispatches proven |
| Textures cut from shared heaps, hashes for the write tracking's edges | the two parts of a scene cut's frame above that do not depend on memory |

The first triage of 2026-11-11 (before the game ran here) and the earlier combined branches are in this file's history and in `old/…`.
