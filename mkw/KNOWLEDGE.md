# Mario Kart World natively on the Mac: what we know

Sections 1 to 11 were read in sources on 2026-11-11, before the game ran on this Mac, and each line says which source. Section 0 holds what this Mac
measured on 2026-11-11 and 12; where a run contradicted a later line, the line is corrected and says so.
Sources: **[code]** nxnative's source at upstream `352e4a6e` (2026-11-11); **[note]** upstream's game note `dm/games/0400C3F00006E000/README.md`;
**[doc]** upstream's `docs/`; **[PR n]** / **[issue n]** of seedds/nxnative; **[sim]** run by us with the host's own code, no game; a repository name for other projects.
When a first run contradicts a line, the run wins: correct the line and say what was measured.

## 0. What this Mac measured (2026-11-11 and 12: 16 GB M2 Pro, macOS 26.7.1, update 1.8.0)

The answers to section 11's questions, in its order, then what the work taught beyond them. The figures with their runs: [TRIAGE.md](TRIAGE.md), the game
note's "Frame rate" (`dm/games/0400C3F00006E000/README.md`) and `docs/reference/frame-rate.md`.

1. 1.8.0 boots to the title and races. At the end of a race the host holds 10.0 to 10.2 GB resident (GPU allocated 8.8 to 9.0 GB); macOS keeps 3.6 to 4.7 GB of
   the Mac's memory compressed and reads nothing back from swap. Over a whole Grand Prix (18 minutes) resident memory rises to 11.2 GB and the compressed part to
   5.6 GB, still with nothing from swap; longer sessions were not run.
2. The base game's routes do not fit 1.8.0. The routes in `bench.tsv` are 1.8.0's own: the title takes A from about 20 s, the first race's starting grid
   appears at about 97 s with one player and 100 s in split screen, and a 150cc race driven by holding A lasts 3 min 15 s. Holding A also carries a Grand Prix on: the half second between two holds is the press that leaves a
   results screen (`gp-full-150`: four races, the award, the next Grand Prix's start).
3. The baseline (upstream with the merged warm-up list), 50cc race: 59.1 to 59.3 fps, 47 to 53 late frames a minute, GPU 14.2 ms a frame. With everything in
   `mkw-fin`, 150cc: 60.0 fps, no late frame in a whole race, GPU 10.9 ms.
4. Game time is 1.000 of real time, with `fps_step_max 2` and with the frame step found on 1.8.0 (its frame-interval function moved: a second fingerprint).
   In the game's own 30 fps mode the frame-step log line reads 2.000 of real time: the line counts the game's step twice there. The race lasts the same
   3 min 15 s as with one player.
5. The game lowers its resolution by the GPU time it measures, and on the Mac that left it no margin for the host's own work: in split screen it kept its size
   and dropped frames. `DM_NVN_GPU_TS_PAD=1.25` gives it the margin, once the pad counts from the frame's first submission: this game times a frame across 23
   submissions with two players and 42 with four, and a pad that counts from each submission's own start changed nothing at any factor.
6. The reflection (cube map) filters were the top GPU cost, a quarter of the GPU's time in split screen, for two reasons that both lie in how Metal compiles
   one fragment shader: a pipeline specialized from a base with open colour state ran it several times slower (`pso_whole`), and one invocation computes all
   six faces whatever the target's size (`fs_split`).
7. With the placeholder list the app's first start had 116 long frames in 75 s at the title. With the merged list (15,062 rows) and a warm archive, no long
   frame of a start or a race came from a pipeline, on any of the Mushroom Cup's four tracks; "Preparing shaders" takes about 9 s.
8. Game Mode is off for the packed app (`LSSupportsGameMode` false in its Info.plist). Fullscreen, on the ProMotion screen or a TV: not measured (no TV was
   connected; every run was a window on the built-in screen).
9. The FSWZADD shaders: not looked at. The screenshots checked from one, two, three and four player races show no fault.
10. With three and four players the game sets its own 30 fps mode (a fixed step of 2), with two it runs at 60. A single Joy-Con: not tried, no controller was
    connected; players 2 to 4 were scripted (`mkw/test/routes/*.ctl`).

Beyond the questions:

- Split screen was bound by the GPU and by how the game times it, not by the CPU, until the pad worked. Only then was the replay thread the limit at a
  race's start: 27 ms of translation a frame with four players, 24 after PR #2408 and the commit's shorter walk.
- The GPU's clock follows its load. A game that needs 11 ms of a 16.7 ms frame is clocked down and misses frames when a heavy moment comes. `DM_GPU_KEEP=1`
  holds the clock at its top for about 4.5 W in a race; with the keeper on `auto` and the pad, one player's picture is drawn with 20 to 25 % fewer pixels.
- The encode thread (`enc_thread on`) takes 3 ms a frame off the replay thread with four players.
- Left: one long frame at each scene cut (TRIAGE.md, "Open"); 2 to 10 late frames in the 20 s from a split-screen race's starting grid, nearly all at the
  camera cut two seconds in; and with four players a late frame now and then on the roads between a Grand Prix's courses (10,000 draws a frame: 24 late
  frames in a whole Grand Prix with the profiled host, 71 before it; the replay takes 23 to 26 ms of the 33.3 there and the GPU 26 to 27).
