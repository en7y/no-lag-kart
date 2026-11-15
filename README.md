# Mario Kart World on the Mac: an nxnative fork for docked split screen

This is a fork of [nxnative](https://github.com/seedds/nxnative), which packs your own copy of a Switch or Switch 2 game into a Mac app: the game's own code runs on the Apple chip and its graphics are rebuilt on Metal. It is not an emulator. This fork adds the fixes and settings that let **Mario Kart World 1.8.0** run in console (docked) mode, split screen included: 60 fps with one and two players and the game's own 30 fps with three and four, on a 14-inch MacBook Pro with an M2 Pro (16-core GPU) and 16 GB.

Nothing from the game is in this repository: you need your own dump of Mario Kart World with update 1.8.0. This project is not affiliated with Nintendo. nxnative's own README, with its other games and its iPhone and iPad builds, is [README-nxnative.md](README-nxnative.md).

[How it runs](#how-it-runs) · [Requirements](#requirements) · [How to play](#how-to-play) · [Settings](#settings) · [If you still get stutters](#if-you-still-get-stutters) · [What this fork changes](#what-this-fork-changes) · [Known limits](#known-limits) · [Credits](#credits)

## How it runs

One whole 150cc race (Mushroom Cup, race 1, from the countdown to the finish), twice per build and player count, on the same Mac with the same game files. Both builds ran in console mode with MetalFX upscaling and no frame hold (nxnative `main` has no GPU clock keeper, which this fork's settings turn on), fullscreen on the MacBook's own screen with Game Mode on and sound off; players 2 to 4 were scripted inputs.

| Players | This fork | nxnative `main` (`b06f4e0e`, 14 Nov 2026) |
|---|---|---|
| 1 | **60.0 fps**, 2 and 4 late frames | 56.0 and 55.9 fps, 752 and 768 late frames |
| 2 | **60.0 fps**, 1 and 1 | 45.8 and 45.7 fps, 2,674 and 2,700 |
| 4 | **30.0 fps** (the game's 30 fps split-screen mode), 1 and 1 | 22.1 and 20.5 fps, 3,459 and 4,003 \* |

A late frame stayed on screen more than 2 ms longer than its step (16.7 ms at 60 fps, 33.3 ms at 30): a hitch you can see. This fork's late frames with two and four players are the one frame at the cut into the race.

\* Below 30 fps the game itself slows down, so nxnative's four-player race had not finished when the run ended: its counts cover 220 s of racing, where this fork finished the race in 194 s.

- **The GPU sets the pace.** A frame's GPU time (median) was 13.9, 14.2 and 29.0 ms with one, two and four players here, against 14.6, 18.4 and 42.2 ms on nxnative `main`.
- **No compiles while racing.** After the same warm-up races, nxnative `main` still compiled 7 to 45 pipelines in each race; this fork compiled none.
- **The same picture or more.** Nothing in this fork's settings lowers what the game draws; its dynamic resolution picks a larger render size here (15 to 26 % more render-target megabytes a frame than on `main`), because its frames fit their time.
- **Memory** is alike in both: the footprint peaked at 10.4 to 11.2 GiB in these races, and this fork's at 12.5 GiB in a whole three-player Grand Prix.

## Requirements

- **A Mac with Apple silicon** and macOS 26.6 or later. This fork was tested on one Mac only: a 14-inch MacBook Pro, M2 Pro (10-core CPU, 16-core GPU), 16 GB, macOS 26.7.1. In split screen the GPU needs most of a frame's time there (14.2 of 16.7 ms with two players, 29.0 of 33.3 with four), so a Mac with a smaller GPU will likely not hold these frame rates: see [If you still get stutters](#if-you-still-get-stutters). Macs with 8 GB were not tested.
- **[Xcode](https://developer.apple.com/download/all/?q=Xcode%2027.2) 27.2** and its Metal toolchain: the shaders are built only with the Metal compiler they were tested with.
- **[Homebrew](https://brew.sh)** and **Python 3.12 or newer** (an arm64 one).
- **Your own dump of Mario Kart World with update 1.8.0** (v917504), as a folder: see step 3. No `prod.keys` are needed.
- **About 55 GB of free disk space** besides the dump (nxnative's rule: twice the game's size plus 10 GB). The finished app is 25 GB.

## How to play

**1. Install the tools** (once), in Terminal. Select Xcode 27.2 first: `sudo xcode-select -s /Applications/Xcode.app` (with several Xcode versions installed, the path of your 27.2, such as `/Applications/Xcode-27.2.app`).

```
xcodebuild -downloadComponent MetalToolchain
brew install xcodegen zstd glslang
python3 -m venv ~/.venvs/nxnative
~/.venvs/nxnative/bin/python3 -m pip install lz4 "capstone>=5,<6" fonttools nsz zbic "backports.zstd; python_version < '3.14'"
```

The virtual environment keeps the packages away from Homebrew's Python, which refuses a plain `pip install`.

**2. Get this repository:**

```
git clone https://github.com/mbeurms/no-lag-kart.git && cd no-lag-kart
```

**3. Put the game in a folder.** Update 1.8.0's RomFS is the whole patched game, so the update's folder alone is enough:

```
~/Games/MarioKartWorld/
  updates/917504/exefs/     main, main.npdm, rtld, sdk, subsdk0, subsdk1
  updates/917504/romfs/
```

**4. Build** the Mac app with this fork's settings:

```
~/.venvs/nxnative/bin/python3 scripts/build_ipa_from_nsp.py ~/Games/MarioKartWorld --platform mac-app --env-file "$PWD/mkw/env-m2pro-16gb.txt"
```

The app, `Mario Kart World.app`, appears in the game's folder. On the M2 Pro a rebuild in which every shader changed took 18 minutes (shader split 3:41, Mac shaders 7:35, pipeline archive 2:30, the app and its signature 2:13); a first build also packs the 23.5 GB game image first. Keep the game folder where it is: moved or renamed, it makes the next build pack that image again. All the script's options: [The packing script in detail](docs/development.md#the-packing-script-in-detail).

**5. Start it** from Finder. The first start is slow once: macOS checks the 25 GB bundle (about three minutes here before anything shows), then the app builds its graphics pipelines behind "Preparing shaders" (about a minute). Later starts take seconds. In the settings window that opens before the game, keep **Console mode: Docked** and **Frame rate: 60 fps** (the defaults), choose **Display mode: Fullscreen** (every figure above was measured in fullscreen, and macOS's Game Mode, which the app asks for, needs it), then click **Play**.

Players 2 to 4 each need a controller. Controllers, quitting, saves and the settings window: [Playing](docs/playing.md) and [Settings](docs/settings.md).

## Settings

The app is packed with [`mkw/env-m2pro-16gb.txt`](mkw/env-m2pro-16gb.txt), where each line carries its reason:

| Line | What it does |
|---|---|
| `DM_OPMODE=1` | console (docked) mode for one to four players: the game draws for 2560x1440, with larger reflection and shadow maps than in handheld mode |
| `DM_PRESENT_UPSCALE=metalfx` | MetalFX scales the picture up to the screen |
| `DM_FPS_HOLD=off` | a late frame does not lengthen the frames after it |
| `DM_GPU_KEEP=1` | keeps the GPU clock at its top (with it off, fullscreen with Game Mode averaged 1,199 of 1,398 MHz); about 4.5 W more in a race. `auto` raises the clock only as far as the frames need |
| `DM_NVN_CUT=8` | the game's submissions reach the GPU in segments of 8 draws while the GPU waits (default 64), so the GPU starts sooner |
| `DM_NVN_UP_COPY=128` | uploads come from a 128 MB resident ring, which halves the residency work at a scene cut |

To change a setting without building again, put lines of the same form in `~/Library/Application Support/nxnative/0400C3F00006E000/env.txt` (make the file if it is not there). They win over the packed settings at the next start; delete them to go back.

## If you still get stutters

On a Mac that does not hold the frame rates above, two settings trade picture for smoothness in split screen. Both exist only in this fork, and both go into `env.txt` (above):

- **`DM_NVN_GPU_TS_PAD=1.25`** (or a milder `1.10`): the game's dynamic resolution reads each frame's GPU time 25 % (10 %) longer than it was, so it lowers its render size before frames run late. The picture is a little softer when the GPU is busy.
- **`DM_OPMODE_MULTI=0`**: handheld mode once the game has found two or more players; until then the game stays in console mode. Split screen then draws for 1920x1080 with handheld's smaller reflection and shadow maps, so its picture is clearly softer.

What they did on the M2 Pro with an earlier build of this fork (13 November), which still stuttered in split screen: the same race as above, one run per line.

| `env.txt` line | Two players | Four players | Drawn per frame (two / four players) |
|---|---|---|---|
| none (two runs) | 55.8 and 55.9 fps, 769 and 804 late frames | 27.8 and 27.7 fps, 905 and 942 late frames | 393 / 715 MB |
| `DM_NVN_GPU_TS_PAD=1.10` | 57.7 fps, 426 | 29.0 fps, 396 | 4 % / 12 % less |
| `DM_NVN_GPU_TS_PAD=1.25` | 57.9 fps, 410 | 29.2 fps, 314 | 6 % / 15 % less |
| `DM_OPMODE_MULTI=0` | 59.9 fps, 29 | 30.0 fps, 9 | 25 % / 29 % less |
| `DM_OPMODE_MULTI=0` and `DM_NVN_GPU_TS_PAD=1.25` | 60.0 fps, 3 | 30.0 fps, 1 | 28 % / 30 % less |

"Drawn per frame" is the render-target megabytes the game draws into each frame, which follows the render size it picks. The pad alone halves the late frames or better; handheld split screen removes nearly all of them. On the current build the M2 Pro has only the one late frame at the cut into the race left, so there the two settings only cost picture: the pad at 1.25 draws 12 % and 19 % less (two and four players), handheld split screen 32 % and 34 % less. The current build with neither line is as smooth as the earlier one with both, and draws about half again as much (52 % and 54 % more).

## What this fork changes

The branch holds 23 fixes of its own, 15 upstream pull requests and 5 later upstream commits, each taken in only after a run on the Mac showed it helps this game (or it corrects behaviour on a path the game takes). The ones that matter most here:

- **The streamed submission:** the GPU starts on a frame 0.9 ms after the game submits it, where it used to wait for the host's copy of the whole frame.
- **Segments of 8 draws** while the GPU waits (`DM_NVN_CUT=8`), the **upload ring** (`DM_NVN_UP_COPY=128`) and the reflection filters drawn as one **layered pass** for each cube face: with these, console mode holds a split screen.
- **Whole render pipelines** (`pso_whole`) and a **merged warm-up list** of 15,062 pipelines from ten lists, so nothing compiles while racing.
- **Fewer passes** for the sky's cube map, the **memory-pool freeze** (a 50 to 70 ms frame once per stretch of track) now rare, and the **frame step for 1.8.0**, so a late frame no longer plays in slow motion.
- **The GPU clock keeper** of upstream pull request #1847, and **the host built with a profile of its own runs** (PGO).

Every change with its measurement, and what was tried and left out: [`mkw/TRIAGE.md`](mkw/TRIAGE.md). The state of the build: [`mkw/README.md`](mkw/README.md). How the port works and what is known about the game: [`mkw/KNOWLEDGE.md`](mkw/KNOWLEDGE.md).

## Known limits

- **One Mac:** a 16 GB M2 Pro MacBook Pro, its built-in screen, fullscreen at a fixed 60 Hz. Other Macs, TVs and external screens, real controllers for players 2 to 4 (scripted here), free roam and the other modes were not tested with this build. iPhone and iPad builds of this fork were not tested either.
- **Heavier courses:** over a whole Grand Prix, a few minutes of heavier courses still bring late frames, up to about two a second (two players on the Star Cup, four on the Banana Cup).
- **Scene cuts:** one frame of about 70 to 115 ms at each scene cut, where several hundred textures are shown for the first time.
- **Sound** was off in the timed runs. An earlier check with the sound path running but muted found no late frame with one player and up to 5 a minute with four (0 to 1 without it).

## Credits

- **[nxnative](https://github.com/seedds/nxnative)** by seedds and its contributors, which this fork is built on, and the projects nxnative builds on ([its acknowledgements](README-nxnative.md#acknowledgements)).
- The authors of the upstream pull requests in the branch, listed in [`mkw/TRIAGE.md`](mkw/TRIAGE.md).
- The warm-up lists merged into this build's: seedds/nxnative pull request #2097, Thijs2004/nxnative-mkw, azmasm/switch2mac, cheemu21/plumber-racer-2 and pahorema/kartnative ([`mkw/pso/README.md`](mkw/pso/README.md)).

## License

MIT, as nxnative ([LICENSE](LICENSE)). Third-party code keeps its own license ([dm/third_party](dm/third_party/README.md)).
