# Mario Kart World on an M2 Pro (16-core GPU, 16 GB)

Goal: update 1.8.0 (v917504) at a steady 60 fps with full-quality textures, no shader stutter, no picture faults, then 4 players on one Mac
(30 fps is acceptable there if that is what the console does). Memory: up to about 10 GB is fine; nothing is scaled down to save memory.

State (2026-11-12): the game runs as a Mac app, `<dump>/Mario Kart World.app`, packed from the branch `mkw-fin`. Measured on this Mac with the host the app
carries (150cc, the first race of the Mushroom Cup, a window on the built-in screen, sound off, players 2 to 4 scripted, one run each):

| Players | Frame rate | Late frames while racing | The race's first 20 s | GPU time a frame |
|---|---|---|---|---|
| 1 | 60 fps | none in a whole race (10,800 frames) | none | 10.9 ms of 16.7 |
| 2 | 60 fps | none in 3,600 frames | 4 of 1,200 | 12.4 ms of 16.7 |
| 3 | 30 fps, the game's own mode | 1 in 1,800 frames | 4 of 600 | 25.4 ms of 33.3 |
| 4 | 30 fps, the game's own mode | 1 in a whole race (4,950 frames) | 2 of 600 | 25.2 ms of 33.3 |

One frame is long at each scene cut: the first frame of the starting grid takes 45 ms with one player and 117 to 170 ms in split screen (TRIAGE.md, "Open").
The app on this Mac was packed from `86d089e9`; the commits after it change notes and test tools only.

Not tested: a TV, real controllers, sound on, other tracks and modes. The full account, with a chart of what each step did, is the build report (a document
outside the repository, written for the owner of this Mac on 2026-11-12).

## Read these

- [TRIAGE.md](TRIAGE.md): what the branch holds (11 fixes of ours, 14 upstream pull requests, 5 later upstream commits) and what was measured and left out.
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

`DM_OPMODE=0` (handheld: the game draws 1080p) · `DM_PRESENT_UPSCALE=metalfx` · `DM_FPS_HOLD=off` (a late frame does not lengthen the ones after it) ·
`DM_NVN_GPU_TS_PAD=1.25` (the game lowers its render size a little before it would drop frames) · `DM_GPU_KEEP=1` (the GPU's clock stays at its top). In the
profile: `pso_whole on`, `fs_split` for the two reflection filters, `enc_thread on`.

## Files here

`test/` preflight, pack, host, bench, watchdog, logsum, ctl_feed, host_with_ctl, routes for players 2 to 4, and the readers of a run (`runsum.py`, `buckets.py`,
`vmsum.py`, `instr.py`, `subprof_sum.py`, `sample_*.py`; KNOWLEDGE.md, section 9) · `verify_dump.py` · `build.sh` · `check_frame_fn.py` (is the frame-interval
function's fingerprint in this build's `main`) · `bahs_probe.py` (what the shader split reads in a shader package) · `sets.tsv` and `assemble.py` (the merged pull
request sets as data) ·
`env-m2pro-16gb.txt` and `env-low-memory.txt` · `pads.swift` · `resolve_pr.py`, `resolve_pr1847.py`, `resolve_neo.py` (merge resolutions as code) ·
`merge_pso_lists.py` and `pso/` · `checks/` (the first frame-step simulations; superseded by `dm/gfx/tests/t_fstep.c`).
