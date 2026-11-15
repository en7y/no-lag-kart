# Mario Kart World on an M2 Pro (16-core GPU, 16 GB)

Goal: update 1.8.0 (v917504) at a steady 60 fps with full-quality textures, no shader stutter, no picture faults, then 4 players on one Mac
(30 fps is acceptable there if that is what the console does). Memory: up to about 10 GB is fine; nothing is scaled down to save memory.

State (2026-11-14): the game runs as a Mac app, `<dump>/Mario Kart World.app`, packed from `mkw-fin3` at `37b46ec3` (the commit after it adds only these
notes). One to four players play in console (docked) mode, and no setting lowers what the game draws: the two stopgaps of 2026-11-13 (handheld mode from two
players on, `DM_OPMODE_MULTI=0`, and the GPU-time pad `DM_NVN_GPU_TS_PAD=1.25`) are gone, and every run below was checked for their log lines. The app is marked
for Game Mode, which macOS turns on in fullscreen. Measured on this Mac (150cc, fullscreen on the built-in screen, which the host sets to a fixed 60 Hz, Game Mode
on, sound off, players 2 to 4 scripted, one run each, two with one player):

| Players | Window | Before: `mkw-fin`'s host, its settings minus the two stopgaps (2026-11-13) | The app (2026-11-14) |
|---|---|---|---|
| 1 | 100–135 s, the end of the countdown and the race's first 30 s | 12 frames off their step of 2,092, GPU 13.64 ms a frame (median) | none of 2,100 in one run; in another 1 off its step and 1 never shown, both at 121 s; GPU 13.28 and 13.71 ms |
| 2 | 120–180 s of the first race | 56.1 fps, 234 off their step, GPU 15.24 ms | 60.0 fps, none of 3,600, GPU 14.07 ms |
| 3 | 120–180 s of the first race | 28.2 fps, 220 off their step, GPU 31.59 ms | 30.0 fps, none of 1,799, GPU 28.35 ms |
| 4 | 330–390 s, the road to the second course (the cup's heaviest minute) | 27.5 fps, 300 off their step, GPU 31.44 ms | 30.0 fps, none of 1,800, GPU 28.41 ms |

A frame "off its step" stayed on screen more than 4 ms longer or shorter than the game's step: what a player can see. Before, the frames came late because the
GPU started on each frame only after the host had copied the whole of it, and split screen was more than console mode then held.

What made console mode hold a split screen: the streamed submission (`8e7483df`: the GPU starts on a frame 0.9 ms after the game submits it), segments of 8
draws while the GPU waits (`DM_NVN_CUT=8`), the upload ring (`1ec15ff8`) and the reflection filters' face-layered pass (`55fcb2cd`) with the cube array filter
split up to 64x64. The per-draw feedback checks (`e423e749`: the replay thread 0.5 to 0.8 ms a frame less with four players), the host's profile recorded again
on this code and PR #1230 came after. TRIAGE.md has each with its measurement.

A whole Grand Prix per player count, on cups and with characters no earlier run used (2026-11-14, the host one commit before PR #1230 with these
settings, 18 minutes from the first race's start through the award, one run each; frames on screen a refresh longer than their step, `soaksum.py`):

| Players | Cup | While driving | Beside a scene cut | Worst minute | Never shown | Pipelines compiled | Footprint at its highest |
|---|---|---|---|---|---|---|---|
| 1 | Flower | 9 | 42 | 17 | 25 | 0 | 11,661 MiB |
| 2 | Star | 176 | 55 | 70 | 7 | 2 | 11,654 MiB |
| 3 | Shell | 5 | 32 | 13 | 4 | 0 | 12,788 MiB |
| 4 | Banana | 55 | 46 | 46 | 3 | 2 | 11,652 MiB |

With two players on the Star Cup and four on the Banana Cup, a few minutes of heavier courses bring frames a refresh late, up to about two a second: there the
GPU, and with four players the replay thread too, needs all of a frame's time in console mode (TRIAGE.md, "Open"). On the final host (after PR #1230) the two Grands Prix with the heavier minutes again, one run each: two players, Star Cup: 199 longer (46 beside a cut, 153 while driving) against 231, the worst minute the same one (780-840 s: 111 against 70; GPU 15.46 ms a frame at the median against 15.12), no pipeline compiled, the footprint at its highest 11,056 MiB; four players, Banana Cup, with the wait ledger (`DM_NVN_WAITS=1`): 50 longer (27 beside a cut, 23 while driving) against 101, the worst minutes the same two (29 and 14 against 35 and 46), 5 pipelines compiled in play with no frame off its step at them, the footprint at its highest 12,083 MiB. In the four-player run's heaviest ten seconds the game's thread waited on the GPU's newest fence 7.6 to 12.0 ms a frame (a quiet minute: 0.4 to 3.8), and the replay thread waited for the encode thread 43 times a frame, every one blocked, about 2 ms a frame in heavy and quiet minutes alike.

Memory in those four Grands Prix (`DM_MEMSTAT`): the footprint at its highest is in the table, 12,788 MiB with three players the most of any run here
(12.1 GiB before, the one-hour run of 2026-11-13); macOS held up to 4,717, 4,116, 5,160 and 4,618 MiB of it compressed (one to four players) and read nothing back from swap. At the three-player
peak: the game's own memory 5,608 MiB (1,916 of it resident, the rest compressed), the GPU's (macOS's graphics ledger) 5,476, the host's heap 979, the rest 725.
Metal's own count of what the host allocated (up to 12,929 MiB, one player) counts the buffers that wrap the game's memory too and is not on top of the footprint.
KNOWLEDGE.md, section 0, has the measures.

One frame is long at each scene cut: about 70 to 115 ms in those four Grands Prix, the frame in which several hundred textures are shown for the first time (727 textures, 148 MB at the cut to the
starting grid with one player). Where that frame's time goes, and why it stays: TRIAGE.md, "Open".

Frames held 0.07 to 0.2 s inside a present call in a long run with the bench's per-frame log are the log's own writes, on the presenting thread, while macOS
restarted services it had ended for memory (KNOWLEDGE.md, section 0); the packed app writes no such log. The game's memory in files (`DM_GUEST_FILE=1`) was tried
and left off (TRIAGE.md).

Sound: every run had it off or silenced. With the real output path running and its samples zeroed (`DM_AUDIO=1 DM_AUDIO_MUTE=1`, 2026-11-12): one player 60 fps
with no late frame in 2,100, four players 0 and 5 late frames in a minute against 0 and 1 without it (two runs each), no underrun in any run.

The host is built with the profile of its own runs (`mkw/pgo/README.md`), recorded again on 2026-11-14 on this branch's code. Four players, the heaviest minute, one run each: the replay's CPU 24.58 → 24.44 ms a frame, no measurable difference; kept because it matches the code.

PR #1230 (`shader_border_emu 0`, `shader_nan_coord cube`) is the last change: every shader was built again for it. It took 7 min 35 s to build the 11,601 shaders, the offline pipeline archive (470 MB) holds the same 9,591 bases and 728 compute pipelines as before, and the
app's first start after it compiled the 7,283 changed whole pipelines in 64 s before its first frame; the second start's check took 0.9 s and compiled 14 of them
again. In play, against the host one commit before it (same
windows, one run each): GPU time a frame 13.38 → 13.28 ms with one player (a second run: 13.71), 14.15 → 14.07 with two, 28.93 → 28.41 with four: within run-to-run
noise; no frame off its step with two and four players before or after. The pictures of those runs show no fault.

Not tested: a TV, real controllers, sound as heard, free roam and the other modes. The full account is the build report (a document outside the repository,
written for the owner of this Mac on 2026-11-12 to 14).

## Read these

- [TRIAGE.md](TRIAGE.md): what the branch holds (23 fixes of ours, 15 upstream pull requests, 5 later upstream commits) and what was measured and left out.
- [KNOWLEDGE.md](KNOWLEDGE.md): how the port works, what is known about this game, the levers, the tools, the traps. Section 0 holds what this Mac measured;
  the sections after it were written from sources before the game ran here and are corrected where a run contradicted them.
- [../dm/games/0400C3F00006E000/README.md](../dm/games/0400C3F00006E000/README.md), "Frame rate": each fix with its measurement.
- [pso/README.md](pso/README.md): the warm-up list (15,062 rows merged from 10 lists) and how it was merged.

## Branches

| Branch | What | Use |
|---|---|---|
| `main` | upstream nxnative as fetched | never edited |
| `mkw-fin3` | `mkw-fin2` + the per-draw feedback checks, a test fix, the settings without stopgaps, the bench's stop by process ID, the profile recorded again, the game note without the stopgaps, PR #1230 with a test of its `cube` value, these notes | **the branch the app is packed from** (worktree `../mkw-worktrees/fin3`) |
| `mkw-fin2` | `mkw-fin` + the streamed submission, the upload ring, the face-layered filter pass and four smaller commits (TRIAGE.md) | reference |
| `mkw-fin` | upstream `352e4a6e` + TRIAGE.md's first "In" list | the app of 2026-11-13 (worktree `../mkw-worktrees/fin`) |
| `mkw-next`, `mkw-fixes` | earlier stages of the same line | reference only |
| `exp/…` | experiments, measured and left out (TRIAGE.md) | reference only |
| `pr/<n>` | upstream pull request heads | merged into variants by `mkw/test/host.py` |
| `old/…` | the first combined branches | reference only |

A candidate is not a branch: `mkw/test/host.py <label> --base <ref> [pr/<n> …]` builds a host of any revision in its own worktree, against the packed game's
profile, into `<build>/variants/<label>/dmhost` (about 40 s), and `mkw/test/bench.sh --variant …` compares variants on a scripted route; `mkw/test/fx.sh` starts
each run as macOS starts an app, for fullscreen and Game Mode.

## Building the app again

From the worktree of `mkw-fin3`, with the dump spelled as the build folder's stamps hold it (`NxNative`; another spelling or a clone of the folder makes the
builder pack the 22 GB RomFS image again):

    ~/nup/.venv/bin/python3 scripts/build_ipa_from_nsp.py ~/Games/Switch/NxNative/MarioKartWorld --platform mac-app --progress lines

`GAME=<dump> mkw/build.sh` runs the same after checking the dump. A pack in which every shader changed took 18 minutes on 2026-11-14 (the shader split 3:41, the Mac shaders 7:35, the offline pipeline archive 2:30, the app and its
signature 2:13). The app lands beside the dump. Its first start waits about three minutes before
anything shows: macOS scans the 24 GB bundle once. The app keeps its saves, its pipeline archive and its own warm-up list in
`~/Library/Application Support/nxnative/0400C3F00006E000/`, its log in `~/Library/Logs/nxnative/`. A file `env.txt` in the first folder overrides the settings window and the
profile's defaults. After a repack, `touch` the bundle folder: macOS's Game Mode daemon keeps its verdict on a bundle path until the folder changes.

## Settings the app runs with

Since 2026-11-15 these are the game profile's defaults (`dm/games/0400C3F00006E000/game.tsv`, each key with its reason), so a build needs no env file: the settings
window shows them, Reset to tested defaults goes back to them, and the matching `DM_` variable still overrides each. `mkw/env-tested.txt` holds the same values for
the bench. Until then they were an env file baked into the app (`env-m2pro-16gb.txt`), which the settings window showed greyed out.

`DM_OPMODE=1` (console mode: the game draws for 2560x1440, with one to four players) · `DM_PRESENT_UPSCALE=metalfx` · `DM_FPS_HOLD=off` (a late frame does not
lengthen the ones after it) · `DM_GPU_KEEP=1` (the GPU's clock stays at its top) · `DM_NVN_CUT=8` (a submission goes to the GPU in segments of 8 draws while the GPU
waits) · `DM_NVN_UP_COPY=128` (upload sources copied into a 128 MB resident ring). In the profile: `pso_whole on`, `fs_split` for the two reflection filters (the cube
array filter up to 64x64), `enc_thread on`, `mac_game_mode on`, and PR #1230's `shader_border_emu 0` and `shader_nan_coord cube`. Fullscreen (`fullscreen on`, the settings window's Display
mode) since 2026-11-15 as well: every run was measured in fullscreen, and Game Mode needs it. The profile keys: `op_mode console` (the default), `present_upscale metalfx`,
`fps_hold off`, `gpu_keep full`, `nvn_cut 8`, `up_copy 128`, `fullscreen on`.

## Files here

`test/` preflight, pack, host, bench, watchdog, logsum, ctl_feed, host_with_ctl, routes for players 2 to 4, runs started as apps for fullscreen and Game Mode (`fx.sh`,
`host_open.py`, `mkbundle.sh`, `gmprobe.sh`; readers `fxsum.py`, `odd.py`, `lates.py`, for a whole Grand Prix `soaksum.py`, `longlog.py` and, for its `DM_MEMSTAT` log, `mempeak.py`; `gpufreq.m`, the GPU's
clock by the second), and the readers of a run (`runsum.py`, `buckets.py`,
`vmsum.py`, `instr.py`, `subprof_sum.py`, `sample_*.py`; KNOWLEDGE.md, section 9) · `verify_dump.py` · `build.sh` · `check_frame_fn.py` (is the frame-interval
function's fingerprint in this build's `main`) · `bahs_probe.py` (what the shader split reads in a shader package) · `sets.tsv` and `assemble.py` (the merged pull
request sets as data) ·
`env-tested.txt` and `env-low-memory.txt` · `pads.swift` · `resolve_pr.py`, `resolve_pr1847.py`, `resolve_neo.py` (merge resolutions as code) ·
`merge_pso_lists.py` and `pso/` · `pgo/` (the profile the host is built with, and what it gave) · `checks/` (the first frame-step simulations; superseded by `dm/gfx/tests/t_fstep.c`).
