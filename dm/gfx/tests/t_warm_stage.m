// A prewarm line names each shader at the stage the shader map gives it, or it is left out (warm_parse, warm_stage_differs in nvn_mtl.m). The loader takes a line's stage at its
// word (shader_load) and the prewarm's shaders go into the shader cache the draws read (warm_claim), so a list from a host that numbered NVN2's task and mesh stages 6 and 7, or
// ran them as compute shaders with C lines of their own, put those shaders there at a stage they do not have; a compute pipeline of a mesh function took Metal's compiler service
// down, and the host with it, in the prepare step (Mario Kart World 1.8.0 with a list merged from other hosts' lists: mkw/KNOWLEDGE.md).
#include "../nvn/nvn_mtl.m"
#include <stdlib.h>
#include <unistd.h>

void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }

static int g_checks, g_failed;
#define EXPECT_EQ(name, want, got) do { \
    long long w_ = (long long)(want), g_ = (long long)(got); g_checks++; \
    printf("%s expected %lld -> got %lld %s\n", name, w_, g_, w_ == g_ ? "OK" : "FAIL"); \
    g_failed += w_ != g_; \
} while (0)

static void put(NSString *dir, NSString *name, NSString *text) {
    if (![text writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil]) { printf("cannot write %s\n", name.UTF8String); exit(2); }
}
#define VS "aaaaaaaaaaaaaaa1_b"
#define PS "aaaaaaaaaaaaaaa2_b"
#define CS "aaaaaaaaaaaaaaa3_b"
#define MS "aaaaaaaaaaaaaaa4_b"
#define TS "aaaaaaaaaaaaaaa5_b"
// An R line of vertex shader vs at stage vst and pixel shader fs (or none) at stage fst; mark makes two lines of one pair two keys
static NSString *r_line(const char *vs, int vst, const char *fs, int fst, int mark) {
    pso_skey sk; memset(&sk, 0, sizeof sk);
    strlcpy(sk.vs, vs, sizeof sk.vs); sk.vs_stage = (uint8_t)vst;
    if (fs) { strlcpy(sk.fs, fs, sizeof sk.fs); sk.fs_stage = (uint8_t)fst; }
    sk.k.samples = (uint32_t)mark;
    char hex[sizeof sk * 2 + 1]; pso_skey_hex(&sk, hex);
    return [NSString stringWithFormat:@"R\t%s\n", hex];
}
static int has(NSArray<WarmTask *> *tasks, int kind, const char *key, int stage) {
    int n = 0; for (WarmTask *t in tasks) n += t->kind == kind && [t->key isEqualToString:@(key)] && t->stage == stage;
    return n;
}
static int has_pair(NSArray<WarmTask *> *tasks, const char *vs, const char *fs, int rows) {
    int n = 0; for (WarmTask *t in tasks) n += t->kind == 1 && [t->vkey isEqualToString:@(vs)] && [t->fkey isEqualToString:@(fs)] && (int)t->rs.count == rows;
    return n;
}

