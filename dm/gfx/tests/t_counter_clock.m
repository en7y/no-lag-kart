// Feed a delayed CPU/GPU sample to the production counter replay without a Metal device.
#include "../nvn/nvn_mtl.m"

module_t *g_mod;
int g_nmod;
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
void *module_sym(module_t *m, const char *name) { (void)m; (void)name; return NULL; }
void *guest_sym(const char *name) { (void)name; return NULL; }
void svc_thread_dump(void) {}
void dm_guest_clock_advanced(void) {}

static unsigned checks, failures;
#define CHECK(label, condition) do { checks++; if (!(condition)) { failures++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)

@interface ClockDevice : NSObject
@property MTLTimestamp cpu;
@property MTLTimestamp gpu;
@end
@implementation ClockDevice
- (void)sampleTimestamps:(MTLTimestamp *)cpu gpuTimestamp:(MTLTimestamp *)gpu { *cpu = self.cpu; *gpu = self.gpu; }
- (uint64_t)queryTimestampFrequency { return 1000000000; }
@end

@interface ClockHeap : NSObject
@property uint64_t boundary;
@property uint64_t *slots;   // when set: the stamp of each slot, 0 for slot 0 too
@property NSUInteger nslots;
@end
@implementation ClockHeap
- (NSData *)resolveCounterRange:(NSRange)range {
    if (range.length != 1) return nil;
    MTL4TimestampHeapEntry entry = {.timestamp = self.slots ? (range.location < self.nslots ? self.slots[range.location] : 0) : self.boundary};
    return self.slots || range.location == 0 ? [NSData dataWithBytes:&entry length:sizeof entry] : nil;
}
@end

// A submission of three command buffers, its GPU idle between them while the host translated (sub_cut commits only once the GPU has run out of work):
//   command buffer 0: segments 0 and 1, GPU 0 to 3,000 ns, committed at the boundary after segment 1; the boundary's stamp lands at the start of command buffer 1 (4,010)
//   command buffer 1: segment 2, 4,000 to 6,000, committed after segment 2; that boundary's stamp landed in its last encoder, before the commit (5,990)
//   the last one: segments 3 and 4, 9,000 to 12,000 (c0 / c1), the stamp at the boundary between them 10,000
// A span of reports reads the GPU's work alone: the 1,000 ns and 3,000 ns gaps are left out once a time is past their middle
static void check_idle_gaps(ClockDevice *device, ClockHeap *heap) {
    uint64_t g0 = device.cpu - 50000, off = device.gpu - device.cpu;   // guest time of the submission's start; a heap stamp is on the GPU clock, guest + off
    static seg_clk clock; memset(&clock, 0, sizeof clock);
    clock.nb = 5; for (int k = 0; k < 5; k++) clock.b[k] = (uint16_t)k;
    clock.ncm = 2; clock.cm[0] = 1; clock.cm[1] = 2;
    atomic_store(&clock.t[1][0], g0); atomic_store(&clock.t[1][1], g0 + 3000);
    atomic_store(&clock.t[2][0], g0 + 4000); atomic_store(&clock.t[2][1], g0 + 6000);
    uint64_t c0 = g0 + 9000, c1 = g0 + 12000;
    uint64_t slots[5] = {g0 + 5 + off, g0 + 1500 + off, g0 + 4010 + off, g0 + 5990 + off, g0 + 10000 + off};
    heap.slots = slots; heap.nslots = 5;
    CHECK("no idle before the first commit", seg_idle_before(&clock, g0 + 3400, c0) == 0);
    CHECK("a gap counts once a time is past its middle", seg_idle_before(&clock, g0 + 3600, c0) == 1000);
    CHECK("both gaps before the last command buffer", seg_idle_before(&clock, g0 + 9000, c0) == 4000);
    post_op top0 = {.type = 0x10, .seg = 0}, end1 = {.type = 0, .seg = 1}, end2 = {.type = 0, .seg = 2}, top4 = {.type = 0x10, .seg = 4}, end4 = {.type = 0, .seg = 4};
    CHECK("the first report keeps its time", rep_ticks(&top0, &clock, 4, c0, c1) == nvn_timestamp_from_ns(g0 + 5));
    CHECK("a stamp written after a commit leaves out the gap before it", rep_ticks(&end1, &clock, 4, c0, c1) == nvn_timestamp_from_ns(g0 + 3010));
    CHECK("a stamp written before a commit keeps the time of its command buffer", rep_ticks(&end2, &clock, 4, c0, c1) == nvn_timestamp_from_ns(g0 + 4990));
    CHECK("a stamp in the last command buffer leaves out both gaps", rep_ticks(&top4, &clock, 4, c0, c1) == nvn_timestamp_from_ns(g0 + 6000));
    CHECK("the submission's end leaves out both gaps", rep_ticks(&end4, &clock, 4, c0, c1) == nvn_timestamp_from_ns(g0 + 8000));
    CHECK("the span of the submission is its GPU work", rep_ticks(&end4, &clock, 4, c0, c1) - rep_ticks(&top0, &clock, 4, c0, c1) == nvn_timestamp_from_ns(g0 + 8000) - nvn_timestamp_from_ns(g0 + 5));
    atomic_store(&clock.t[2][0], 0); atomic_store(&clock.t[2][1], 0);   // command buffer 1's feedback has not arrived
    CHECK("a command buffer with no feedback gives no gap", seg_idle_before(&clock, g0 + 9000, c0) == 0);
    heap.slots = NULL; heap.nslots = 0;
}

