// What the host's frame step (dm/gfx/nvn/nvn_fstep.h) does with frames slower than 2 vsyncs, against what Mario Kart World's stub can take:
// the stub hands the game the host's step capped at 2 (dm/games/0400C3F00006E000/patches.py: csel w8,w17,w8,ls after mov w8,#2).
// Build and run: cc -I dm/gfx/nvn mkw/checks/fstep_hold3.c -o /tmp/fstep_hold3 && /tmp/fstep_hold3
#include <stdio.h>
#include "nvn_fstep.h"
static void run(const char *what, double cost, int kmax, int frames) {
    nvn_fstep s = {0}; double real = 0, game = 0; int held[5] = {0};
    int step = 1;
    for (int f = 0; f < frames; f++) {
        int k = s.k ? s.k : 1;
        double shown = ceil(cost > k ? cost : k);          // a frame goes up at the first vsync after its work is done, and no sooner than its hold
        real += shown; game += step > 2 ? 2 : step;          // the game steps what the stub hands it: at most 2
        held[k < 4 ? k : 4]++;
        step = nvn_fstep_next(&s, shown, cost, 1, kmax, 0, 0);
    }
    printf("%-34s cost %.1f vsyncs, kmax %d: held 1/2/3 vsyncs %d/%d/%d frames, game time %.3f of real time\n", what, cost, kmax, held[1], held[2], held[3], game / real);
}
int main(void) {
    run("fits 60 fps", 0.8, FSTEP_MAX, 1800);
    run("fits 30 fps", 1.6, FSTEP_MAX, 1800);
    run("slower than 30 fps (host today)", 2.2, FSTEP_MAX, 1800);
    run("slower than 30 fps (hold capped)", 2.2, 2, 1800);
    return 0;
}