int main(void) { @autoreleasepool {
    char tmpl[] = "/tmp/t_warm_stage.XXXXXX";
    if (!mkdtemp(tmpl)) { perror("mkdtemp"); return 2; }
    NSString *dir = @(tmpl);
    put(dir, @"shader_map.tsv", @"package\tindex\tstage\tdm_ctl_sha16\tsource\n"
        "a.bin\t0\tvertex\taaaaaaaaaaaaaaa1\tx\na.bin\t1\tpixel\taaaaaaaaaaaaaaa2\tx\na.bin\t2\tcompute\taaaaaaaaaaaaaaa3\tx\n"
        "a.bin\t3\tmesh\taaaaaaaaaaaaaaa4\tx\na.bin\t4\ttask\taaaaaaaaaaaaaaa5\tx\n");
    NSMutableString *l = [NSMutableString stringWithString:@"# lines of this host, then lines as other hosts wrote them\n"];
    [l appendString:@"S\t" VS "\t0\nS\t" PS "\t1\nS\t" CS "\t5\nS\t" TS "\t3\nS\t" MS "\t4\nC\t" CS "\n"];                      // this host's: every stage is the map's
    [l appendString:r_line(VS, 0, PS, 1, 1)]; [l appendString:r_line(VS, 0, PS, 1, 2)]; [l appendString:r_line(VS, 0, NULL, 0, 1)];
    [l appendString:@"S\t" TS "\t6\nS\t" MS "\t7\n"];                                                                          // the API's numbers for task and mesh
    [l appendString:@"S\t" MS "\t5\nS\t" TS "\t5\nC\t" MS "\nC\t" TS "\n"];                                                    // task and mesh run as compute shaders
    [l appendString:@"C\t" VS "\nS\t" PS "\t0\n"];                                                                             // a vertex shader as compute, a pixel shader as vertex
    [l appendString:r_line(PS, 0, PS, 1, 1)]; [l appendString:r_line(VS, 0, CS, 1, 1)]; [l appendString:r_line(MS, 0, PS, 1, 1)];   // a pair with a shader of another stage
    [l appendString:@"S\tbbbbbbbbbbbbbbb1_b\t0\n"];                                                                           // another game version's shader
    put(dir, @"list.tsv", l);
    setenv("DM_NVN_SHMAP", [dir stringByAppendingPathComponent:@"shader_map.tsv"].UTF8String, 1);
    setenv("DM_MSL_DIR", tmpl, 1);
    setenv("DM_PSO_MANIFEST", "off", 1);   // nothing starts by itself: the lines are parsed here
    unsetenv("DM_SAVE");
    mtl_init();
    shmap_read_once();
    EXPECT_EQ("the map's five shaders are read", 5, g_shmap.count);

    long lines = 0; NSArray<WarmTask *> *tasks = warm_parse(@[[dir stringByAppendingPathComponent:@"list.tsv"]], &lines);
    EXPECT_EQ("lines taken: this host's 9", 9, lines);
    EXPECT_EQ("tasks: 5 shaders, 1 compute pipeline, 2 pairs", 8, tasks.count);
    EXPECT_EQ("vertex shader at 0", 1, has(tasks, 0, VS, 0));
    EXPECT_EQ("pixel shader at 1", 1, has(tasks, 0, PS, 1));
    EXPECT_EQ("compute shader at 5", 1, has(tasks, 0, CS, 5));
    EXPECT_EQ("task shader at 3", 1, has(tasks, 0, TS, 3));
    EXPECT_EQ("mesh shader at 4", 1, has(tasks, 0, MS, 4));
    EXPECT_EQ("compute pipeline of the compute shader", 1, has(tasks, 2, CS, 5));
    EXPECT_EQ("the pair's two pipelines in one task", 1, has_pair(tasks, VS, PS, 2));
    EXPECT_EQ("the vertex shader's pipeline without a pixel shader", 1, has_pair(tasks, VS, "", 1));
    EXPECT_EQ("no task or mesh shader at 5, 6 or 7", 0, has(tasks, 0, TS, 6) + has(tasks, 0, MS, 7) + has(tasks, 0, MS, 5) + has(tasks, 0, TS, 5));
    EXPECT_EQ("no compute pipeline of a mesh, task or vertex shader", 0, has(tasks, 2, MS, 5) + has(tasks, 2, TS, 5) + has(tasks, 2, VS, 5));
    EXPECT_EQ("no pixel shader at 0", 0, has(tasks, 0, PS, 0));
    EXPECT_EQ("no pair with a shader of another stage", 0, has_pair(tasks, PS, PS, 1) + has_pair(tasks, VS, CS, 1) + has_pair(tasks, MS, PS, 1));
    EXPECT_EQ("lines left out for the stage: 5 S, 3 C, 3 R", 11, g_warm_skip_stage);
    EXPECT_EQ("the other version's shader counts apart", 1, g_warm_skip_stale);

    [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
    printf("%d checks, %d failed\n", g_checks, g_failed);
    return g_failed != 0;
} }
