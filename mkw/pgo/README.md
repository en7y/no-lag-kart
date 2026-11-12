# The host's profile (`dmhost.profdata`)

`dm/host/Makefile` builds Mario Kart World's Mac host with this file (`-fprofile-instr-use`): clang lays out and inlines the host's code by how often each
branch and call ran in the recorded runs. No source line changes, and a build without the file is the plain `-O2` host. Other games' hosts are built
without it: a profile says nothing of code its runs never reached, and clang lays such code out as cold.

Recorded on 2026-11-12 on the 16 GB M2 Pro from the host of `mkw-fin` at `201b1bbd`: an instrumented build (`-fprofile-instr-generate`) played the routes
`gp150-4p` (180 s), `gp150-2p` (180 s) and `gp-start-150` (135 s) with the real sound output running silently (`DM_AUDIO=1 DM_AUDIO_MUTE=1`), so the start,
the menus, the course's movie, the race in the 60 and the 30 fps mode and the sound path are in it. The three `.profraw` files were merged with
`xcrun llvm-profdata merge`.

Measured, four players at 150cc, one run each of the same source built with and without the profile (the replay thread, medians a frame):

| Stretch | Draws a frame | Instructions a draw | CPU time | Time on the clock | Late frames |
|---|---|---|---|---|---|
| The first race, seconds 120 to 180 | 8,000 | 23,327 → 21,257 | 20.82 → 19.32 ms | 22.55 → 21.24 ms | 0 → 0 |
| Its start, seconds 100 to 120 | 11,000 | 21,790 → 19,517 | 24.53 → 21.75 ms | 26.31 → 23.56 ms | 7 → 3 |
| The road to the second course, seconds 330 to 390 (`gp150-4p-r2`) | 10,300 | 22,314 → 19,826 | 25.67 → 23.14 ms | 27.54 → 25.13 ms | 14 → 1 |

A frame has 33.3 ms in the game's 30 fps mode, and on that road the GPU takes 26 to 27 of them too: the 2.4 ms are what kept the frames on time.

To record it again after the replay's hot paths change (a stale profile costs speed, never correctness: clang builds a function whose source changed
without it):

    mkw/test/host.py pgoi --base mkw-fin --cflags=-fprofile-instr-generate
    # bench runs of the variant pgoi with LLVM_PROFILE_FILE=/tmp/pgo/mkw-%p%c.profraw,DM_AUDIO=1,DM_AUDIO_MUTE=1 among its settings
    xcrun llvm-profdata merge -o mkw/pgo/dmhost.profdata /tmp/pgo/*.profraw