- `DM_AUDIO=1 DM_AUDIO_MUTE=1` runs the real sound output with its samples zeroed: a sound-on run that nobody hears. It changed no frame count here.
- Traps met here, beside section 10's: `make` does not rebuild a source that `cp` restored within the same second as the binary (touch it). A newly packed
  app's first start waits about three minutes while macOS scans the 24 GB bundle. A route's menu presses can slip by one screen (one run of the last night
  went through a cup movie): look at a run's last screenshot before believing its numbers. `DM_AUDIO=0` in the launch environment silences a test start.

## 1. How the pieces fit

- **The game's own code runs on the Mac's CPU.** The Switch 2 and the Mac are both ARM64, so nothing is emulated instruction by instruction. The rewriter
  (`dm/tools/patch_nso.py`) rewrites the game's modules (`main`, `subsdk0`, `subsdk1`, `sdk`) where they talk to the console, and the host answers those calls. [doc]
- **The host** (`dm/host`, one binary, `dmhost`) plays the console's operating system: memory, threads, files, controllers, sound, movies (`hle_*.c`). [code]
- **Graphics**: the game calls NVN2, Nintendo's graphics API on NVIDIA hardware. `dm/gfx/nvn/hle_nvn.c` records those calls and `nvn_mtl.m` replays them through
  Apple's Metal 4. [code]
- **Shaders** are shipped compiled for the Switch 2's NVIDIA GPU ("Ampere" machine code). At build time each is translated once: Ampere code → the vendored
  Ryujinx translator with an Ampere decoder (`dm/third_party/ryujinx`, `InstEmitAmpere*.cs`) → SPIR-V → spirv-cross → Metal source → rewrites
  (`dm/gfx/tools/dmsh_rewrite.py`, `dmsh_fetch.py`) → a Metal library. Driver: `dmsh_build.py`. The whole chain has one version (`dm/gfx/nvn/dmsh_chain.h`):
  change any step and every shader of every game is translated again. [code] [doc]
- **The profile** (`dm/games/0400C3F00006E000/`): `game.tsv` (keys, turned into `#define DM_GAME_…` by `dm/games/game.py`, so a key change needs only a host
  rebuild), `patches.py` (stubs the rewriter places), `shader_map.tsv` (shader key → file), `pso_manifest.tsv` (prewarm seed list),
  `shader_pairs.tsv` / `pso_pairs.tsv` (which vertex shader goes with which pixel shader), `smoke.tsv` / `bench.tsv` (scripted routes). [code]
- **1.8.0 is packed from a derived profile.** The profile registers the base game's builds (v0). For 1.8.0 (v917504) the packing script writes a copy into
  `<build>/profile/0400C3F00006E000/` with 1.8.0's build row and shader tables made from 1.8.0's own files. That copy is keyed by the content of every profile
  file except the shader tables, `game.tsv` and `patches.py` (`DERIVED_SKIP`), plus the text of the `game.tsv` it writes: **editing the profile's README, lists
  or keys makes the next build derive it again and split the shaders again.** [code: `scripts/build_ipa_from_nsp.py` `derive_profile`]
