// A burst of three slow frames (a few pipelines compiled in a row) in a game that otherwise fits 60 fps: how long the host's frame step keeps the picture
// below 60 fps afterwards, and how much game time Mario Kart World loses, with Hold frames when late on (kmax 3) and off (kmax = kmin = 1).
// Build and run: cc -I dm/gfx/nvn mkw/checks/fstep_hitch.c -o /tmp/fstep_hitch -lm && /tmp/fstep_hitch
#include <stdio.h>
#include "nvn_fstep.h"
static void run(const char *what, int kmax, double burst) {
    nvn_fstep s = {0}; double real = 0, game = 0, below = 0; int step = 1;
    for (int f = 0; f < 1200; f++) {
        double cost = f >= 300 && f < 303 ? burst : 0.6;      // GPU and CPU work of the frame, in vsyncs
        int k = s.k ? s.k : 1;
        double shown = ceil(cost > k ? cost : k);
        real += shown; game += step > 2 ? 2 : step;
        if (f >= 303 && k > 1) below += shown;
        step = nvn_fstep_next(&s, shown, cost, 1, kmax, 0, 0);
    }
    printf("%-10s burst of 3 frames at %.1f vsyncs: %.2f s below 60 fps after it, game time lost %.2f s (ups %llu, downs %llu)\n", what, burst, below / 60, (real - game) / 60, (unsigned long long)s.ups, (unsigned long long)s.downs);
}
int main(void) {
    run("hold on", FSTEP_MAX, 1.5); run("hold off", 1, 1.5);
    run("hold on", FSTEP_MAX, 2.5); run("hold off", 1, 2.5);
    run("hold on", FSTEP_MAX, 6.0); run("hold off", 1, 6.0);
    return 0;
}
