# Mario Kart World on an M2 Pro (16-core GPU, 16 GB)

Goal: update 1.8.0 (v917504) at a steady 60 fps with full-quality textures, no shader stutter, no picture faults, then 4 players on one Mac
(30 fps is acceptable there if that is what the console does). Memory: up to about 10 GB is fine; nothing is scaled down to save memory.

State (2026-11-13): the game runs as a Mac app, `<dump>/Mario Kart World.app`, packed from the branch `mkw-fin`. One player plays in console (docked) mode; when a
second player joins at the game's controller screen the app changes to handheld mode (`DM_OPMODE_MULTI=0`). The app is marked for Game Mode, which macOS turns on
in fullscreen. Measured on this Mac with the host the app carries and its settings (150cc, the first race of the Mushroom Cup, fullscreen on the built-in screen,
which the host sets to a fixed 60 Hz, Game Mode on, sound off, players 2 to 4 scripted, one run each):

| Players | Mode | Frame rate | Frames on screen off their step, racing | The 20 s from the starting grid | GPU time a frame |
|---|---|---|---|---|---|
| 1 | console, 2560x1440 | 60 fps | none in 2,100 (a race's first 35 s) | in the 2,100 | 11.5 ms of 16.7 |
| 2 | handheld, 1920x1080 | 60 fps | none in 3,600 | 4 of 1,196 | 12.4 ms of 16.7 |
| 3 | handheld | 30 fps, the game's own mode | none in 1,800 | none of 601 | 25.4 ms of 33.3 |
| 4 | handheld | 30 fps, the game's own mode | none in 1,800 | 3 of 597 | 25.7 ms of 33.3 |

In console mode a split screen does not hold on this GPU: two players 58.4 fps, three 29.6, four 29.3, with 48 to 95 uneven frames a minute.

One frame is long at each scene cut: 80 to 161 ms with one player in console mode (as long in handheld mode), 117 to 170 ms in split screen (TRIAGE.md, "Open").

A whole Grand Prix (one player in console mode, 150cc, the Mushroom Cup's four races, the award and the start of the next one: 18 minutes of the route
`gp-full-150`, which only holds A): 59.94 fps, 44 frames on screen longer than their step in 64,731 and 24 never shown, 40 of the 44 beside a texture upload or a cut
frame (11 in 1.2 s at one scene change, 16 minutes in), no pipeline compiled on any of the four tracks, footprint 7.7 GB at the start and 11.9 GB at its highest, 40 MB
read back from swap. The same in handheld mode: 39 and 22, in the same places, footprint 11.1 GB at its highest, nothing from swap.

The same with four players (`gp150-4p-full`, handheld mode after the change, Game Mode on throughout): 30 fps, 27 frames on screen longer than their step in 26,212
racing frames and 6 never shown, no minute with more than 7, no pipeline compiled, nothing from swap, footprint 11.4 GB at its highest. A second run, on the app's own host: 42 and 6, the worst minute 16, one pipeline compiled.

Two or three frames in each one-player Grand Prix above were held 0.07 to 0.2 s inside a present call. That was the bench's own per-frame log, written on the
presenting thread, waiting while macOS started services again after ending idle ones for memory (the game holds 11 to 12 GiB of the Mac's 16 by then;
KNOWLEDGE.md, section 0). The packed app writes no such log. The same Grand Prix twice without that log (`MKW_NO_TSV=1`, the long frames read from the host's own lines): 5 of 6 such moments
passed with no frame over 32 ms, at the sixth one frame took 165 ms on a results screen; the other frames of 60 ms or more (9 and 8 in 18 minutes) lie at
scene cuts and scene changes. The game's memory in files (`DM_GUEST_FILE=1`) was tried and left off: 6 GiB of footprint for 12 and no daemon ended, but frames
of 0.1 to 0.25 s where pages were read back, 8.5 to 10 GB written in 20 minutes and 10 GB of free disk needed at the start.

The runs of 2026-11-12, in a window in handheld mode, are in TRIAGE.md and KNOWLEDGE.md: one player 60 fps with 1 late frame in a whole race, two 60 fps, three
and four 30 fps with none in a minute.

Sound: every run had it off or silenced. With the real output path running and its samples zeroed (`DM_AUDIO=1 DM_AUDIO_MUTE=1`, 2026-11-12): one player 60 fps
with no late frame in 2,100, four players 0 and 5 late frames in a minute against 0 and 1 without it (two runs each), no underrun in any run.

The host is built with the profile of its own runs (`mkw/pgo/README.md`): with four players the replay thread takes 7 to 11 % less time a draw, and a
whole Grand Prix had 24 late frames in place of 71.

Not tested: a TV, real controllers, sound as heard, the other cups and modes. The full account, with a chart of what each step did, is the build report (a document
outside the repository, written for the owner of this Mac on 2026-11-12 and 13).

## Read these

- [TRIAGE.md](TRIAGE.md): what the branch holds (12 fixes of ours, 14 upstream pull requests, 5 later upstream commits) and what was measured and left out.
- [KNOWLEDGE.md](KNOWLEDGE.md): how the port works, what is known about this game, the levers, the tools, the traps. Section 0 holds what this Mac measured;
  the sections after it were written from sources before the game ran here and are corrected where a run contradicted them.
- [../dm/games/0400C3F00006E000/README.md](../dm/games/0400C3F00006E000/README.md), "Frame rate": each fix with its measurement.
- [pso/README.md](pso/README.md): the warm-up list (15,062 rows merged from 10 lists) and how it was merged.

## Branches

| Branch | What | Use |
|---|---|---|
| `main` | upstream nxnative as fetched | never edited |
| `mkw-fin` | upstream `352e4a6e` + everything in TRIAGE.md's "In" | **the branch the app is packed from** (worktree `../mkw-worktrees/fin`) |
| `mkw-next`, `mkw-fixes` | earlier stages of the same line | reference only |
| `pr/<n>` | upstream pull request heads | merged into variants by `mkw/test/host.py` |
| `old/…` | the first combined branches | reference only |

A candidate is not a branch: `mkw/test/host.py <label> --base <ref> [pr/<n> …]` builds a host of any revision in its own worktree, against the packed game's
profile, into `<build>/variants/<label>/dmhost` (about 40 s), and `mkw/test/bench.sh --variant …` compares variants on a scripted route.

## Building the app again

From the worktree of `mkw-fin`, about 13 minutes when the shader libraries are cached:

    ~/nup/.venv/bin/python3 scripts/build_ipa_from_nsp.py <dump> --platform mac-app --allow-other-metal --progress lines --env-file "$PWD/mkw/env-m2pro-16gb.txt"

`GAME=<dump> mkw/build.sh` runs the same after checking the dump. The app lands beside the dump. Its first start waits about three minutes before anything shows: macOS scans the 24 GB bundle once. The app keeps its saves, its
pipeline archive and its own warm-up list in `~/Library/Application Support/nxnative/0400C3F00006E000/`, its log in `~/Library/Logs/nxnative/`. A file `env.txt`
in the first folder overrides the settings the app was packed with.

## Settings the app is packed with (`env-m2pro-16gb.txt`; each line carries its reason)

`DM_OPMODE=1` (console mode: the game draws for 2560x1440) · `DM_OPMODE_MULTI=0` (handheld mode, 1080p, from two players on) · `DM_PRESENT_UPSCALE=metalfx` · `DM_FPS_HOLD=off` (a late frame does not lengthen the ones after it) ·
`DM_NVN_GPU_TS_PAD=1.25` (the game lowers its render size a little before it would drop frames) · `DM_GPU_KEEP=1` (the GPU's clock stays at its top). In the
profile: `pso_whole on`, `fs_split` for the two reflection filters, `enc_thread on`, `mac_game_mode on`. Fullscreen is not among them: it is the player's choice in the
settings window (Display mode), saved on this Mac as `defaults write org.nxnative.0400c3f00006e000 launcher.DM_FULLSCREEN -string 1`; Game Mode needs it.

## Files here

`test/` preflight, pack, host, bench, watchdog, logsum, ctl_feed, host_with_ctl, routes for players 2 to 4, runs started as apps for fullscreen and Game Mode (`fx.sh`,
`host_open.py`, `mkbundle.sh`, `gmprobe.sh`; readers `fxsum.py`, `odd.py`, `lates.py`, for a whole Grand Prix `soaksum.py` and `longlog.py`; `gpufreq.m`, the GPU's
clock by the second), and the readers of a run (`runsum.py`, `buckets.py`,
`vmsum.py`, `instr.py`, `subprof_sum.py`, `sample_*.py`; KNOWLEDGE.md, section 9) · `verify_dump.py` · `build.sh` · `check_frame_fn.py` (is the frame-interval
function's fingerprint in this build's `main`) · `bahs_probe.py` (what the shader split reads in a shader package) · `sets.tsv` and `assemble.py` (the merged pull
request sets as data) ·
`env-m2pro-16gb.txt` and `env-low-memory.txt` · `pads.swift` · `resolve_pr.py`, `resolve_pr1847.py`, `resolve_neo.py` (merge resolutions as code) ·
`merge_pso_lists.py` and `pso/` · `pgo/` (the profile the host is built with, and what it gave) · `checks/` (the first frame-step simulations; superseded by `dm/gfx/tests/t_fstep.c`).