- **The dump**: `updates/917504/{exefs,romfs}` alone is the whole game (an update's RomFS is the patched full RomFS). `exefs/main.npdm` is required. No 1.8.1
  exists. [code: `scripts/pack_dump.py`] [checked against a public version list, 2026-11-11]

### The build folder (`<dump>/0400C3F00006E000_build`, `--platform mac`)

`extract/v917504/RomFS.img` (21.7 GB) · `patched_v917504/` (rewritten modules) · `shader/cache/b-<chain>.img` (all Mac shader libraries, one file) and
`shader/cache/cas.db` (compile cache) · `tools/dmhost` · `font/` · `run/save` (the save, kept from run to run) · `run/pso_archive` (pipeline archive from the
prebuild tool) · `profile/<id>/` (the derived profile) · `bench/<time>/` (benchmark runs) · `variants/<label>/` (ours: hosts of other revisions). [doc] [code]

The run command the build prints: `cd <build>/run && DM_ROOT=<build> DM_ROMFS=<build>/extract/v917504/RomFS.img DM_SAVE=<build>/run/save DM_TEMP=<build>/run/temp
DM_MSL_DIR=<build>/shader/cache DM_FONT_DIR=<build>/font DM_NVN_SHMAP=<profile>/shader_map.tsv DM_LANG=en-US DM_WINDOW=1 DM_AUDIO=1 <build>/tools/dmhost
<build>/patched_v917504`. The prewarm seed list is read from beside the shader map. [doc: development.md, A Mac-only build] [code: `nvn_mtl.m`]

## 2. The game

- Title ID `0400C3F00006E000`. Base game v0 = 1.0.0 (SDK 19.3.3, NVN2 API 231.16); update v917504 = 1.8.0 (SDK 21.4.0), which has a `subsdk1` the base lacks.
  Nintendo EPD's engine: sead / agl / gsys, Phive, Havok, Pia. Donkey Kong Bananza runs on the same engine, so what is found on one usually applies to the other. [note]
- RomFS: 205,902 entries, 21.7 GB (base). Shaders: 11,560 in the base game's map (compute 726, pixel 7,261, vertex 3,561, domain 12; 25 are task and mesh
  shaders that draw the bushes and grass beside the track). 1.8.0: 11,604, of which the chain translates 11,603; the one that fails stops at
  `Ampere instruction 481 at 0x0 … is not implemented`. [note] [PR #2064: a 1.8.0 run on an M4 Max, 64 GB]
- **1.8.0 reaches the first race on a Mac** [PR #2064]: a 380 s scripted run shows "Ver. 1.8.0" on the title, goes through the menus and the cup movie and reaches
  the first race at about 195 s (later than the base game's 120 to 150 s), no crash, GPU 8.1 ms at the median in the race on that M4 Max. Its only `[RED]`
  lines: the VP9 decoder's "packet refused with N pictures waiting" four times in the cup movie, `texture type mismatch` for `d92d9b75e2cc7dad_b`, one
  swizzled-texture CPU fallback. Without a pipeline archive or prewarm list the race had 108 frames bound by a pipeline compile, 8.3 s in all.
- **Memory the game asks for**: the Switch 2 gives a game 9 GB of its 12 (`app_pool 0x240000000`). The game sets a 7.43 GB heap (7.47 on 1.8.0) and maps up
  to +1.75 GB of its 4 GB alias region by the title. [note]
- **What it draws into**: the top left 2048x1152 of a 3840x2160 window texture, cropped at present. Its dynamic resolution (agl) reads the GPU time between
  timestamp reports each frame and resizes the scene: sizes seen in a race 1328x748 to 1548x868 on slower Macs. Render targets therefore change size nearly
  every frame. [note] [issue #1823]
- **Terrain**: six sparse texture arrays of 8192x8192x68 (two BC6H, 5,803 MB each when made whole; four ASTC 8x8, 1,451 MB each). The host makes them Metal
  placement sparse textures and maps only the tiles the game maps. [note]
- **Compute**: 168 compute shaders of `DrivePassShaderDefault` declare 48 KB of shared memory; a culling shader (`e04783bda5a52269`) reads a list another
  (`2ce9071c2f22d74f`) rebuilds every few frames. [note]
- **Movies**: VP9 at 2560x1440 (the cup's opening: 1,423 pictures, about 25 s), decoded by the host's libvpx. [note]
- **The open world's minimap is a second 3D view of the world** (about 40 fps against 60 with it off, in an emulator): free roam is heavier than a race for that
  reason too. [SerkiGohan/Eglantine-mkw60]
- **Variable rate shading**: the game's calls are accepted and ignored, so every pixel is shaded where the console shades fewer. [note, Open]

### Frame pacing, the part that decides how the game feels

- Once a frame the game's framework picks its interval in vsyncs (function at `main+0x3a9e28` on v0; mode at `[x19+0x210]`: 1 = 60 fps, 2 = the game's own 30 fps
  mode, 0 = chosen from the frame's CPU time). The game then advances its simulation by that many 60ths of a second. So on a console **a slow frame becomes a
  30 fps frame at full game speed, never slow motion**. [note] [code: `patches.py`]
- On the Mac the mode-0 choice looked only at CPU time, so frames that waited on the GPU kept interval 1 and the game ran in slow motion. Upstream's stub
  (`MATCH_FRAME_STEP`, found by the function's fingerprint on any build that keeps it) hands the game the host's step instead, **at most 2**. [note] [code]
- The host's step comes from `dm/gfx/nvn/nvn_fstep.h`: `k` = vsyncs a frame stays on screen (the "hold"), `step` = what the game advances by. Three late frames
  in a row raise the hold; frames that fit try the lower hold again after 1 s (doubling to 8 s after a failed try); time the game is behind ("debt", at most
  0.25 s) is paid back with a step one longer than the hold. [code]
- **Our fix** (`fps_step_max 2`): the host knew no limit of the game's and could hold 3 vsyncs or pay back with a step of 3. The game took 2. Result before:
  20 fps on screen at two thirds of the game's speed. Upstream's own note has the trace of it: game time 0.977 of real time "in the one window with 3-vsync
  holds, where the game steps 2". [sim: `dm/gfx/tests/t_fstep.c`, 103 checks] [note]
- The periodic log line `[nvn] frame step: game time X s in Y s (Z of real time); held 1 / 2 / 3 vsyncs a / b / c frames, …` is the measure: Z = 1.000 means
  the game runs at its speed. [code: `hle_nvn.c` `fstep_tick`]
- `fps_target 60` in the profile; `DM_FPS_TARGET=30` caps at 30 (every frame held 2; upstream measured game time 0.996). `DM_FPS_HOLD=off`: frames are never
  held longer than the cap's vsyncs. [note] [code]

### Measured by others (none on an M2 Pro)

| Mac | Scene | Frame | GPU | Memory | Source |
|---|---|---|---|---|---|
| M6, 16 GB | first race, base game | p50 16.6-16.7 ms, p95 17-18 | 7.2-7.7 ms | resident 11.4 GB | [note] |
| M1 Pro, 16 GB | first race, base game | median 25-28 ms (33-42 fps) | 21-28 ms | wired about 7 GB, no swap growth | [note] |
| M1 Pro, 16 GB | free roam, heavier areas | about 40 fps | | 3.8-4.4 GB footprint with `mem_map_limit on` and `DM_GUEST_FILE=1` | [note] [PR #1594] |
| M4 Pro | 1.8.0, handheld mode | holds 60 fps | 10.5 ms | | [issue #1823, maintainer, 2026-11-11] |
| M1 Max | reflection (cube-map) filter passes alone | | 5.4 ms with nxnative, 1.7 with another engine | | [azmasm/switch2mac README] |

An M2 Pro's 16-core GPU sits between the M1 Pro and the M4 Pro. Expect a race near the edge of 60 fps with the scene's resolution lowered by the game, not a
comfortable 60: that is a reading of this table, not a measurement.

### Known defects upstream lists as open [note]

Long frames from pipelines compiled at first use (the profile ships no prewarm list) · `DrawMeshTasks3D` and indirect mesh draws not implemented (no run reached
them) · one foliage compute shader (`649e36162cad9e79`) keeps a race the host cannot remove · sky panels (issue #1186) resolved on the base game, **not checked on
1.8.0** · on 1.8.0: the one shader that does not translate, the `texture type mismatch`, the movie's refused packets (causes not found) [PR #2064].
Already fixed upstream, both found on 1.8.0: the dark parallelogram under the kart on the title (a mip generator's image views; `docs/reference/rendering.md`,
Image views of the type a shader declares) and lamp glows showing through buildings at night (the depth register of a partly written target;
`docs/reference/shaders.md`). If either shows on our build, the shader libraries are from an older chain.

## 3. Where the time goes, and the levers that exist

A frame has a CPU side (the game's own code, then the host translating its graphics calls: the "submit" thread, 4 to 6.5 ms a frame in a race on an M6 [note])
and a GPU side. Whichever is longer sets the frame rate. On M1 and M2 class GPUs the GPU side is the limit for this game [note: M1 Pro].
The table's last column is the state of 2026-11-11; what was taken and what each lever gave on this Mac is in TRIAGE.md and section 0.

| Lever | What it does | Measured by | State here |
|---|---|---|---|
| The game's dynamic resolution | lowers the scene's resolution when the GPU time it reads is high | [note]: M1 Pro 33.5 → 42.3 fps once the host reported real GPU times | in upstream; needs nothing |
| `DM_NVN_GPU_TS_PAD=<1.0-2.0>` | stretches the GPU times the game reads, so it lowers resolution earlier: steadier 60, softer picture | [PR #1437] | variant `c1437` |
| Multi-draws copied when their pass opens | the scene passes are no longer split: fewer passes for the GPU | [PR #1179]: GPU p50 13.0 ms against 13.65-14.1 on an M4 Pro; 72,000 pass splits to 0 in 10 minutes | variant `c1179` |
| The maintainer's heavy-frame branch | argument tables patched instead of rebuilt, long passes cut while the GPU idles, a GPU clock keeper | [PR #1847], on Donkey Kong Bananza | variant `c1847` |
| Passes overlap the previous one's fragments | fewer full GPU barriers between passes | [PR #1970]: Ocarina on an M1, GPU p50 39.5 → 37.2 ms | variant `c1970` |
| Reflection (cube-map) filter shaders | three remedies, none upstream: the NaN guard written as `fmax` [PR #1230: M1 Pro 42 → 50 fps], uniform reads loaded once (switch2mac's `cb_hoist`), one cube face per draw [PR #1251] | their authors | each changes the shader chain: a full shader rebuild per try. #1230 as written would switch off upstream's readable-tile rewrite (`dmsh_fetch.py` matches the guard it rewrites): needs a port |
| Handheld mode (`DM_OPMODE=0`) | the game renders for the console's own 1080p screen instead of a TV | [issue #1823]: 1.8.0 holds 60 on an M4 Pro | in `mkw/env-m2pro-16gb.txt` |
| MetalFX at present (`DM_PRESENT_UPSCALE=metalfx`) | the window is scaled up by Apple's upscaler instead of a plain filter | [doc: settings.md] | in `mkw/env-m2pro-16gb.txt` |
| Encode thread (`DM_NVN_ENC_THREAD=1`) | Metal encoding on its own thread: helps when the CPU side is the limit | [doc]: a win for a game that waits on its fence every frame | to try; off by default on the Mac |
| `DM_FPS_HOLD=off` | never hold a frame longer than the cap | [sim] | to try once, against our frame-step fix |
| Variable rate shading | the console shades fewer pixels in places; the host ignores the calls | nobody | not built: Metal's rasterization rate maps are the tool. A project of its own |

What does **not** help on this Mac: scaling textures down (`DM_NVN_TEX_SOFT`). It drops the finest level of large textures to save memory; memory is not our
limit and the picture gets softer.

## 4. Stutter: why a game hitches the first time it shows something, and what exists against it

A "pipeline" is one pair of shaders plus the render settings they are used with, compiled by Metal for this GPU. The first use of each costs tens of
milliseconds on the Mac, so the first minutes of a game hitch unless the pipelines are built before they are needed. [doc: development.md, Prewarm lists]

1. **Prewarm lists.** `pso_manifest.tsv` (shipped beside the shader map) then `pso_user.tsv` (written by the host as you play, beside the save folder). Rows:
   `S` a shader, `R` a render pipeline, `C` a compute pipeline, `M` a native task / mesh pipeline. They name shaders by content, so a list recorded on any
   device works on any other; rows for shaders the game version lacks are dropped at load. Record one: `DM_PSO_MANIFEST=off DM_PSO_RECORD=<file>`. [doc]
2. **The prepare step.** With a window the game waits before its first frame until every row of both lists is built ("Preparing shaders"), on every core.
   Log: `pipeline prepare: N lines (…) in … s`. [doc]
3. **Bases and the archive** (the Metal 4 path, on by default on the Mac). A pipeline's expensive part (its "base") is compiled once and stored in
   `pso_archive/` beside `pso_user.tsv`; a base comes back from the archive in about 0.06 ms against 10 to 80 ms to compile, and the final pipeline is
   specialized from it in microseconds. [doc]
4. **Hybrid pipelines.** A draw whose pipeline is missing draws at once with a stand-in ("pulling" pipeline) of the same shader pair while its own builds in
   the background. No stand-in exists for merged passes, readable-tile fragments, and layer-writing or transform-feedback vertex shaders: those draws wait. [doc]
5. **The prebuild** puts the stand-in base of every known shader pair into the archive. A `--platform mac` build runs it as a tool into
   `<build>/run/pso_archive` (log `pso_prebuild.log`), once per chain version. [doc]
6. **Task / mesh pipelines** have no stand-in: one not on a list is built before its draw. Mario Kart World has 25 such shaders, so its `M` rows matter. [doc] [note]

Lists we hold: PR #2097's (9,342 rows: 5,689 S, 3,492 R, 150 C, 11 M; recorded over about 15 launches of the first Grand Prix race on 1.8.0 on an iPhone;
there 115 frames of 50 ms or more in 7,800 became 23 in 28,700) and `mkw/pso/pso_manifest_merged_180.tsv` (15,062 rows from 10 lists of 6 repositories,
`mkw/pso/README.md`). The merged list is the profile's `pso_manifest.tsv` in `mkw-fin` and ships in the app; upstream's profile still ships the two-line placeholder. Finding what still waits:
the `pipelines up to frame` line every 300 frames (draws that waited, by reason) and `DM_PSO_WAITLOG=1` (every wait over 20 ms with its shader pair). [doc]

## 5. Memory on a 16 GB Mac

- CPU and GPU share one memory on Apple silicon. GPU memory is "wired": macOS cannot page it out. A game that wires more than the Mac has makes macOS
  swap everything else, and at the limit the Mac freezes until the power button [issue #1326]. `mkw/test/watchdog.sh` ends the game before that.
- What the game takes in a race on 16 GB Macs: before the terrain's tiles were shared, resident 12.8 GB, wired 9.6 to 9.8 GB and 6.5 GB of swap on an M6.
  With the sharing: placement heaps 1 GB instead of 3, resident 11.3 to 11.4 GB; on an M1 Pro wired about 7 GB with no swap growth over five minutes, and a
  30-minute session of two Grand Prix played through. [note]
- `mem_map_limit on` (PR #1594, in our branch): the host refused nothing where the console refuses to map past the 9 GB pool, so the game never freed its
  streaming blocks: 7.8 → 9.4 GB in 12 minutes of free roam. With it the game frees its own blocks. Log: `[mem] MapPhysicalMemory … refused …`. [PR #1594]
- `DM_GUEST_FILE=1` keeps the game's memory in files (footprint 3.8 to 4.4 GB) at the price of about twice the long frames. For 8 GB Macs; not for us. [note]
- Render targets that change size with the dynamic resolution used to be new Metal memory each time (3 to 6.7 GB added every 300 frames on a 16 GB M6);
  upstream now recycles them. [note] [issue #1823]

## 6. Three ways macOS itself slows a game [doc: reference/frame-rate.md]

- **Game Mode** holds the GPU at its lowest clock after 45 s to 3 minutes of fullscreen. The packed app declares itself not a game
  (`LSSupportsGameMode` false), but macOS remembers an app it once labelled. Check: `log show --last 10m --predicate 'process == "gamepolicyd"'`.
- **Fullscreen on a ProMotion screen** (this MacBook's): the host switches the screen to its fixed 60 Hz mode; upstream says that switch was never run on a
  ProMotion screen. Measure window and fullscreen apart.
- **The GPU clock follows the load**: a GPU that finishes early is clocked down, so the same work takes longer and a 30 fps hold can keep itself alive.
  The frame step's "probes" and PR #1847's GPU clock keeper exist for this. On battery or in Low Power Mode every number is lower.

## 7. Controllers and four players [code: `dm/host/hle_hid.c`, `front_mac.m`, `pad_slots.h`, `pad_apple.h`]

- The host takes controllers macOS's GameController framework gives an *extended gamepad* profile: DualSense, Switch Pro Controller, a left and right Joy-Con
  paired as one. A controller without that profile is logged as `no extended gamepad profile: not used`. Up to 8 players; slot p is player p + 1.
- **A single Switch 1 Joy-Con held sideways: unknown.** Upstream's own comment says it "has not been tried". `swift mkw/pads.swift` prints what macOS gives
  each connected controller. PR #1143 adds single Joy-Cons (61 files, conflicts with today's upstream). Switch 2 controllers have a separate path (`pad_switch2_apple.m`).
- Player 1 is the *handheld* controller in handheld mode (`DM_OPMODE=0`), the first wireless one otherwise; players 2 to 8 are wireless controllers on their
  own numbers in both modes. A game that supports four gets four; a fifth controller is not used.
- When a game opens the console's controller screen (who plays with what), the host answers with the connected players; with fewer than the game's minimum
  a prompt in the window waits for more.
- Open fault, found on other games: with more controllers connected than the screen's maximum, a game reopens it for ever [PR #1781]. Two players chosen with
  four controllers connected would be that case. To check at the four-player stage.
- `DM_PAD_PRESS_TO_JOIN=1`: players are numbered in the order they first press a button. `DM_KBD_PLAYER=own`: the keyboard is a player of its own.
- **Testing four players with no controller**: branch `mkw-test` adds `p2:` to `p8:` lines to the control file (`DM_CTL`); `mkw/test/ctl_feed.py` plays a
  timed script of them (section 9).
- **What the console does with 3 or 4 players** is not confirmed: two players' statements say 30 fps, a measured source covers 2 players (60). Our build will
  answer it: the game publishes its own 30 fps mode as a fixed step, and the frame step's log line names it ("the game's own step").

## 8. What other projects taught us

| Project | Kind | What we took or learned |
|---|---|---|
| MenAtCafe/mkw-neo | nxnative fork for 8 GB Macs, 1.0.0 | a CPU-upload gate that only matters with `DM_GUEST_FILE=1`; a prewarm list (in our merged list); its memory work is for Macs half this size |
| Thijs2004/nxnative-mkw | nxnative fork, 1.8.0, stale | a 1.8.0 shader map and prewarm list (in our merged list); a 30/60 interval lock, superseded by upstream's stub |
| azmasm/switch2mac | own engine with nxnative data | the reflection filters' cost on M1 (5.4 against 1.7 ms) and `cb_hoist`; its engine grows past 20 GB of memory |
| adriadam10/mkw-recomp, visibou/mkwrecomp, TsilaAllaoui/mkw-pc-recomp, MKW-THWOMP | Windows recompilations | the frame mode function confirmed independently (1.0.0 `main+0x3A9EC8`); translator fixes, all but one already in nxnative: **FSWZADD** (the Switch 2's swizzle-add) gets the older GPU's sign table in nxnative, while mkw-recomp (checked against NVIDIA's disassembler) and Eden swap two codes. 37 of the game's shaders use it. Not verified on the game; a fix changes the chain |
| SerkiGohan/Eglantine-mkw60 and -performance | emulator forks | the open world's minimap is a second 3D view |
| sn0wst0rm's pull requests (#1245, #1247, #1249, #1252) | nxnative, 1.8.0 | 1.8.0 support (superseded by the derived profile), event ordering across queues, task/mesh binding fixes: 28 to 110 conflict hunks each today |
| Android forks (AnkaNative, Swap2-Native, NativeAYN, iMKW) | Vulkan back ends | nothing for Metal |

## 9. Tools: building, driving, measuring

| Need | Tool | Notes |
|---|---|---|
| Is this Mac ready? | `mkw/test/preflight.sh` | every build prerequisite, disk, the dump, power. Run 2026-11-11: all present except the dump's `main.npdm` |
| The one full build | `mkw/test/pack.sh` | `scripts/build_ipa_from_nsp.py <dump> --platform mac`: extract, rewrite, split and build the shaders, host, pipeline prebuild. Prints the run command |
| A host of another revision | `mkw/test/host.py <label> [--base <ref>] [--key k=v] [pr/<n> …]` | built in its own git worktree against the packed game's profile, into `<build>/variants/<label>/dmhost`. About 40 s each. Profile keys through `--key`, never by editing the profile |
| Compare variants | `mkw/test/bench.sh --variant … --variant …` | upstream's `scripts/bench.py`: same save, same scripted route, variants in turn, medians and range. Frame time p50/p95/p99/max, GPU p50/p95, dropped frames, game speed, `[RED]` lines, two screenshots a run. Results in `<build>/bench/<time>/results.md` |
| Scripted input | `DM_KEYS` (player 1, at fixed seconds or frames), `DM_CTL=<file>` (lines appended while it runs: presses, `shot <png>`, `passdump`, `env K=V`) | routes: `dm/games/<id>/bench.tsv`. A recorded route: `DM_REC=<file>` while playing, then `DM_KEYS=@<file>` |
| Players 2 to 8 without controllers | `mkw/test/host_with_ctl.sh` + `ctl_feed.py`, host of branch `mkw-test` | control lines `p2:A`, `p3:A~60` … ; holds of different players run side by side |
| What a log says | `mkw/test/logsum.sh <log>` | counts and last lines by tag: `[RED]`, frame step, `[longframe]`, `[mem]`, pipelines |
| Not freezing the Mac | `mkw/test/watchdog.sh` | started by `bench.sh`; ends the game at memory pressure level 4 or +6 GB of swap |
| Frame times on screen | `DM_METAL_HUD=1` | Apple's overlay (bench.py turns it on) |
| Long frames | on by default: a `[longframe]` line for a frame over 20 ms; `DM_HITCH_DUMP=<ms>` dumps every game thread during a stall |
| GPU time per pass | `DM_NVN_GPUPROF=every:<n>` + `dm/tools/gpuprof.py`; `DM_AB=<frames>` alternates a switch set to `ab` within one run | the tool for "which pass costs what on this GPU" |
| Memory over time | `DM_MEMSTAT=<tsv>` (a line a second by region class); `footprint`, `vmmap` | |
| Pipeline waits | `DM_PSO_WAITLOG=1`; the `pipelines up to frame` line every 300 frames | |
| Does a change break another game? | `scripts/regress.py check --games <ids>` | compares two revisions on every game that has a `--platform mac` build on this Mac |
| Unit tests | `clang -O1 -Wall -o /tmp/t dm/gfx/tests/t_fstep.c && /tmp/t`; `python3 -m unittest dm/tools/tests/test_docs.py dm/tools/tests/test_game_profile.py` | run 2026-11-11: 103 checks, 6 and 28 tests pass |

**Rule for every measurement**: one change at a time, both variants in one `bench.sh` invocation, on AC power, other apps closed, window and fullscreen never
mixed. A number from a separate invocation is not comparable.

## 10. Traps (each cost time once)

- Editing anything in `dm/games/0400C3F00006E000/` re-derives the 1.8.0 profile at the next build (section 1). Use `host.py --key`.
- The shader chain version covers every tool in the chain: a one-line change to a rewrite translates all 11,604 shaders again. Chain changes go last and one at a time.
- A dump without `exefs/main.npdm` builds nothing. `mkw/verify_dump.py` compares the dump with the FTP `.listing` files.
- This clone is blobless with several remotes: git prints `not our ref` lines while it fetches file contents on demand. Harmless. `git grep` over history is slow.
- Pull requests against a host that changes daily conflict within days. `mkw/resolve_pr.py` holds the resolutions as code, checked by assertions: when
  upstream moves a line they fail loudly instead of merging wrongly.
- A pull request's title is not its content: #1873 ("a Metal 4 index buffer … on macOS 26") fixes a case its own text says no draw meets today; #1978's
  rounding fault needs two clock reads in the same 42 ns tick. Read the diff and the "Not checked" line before believing a fix matters.
- Upstream's route timings are the base game's on an M6. 1.8.0 reached its first race at about 195 s on an M4 Max.
- GitHub's web pages rate-limit or block automated reading; `git fetch` of `pull/<n>/head` and the REST API (60 requests an hour unauthenticated) work.

## 11. Open questions, in the order the first runs answer them

Answered in section 0, in the same order.

1. Does 1.8.0 boot to the title on this Mac, and how much memory does it hold there? (first run by hand, with `watchdog.sh`)
2. Does `gp-race1` reach the race inside its window? (screenshots of the first `bench.sh` run)
3. Frame p50 / p99 and GPU p50 in the race, window, handheld mode: the baseline every later number is compared with.
4. Game time against real time: 1.000 with `fps_step_max 2`? How many holds of 2?
5. Does the game lower its resolution (which sizes), and does the GPU reach 16.7 ms anyway?
6. Which passes cost the GPU time on an M2 Pro (`DM_NVN_GPUPROF`): are the reflection filters the top cost here as on the M1 Max?
7. How many frames wait for a pipeline in a first race with upstream's placeholder list, with PR #2097's, with the merged one?
8. Is Game Mode off for the app after its first fullscreen run? Does fullscreen at fixed 60 Hz work on the ProMotion screen?
9. Do the 37 FSWZADD shaders draw anything visibly wrong (derivative signs)? Find where they are used first.
10. Four players: does the game set its own 30 fps mode, and what do the frames cost? What does macOS give a single Joy-Con?