// DM_NVN_GPU_TS_PAD=1.25 (./t_counter_clock --pad): a frame's report times are stretched from the GPU start of its first submission, whichever submission a report is in. A game
// that reads its frame's GPU time from a report in its first submission and one in its last then measures it 1.25 times as long; stretched from each submission's own start,
// as it was, only the last submission's part was
static void check_pad(void) {
    const uint64_t g0 = 5000000000ull;
    post_op top = {.type = 0x10, .seg = 0}, end = {.type = 0, .seg = 0};
    #define T(ns) nvn_timestamp_from_ns(ns)
    pad_begin(7, NULL, 0, g0);   // frame 7's first submission: one command buffer, the GPU at work from g0 to g0 + 4,000
    uint64_t a0 = rep_ticks(&top, NULL, 0, g0, g0 + 4000), a1 = rep_ticks(&end, NULL, 0, g0, g0 + 4000);
    CHECK("the frame's first report keeps its time", a0 == T(g0));
    CHECK("the first submission's end is stretched from the frame's start", a1 == T(g0 + 5000));
    pad_begin(7, NULL, 0, g0 + 6000);   // its second submission, g0 + 6,000 to g0 + 10,000 (the 2,000 between them: the host translating)
    uint64_t b0 = rep_ticks(&top, NULL, 0, g0 + 6000, g0 + 10000), b1 = rep_ticks(&end, NULL, 0, g0 + 6000, g0 + 10000);
    CHECK("a later submission's start is stretched from the frame's start too", b0 == T(g0 + 7500));
    CHECK("and its end", b1 == T(g0 + 12500));
    CHECK("the frame's span, first report to last, reads 1.25 times its 10,000 ns", b1 - a0 == T(g0 + 12500) - T(g0));
    pad_begin(8, NULL, 0, g0 + 20000);   // the next frame starts anew
    CHECK("the next frame's first report keeps its time", rep_ticks(&top, NULL, 0, g0 + 20000, g0 + 23000) == T(g0 + 20000));
    CHECK("and its end is stretched from that frame's start", rep_ticks(&end, NULL, 0, g0 + 20000, g0 + 23000) == T(g0 + 23750));
    pad_begin(9, NULL, 0, 0);   // a first submission with no GPU time yet
    CHECK("a submission with no time gives its frame no start", g_pad_base == 0 && g_pad_frame == 8);
    pad_begin(9, NULL, 0, g0 + 40000);
    CHECK("the frame's next submission gives it", g_pad_base == g0 + 40000 && g_pad_frame == 9 && rep_ticks(&end, NULL, 0, g0 + 40000, g0 + 42000) == T(g0 + 42500));
    static seg_clk clock; memset(&clock, 0, sizeof clock); atomic_store(&clock.t[0][0], g0 + 50000); atomic_store(&clock.t[0][1], g0 + 51000);
    pad_begin(10, &clock, 2, g0 + 53000);   // a submission cut into command buffers: gaps come only after its first segment
    CHECK("a submission of several command buffers starts at its first segment's GPU start", g_pad_base == g0 + 50000 && g_pad_frame == 10);
    pad_begin(10, NULL, 0, g0 + 50000 + PAD_FRAME_NS);   // a frame that goes on and on (a loading screen that presents nothing)
    CHECK("a frame's start holds for a quarter of a second", g_pad_base == g0 + 50000);
    pad_begin(10, NULL, 0, 0);
    CHECK("and through a submission with no time", g_pad_base == g0 + 50000 && g_pad_frame == 10);
    pad_begin(10, NULL, 0, g0 + 50001 + PAD_FRAME_NS);
    CHECK("past that the stretch starts anew", g_pad_base == g0 + 50001 + PAD_FRAME_NS && g_pad_frame == 10);
    #undef T
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--pad")) {
        setenv("DM_NVN_GPU_TS_PAD", "1.25", 1); check_pad();
        printf("counter clock, reports stretched 1.25 times: %u checks, %u failed\n", checks, failures);
        return failures != 0;
    }
    @autoreleasepool {
        ClockDevice *device = [ClockDevice new];
        ClockHeap *heap = [ClockHeap new];
        g_dev = (id<MTLDevice>)device;
        g_ts_heap = (id<MTL4CounterHeap>)heap;
        const uint64_t age = 8000000, delay = 20000000, offset = 100000000;
        // The sampled CPU time predates the report by at least 20 ms. A late guest-clock
        // read would add that scheduling delay to the value sent to the game.
        device.cpu = now_ns() - delay;
        device.gpu = device.cpu + offset;
        heap.boundary = device.gpu - age;
        seg_clk clock = {.nb = 1, .b = {0}};
        post_op report = {.type = 0x10, .seg = 0};
        uint64_t expected = nvn_timestamp_from_ns(device.cpu - age);
        CHECK("a late read preserves the GPU boundary's sampled guest time", rep_ticks(&report, &clock, 0, 0, 0) == expected);
        device.cpu += 1000;
        device.gpu += 1000;
        CHECK("a later clock pair maps the same boundary to the same report", rep_ticks(&report, &clock, 0, 0, 0) == expected);
        device.cpu = 0;
        CHECK("a missing CPU sample takes the existing feedback fallback", rep_ticks(&report, &clock, 0, 10000, 0) == nvn_timestamp_from_ns(10000));
        device.cpu = now_ns() - delay; device.gpu = device.cpu + offset;
        check_idle_gaps(device, heap);
        pad_begin(7, NULL, 0, 1000); CHECK("with no stretch asked for a frame takes no start", g_pad_base == 0 && g_pad_frame == UINT64_MAX);

        guest_clock_freeze(1);
        uint64_t frozen = guest_ns();
        CHECK("projection keeps the frozen guest time", guest_ns_at_host_time(1) == frozen);
        usleep(1000);
        guest_clock_freeze(0);
        uint64_t host = now_ns(), guest = guest_ns_at_host_time(host);
        CHECK("projection subtracts the time spent frozen", guest < host && guest >= frozen);
        CHECK("a host sample older than the pause offset cannot underflow", guest_ns_at_host_time(1) == 0);
        CHECK("feedback conversion uses the resumed guest epoch", llabs((int64_t)gpu_s_guest_ns(host / 1e9) - (int64_t)guest) <= 2);
        CHECK("future feedback is rejected", gpu_s_guest_ns(host / 1e9 + 1) == 0);
        CHECK("invalid feedback is rejected", gpu_s_guest_ns(NAN) == 0 && gpu_s_guest_ns(INFINITY) == 0);

        setenv("DM_DETCLOCK", "1000000", 1);
        dm_guest_frame_tick();
        uint64_t deterministic = guest_ns();
        CHECK("deterministic projection uses the current guest frame", guest_ns_at_host_time(host) == deterministic);
        dm_guest_frame_tick();
        CHECK("deterministic projection advances by the configured step", guest_ns_at_host_time(host) == deterministic + 1000000);
    }
    printf("counter clock: %u checks, %u failed\n", checks, failures);
    return failures != 0;
}
