# Mario Kart World on an M2 Pro (16-core GPU, 16 GB)

Goal: update 1.8.0 (v917504) at a steady 60 fps with full-quality textures, no shader stutter, no picture faults, then 4 players on one Mac
(30 fps is acceptable there if that is what the console does). Memory: up to about 10 GB is fine; nothing is scaled down to save memory.

State (2026-11-11): everything is built and checked as far as it can be without the game. The game has not run on this Mac: the dump lacks
`exefs/main.npdm` and about 25,000 RomFS files.

## Read these

- [KNOWLEDGE.md](KNOWLEDGE.md): how the port works, what is known about this game, the levers, the tools, the traps, the open questions. Each line names its source.
- [TRIAGE.md](TRIAGE.md): every change considered, which three are in and why the others wait.

## Branches

| Branch | What | Use |
|---|---|---|
| `main` | upstream nxnative as fetched | never edited |
| `mkw-fixes` | upstream `352e4a6e` + the three fixes of TRIAGE.md + this folder + a benchmark route | **the branch to build and play from** |
| `mkw-test` | `mkw-fixes` + scripted controllers for players 2 to 8 | measuring multiplayer without controllers |
| `old/mkw-m2pro`, `old/mkw-m2pro-perf`, `old/mkw-m2pro-perf2` | the first combined branches (upstream `084f5aa5`, 14 changes) | reference only |
| `pr/<n>` | upstream pull request heads | merged into variants by `mkw/test/host.py` |

Candidates are not branches: `mkw/test/host.py <label> pr/<n>` builds a host with one of them on top of `mkw-fixes`, in its own worktree, when a measurement needs it.

## When the dump is complete

1. `mkw/test/preflight.sh` says "Ready to build."
2. `mkw/test/pack.sh` (the long step: extraction, 11,604 shaders, the pipeline prebuild). It ends with the command that runs the game.
3. Run that command once by hand with `mkw/test/watchdog.sh &` beside it. Go to the main menu, quit. This makes the save every scripted run starts from,
   and answers KNOWLEDGE.md's first open question (does it boot, how much memory).
4. `mkw/test/host.py upstream --base origin/main`, then
   `mkw/test/bench.sh --variant 'fixes:' --variant 'upstream:host=<printed path>'`: the baseline, and the first proof or disproof of the frame-step fix.
   Look at the screenshots first: if they are not the race, move the route's window (`dm/games/0400C3F00006E000/bench.tsv`).
5. One candidate at a time, each against `fixes` in one invocation: `c1179`, `c1437` (with `DM_NVN_GPU_TS_PAD=1.2`), `c1847`, `c1970`; settings the same way
   (`--variant 'a:' --variant 'b:DM_FPS_HOLD=off'`, fullscreen, `DM_NVN_ENC_THREAD=1`).
6. A GPU profile of a race frame (`DM_NVN_GPUPROF=every:300`, `dm/tools/gpuprof.py`): which passes cost what on this GPU. Then the shader remedies for the
   reflection filters, each a chain change, each measured on the passes it targets.
7. Stutter: count the frames that wait for a pipeline in a first race (`pipelines up to frame`, `DM_PSO_WAITLOG=1`) with upstream's list, PR #2097's and the
   merged one (`host.py --list`); then this Mac's own `pso_user.tsv` after a Grand Prix.
8. Four players: `swift mkw/pads.swift` with each kind of controller; a scripted 4-player race with `mkw-test` (the route is written by looking at the menus
   once); the game's frame mode from the frame-step log; then frame times.

## Files here

`test/` preflight, pack, host, bench, watchdog, logsum, ctl_feed, host_with_ctl (see KNOWLEDGE.md section 9) · `verify_dump.py` · `env-m2pro-16gb.txt`
(`DM_OPMODE=0`, `DM_PRESENT_UPSCALE=metalfx`) and `env-low-memory.txt` · `build.sh` (the double-clickable app, once the measurements have chosen its
settings) · `pads.swift` · `resolve_pr.py`, `resolve_pr1847.py`, `resolve_neo.py` (merge resolutions as code) · `merge_pso_lists.py` and
`pso/pso_manifest_merged_180.tsv` · `checks/` (the first frame-step simulations; superseded by the cases in `dm/gfx/tests/t_fstep.c`).
