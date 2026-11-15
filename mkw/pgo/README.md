# The host's profile (`dmhost.profdata`)

`dm/host/Makefile` builds Mario Kart World's Mac host with this file (`-fprofile-instr-use`): clang lays out and inlines the host's code by how often each
branch and call ran in the recorded runs. No source line changes, and a build without the file is the plain `-O2` host. Other games' hosts are built
without it: a profile says nothing of code its runs never reached, and clang lays such code out as cold.

Recorded on 2026-11-14 on the 16 GB M2 Pro from the host of `mkw-fin3` at `cb68adf7`: an instrumented build (`-fprofile-instr-generate`) played the routes
`gp150-4p` (180 s), `gp150-2p` (180 s) and `gp-start-150` (135 s) in a window, as a child of the bench (`LLVM_PROFILE_FILE` must reach the host, and an app
started through `open` gets only `DM_`, `MKW_`, `MTL_` and `METAL_` variables), in console mode, with the real sound output running silently
(`DM_AUDIO=1 DM_AUDIO_MUTE=1`), so the start, the menus, the course's movie, the race in the 60 and the 30 fps mode and the sound path are in it. The three
`.profraw` files were merged with `xcrun llvm-profdata merge`. It replaces the first recording (2026-11-12, from `mkw-fin` at `d3197c42`), which the
streamed submission, the upload ring, the face-layered filter passes and the per-draw feedback checks had made stale where the replay spends its time.

Measured with the first recording, four players at 150cc, one run each of the same source built with and without the profile (the replay thread, medians a frame):

| Stretch | Draws a frame | Instructions a draw | CPU time | Time on the clock | Late frames |
|---|---|---|---|---|---|
| The first race, seconds 120 to 180 | 8,000 | 23,327 → 21,257 | 20.82 → 19.32 ms | 22.55 → 21.24 ms | 0 → 0 |
| Its start, seconds 100 to 120 | 11,000 | 21,790 → 19,517 | 24.53 → 21.75 ms | 26.31 → 23.56 ms | 7 → 3 |
| The road to the second course, seconds 330 to 390 (`gp150-4p-r2`), three runs with the profile | 10,100 to 10,800 | 22,314 → 19,269 to 19,826 | 25.67 → 21.26 to 24.11 ms | 27.54 → 23.26 to 26.11 ms | 14 → 1, 16 and 1 |
| The Mushroom Cup's four races, seconds 120 to 985 (`gp150-4p-full`) | 6,400 to 10,800 | | | | 71 → 24 |

A frame has 33.3 ms in the game's 30 fps mode, and on that road the GPU takes 26 to 27 of them at the median too, so its late frames follow how heavy the four
views happen to be: the profiled run with 16 had 10,800 draws a frame where the others had 10,100 to 10,400. The whole Grand Prix is what tells: 71 late
frames in 25,529 without the profile (62 of them in frames of 9,000 draws or more), 24 in 25,593 with it (17), no minute with more than 6 where there
were up to 15. (The commit that added the profile, `56213e57`, says "14 late frames become 1" from the first run of each alone.)

To record it again after the replay's hot paths change (a stale profile costs speed, never correctness: clang builds a function whose source changed
without it):

    mkw/test/host.py pgoi --base mkw-fin --cflags=-fprofile-instr-generate
    # bench runs of the variant pgoi with LLVM_PROFILE_FILE=/tmp/pgo/mkw-%p%c.profraw,DM_AUDIO=1,DM_AUDIO_MUTE=1 among its settings
    xcrun llvm-profdata merge -o mkw/pgo/dmhost.profdata /tmp/pgo/*.profraw
