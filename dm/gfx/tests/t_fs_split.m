// Split outputs (profile key fs_split, DM_NVN_FS_SPLIT; nvn_mtl.m fs_split_draw): the draw of a listed fragment shader is made once for each colour attachment it writes, with
// the channel masks of the others at 0. The test's shader writes a value of its own to each of three attachments and the draws blend additively, so an attachment that one draw
// reached twice, or not at all, shows in the picture; the draws the host encodes are counted (g_stat_draw).
// ./t_fs_split: with pipelines compiled whole; ./t_fs_split --bases: with pipelines specialized from bases, where the list is not used and the picture is the same
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(s, c) do { int ok = !!(c); checks++; failed += !ok; printf("%s: %s\n", s, ok ? "PASS" : "FAIL"); } while (0)
#define LISTED "00000000000000f3"
#define LISTED_STORES "00000000000000f4"
typedef struct { uint8_t p[16384]; size_t n; } chain;
static void emit(chain *c, unsigned op, const void *a, size_t n) {
    size_t sz = (8 + n + 7) & ~7ull; if (c->n + sz > sizeof c->p) abort();
    op_hdr h = {op, (uint32_t)sz}; memcpy(c->p + c->n, &h, 8);
    if (n) memcpy(c->p + c->n + 8, a, n); c->n += sz;
}
static tex_t texture(int target, int format, int side, int layers) {
    static uint64_t serial = 820000;
    serial++;
    tex_t t = {.magic = MAGIC('T', 'E', 'X', 0), .serial = serial, .off = (int64_t)serial << 20};
    t.d = (nvn_texdesc){.target = target, .format = format, .width = (uint32_t)side, .height = (uint32_t)side, .depth = (uint32_t)layers, .levels = 1, .samples = 1};
    nvn_tex_layout(&t.d, &t.L); return t;
}
static void rt_layers(chain *c, const tex_t *t, int n, const tex_t *ds) {   // layers 0 .. n - 1 of t as colour attachments 0 .. n - 1
    p_set_rt r = {.n = n, .depth = ds};
    for (int i = 0; i < n; i++) { r.color[i] = t; r.has_cview[i] = 1; r.cview[i] = (view_t){.set_layers = 1, .min_layer = i, .nlayers = 1}; }
    emit(c, OP_SET_RT, &r, sizeof r);
}
static void additive(chain *c, int n) {   // every attachment adds what the shader writes to what it holds
    color_st col = {(1u << n) - 1, NVN_LOGIC_OP_COPY, NVN_ALPHA_FUNC_ALWAYS}; p_bind_state x = {.kind = 1}; memcpy(x.bytes, &col, sizeof col); emit(c, OP_BIND_STATE, &x, sizeof x);
    for (int i = 0; i < n; i++) {
        blend_st b = {(uint64_t)i, NVN_BLEND_FUNC_ONE, NVN_BLEND_FUNC_ONE, NVN_BLEND_FUNC_ONE, NVN_BLEND_FUNC_ONE, NVN_BLEND_EQUATION_ADD, NVN_BLEND_EQUATION_ADD};
        p_bind_state y = {.kind = 0}; memcpy(y.bytes, &b, sizeof b); emit(c, OP_BIND_STATE, &y, sizeof y);
    }
}
static void channels(chain *c, uint32_t mask) { chmask_st m = {mask}; p_bind_state x = {.kind = 2}; memcpy(x.bytes, &m, sizeof m); emit(c, OP_BIND_STATE, &x, sizeof x); }
static void bind(chain *c, const prog_t *p) { p_bind_program b = {p, 3}; emit(c, OP_BIND_PROGRAM, &b, sizeof b); }
static void triangle(chain *c) { p_draw d = {.prim = NVN_DRAW_PRIMITIVE_TRIANGLES, .count = 3, .instances = 1}; emit(c, OP_DRAW, &d, sizeof d); }
// The scene of every case: n layers of t attached and cleared to 0, the program bound, additive blending, the channel masks, and the draws
static void scene(chain *c, const prog_t *pg, const tex_t *t, int n, const tex_t *ds, uint32_t mask, int draws) {
    rt_layers(c, t, n, ds);
    for (int i = 0; i < n; i++) { p_clear_color cc = {.index = i, .mask = 0xf}; emit(c, OP_CLEAR_COLOR, &cc, sizeof cc); }
    bind(c, pg); additive(c, n); channels(c, mask);
    for (int k = 0; k < draws; k++) triangle(c);
}
static void reset(void) { state_reset(); memset(&R, 0, sizeof R); g_csh_n = 0; }
static void finish(void) {
    uint64_t f = mtl_sub_commit(); CHECK("submission completes", mtl_wait(f, 2000000000ull));
    mtl_drain(); CHECK("no GPU error", !mtl_last_commit_error());
}
static void execute(chain *c) { emit(c, OP_END, NULL, 0); reset(); mtl_sub_begin(); mtl_exec(c->p); finish(); }
static int layer_is(const tex_t *t, int layer, int r, int g, int b, int a) {   // every pixel of the layer holds these bytes
    NSUInteger side = t->d.width, n = side * side * 4; id<MTLBuffer> out = [g_dev newBufferWithLength:n options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [g_q commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:tex_mtl(t) sourceSlice:(NSUInteger)layer sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(side, side, 1) toBuffer:out destinationOffset:0 destinationBytesPerRow:side * 4 destinationBytesPerImage:n];
    [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    const uint8_t *p = out.contents, want[4] = {(uint8_t)r, (uint8_t)g, (uint8_t)b, (uint8_t)a}; int bad = 0;
    for (NSUInteger i = 0; i < side * side; i++) bad += memcmp(p + 4 * i, want, 4) != 0;
    if (bad) printf("  layer %d holds %d %d %d %d, expected %d %d %d %d\n", layer, p[0], p[1], p[2], p[3], r, g, b, a);
    return !bad;
}
// Programs live for the whole test: the pipeline cache goes by their address
static prog_t split_pg[3]; static NvProg *split_np[3];
static void program(int k, id<MTLLibrary> lib, const char *key) {
    static uint64_t serial = 930000; split_pg[k].serial = ++serial;
    NvProg *p = split_np[k] = [NvProg new]; p->sh[0] = [NvShader new]; p->sh[1] = [NvShader new];
    p->sh[0]->fn = [lib newFunctionWithName:@"v"]; p->sh[0]->stage = 0;
    p->sh[1]->fn = [lib newFunctionWithName:@"three"]; p->sh[1]->stage = 1; p->sh[1]->rf.color_known = 1; p->sh[1]->rf.color_mask = 7;
    snprintf(p->sh[1]->key, sizeof p->sh[1]->key, "%s", key);
    serial_put(split_pg[k].serial, p);
}
int main(int argc, char **argv) { @autoreleasepool {
    int bases = argc == 2 && !strcmp(argv[1], "--bases");
    setenv("DM_NVN_FS_SPLIT", LISTED ":64," LISTED_STORES ":64", 1); setenv("DM_PSO_WHOLE", bases ? "0" : "1", 1);
    alarm(60); setbuf(stdout, NULL); mtl_init();
    NSError *error = nil;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
        "vertex float4 v(uint i [[vertex_id]]) { float2 p[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)}; return float4(p[i], 0, 1); }\n"
        "struct Three { float4 a [[color(0)]]; float4 b [[color(1)]]; float4 c [[color(2)]]; };\n"
        "fragment Three three() { Three o; o.a = float4(10, 1, 0, 0) / 255.0f; o.b = float4(20, 2, 0, 0) / 255.0f; o.c = float4(30, 3, 0, 0) / 255.0f; return o; }\n" options:nil error:&error];
    if (!lib) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 2; }
    program(0, lib, LISTED); program(1, lib, "00000000000000aa"); program(2, lib, LISTED_STORES);
    int on = !bases;   // with pipelines specialized from bases the list is not used: every case below is one draw a draw

    // 1. two draws of the listed shader into three attachments: three draws each, and every attachment holds twice its own value
    { tex_t t = texture(NVN_TEXTURE_TARGET_2D_ARRAY, NVN_FORMAT_RGBA8, 8, 3); chain c = {0}; scene(&c, &split_pg[0], &t, 3, NULL, 0xfff, 2);
      uint64_t split = g_fs_split_draws, draws = g_stat_draw; execute(&c);
      CHECK(on ? "a listed shader's two draws into three attachments are made in parts" : "pipelines specialized from bases: the list is not used", g_fs_split_draws - split == (on ? 2 : 0));
      CHECK(on ? "three draws each" : "one draw each", g_stat_draw - draws == (on ? 6 : 2));
      CHECK("every attachment holds twice its own value", layer_is(&t, 0, 20, 2, 0, 0) && layer_is(&t, 1, 40, 4, 0, 0) && layer_is(&t, 2, 60, 6, 0, 0)); }

    // 2. a shader that is not listed: one draw each, the same picture
    { tex_t t = texture(NVN_TEXTURE_TARGET_2D_ARRAY, NVN_FORMAT_RGBA8, 8, 3); chain c = {0}; scene(&c, &split_pg[1], &t, 3, NULL, 0xfff, 2);
      uint64_t split = g_fs_split_draws, draws = g_stat_draw; execute(&c);
      CHECK("a shader that is not listed is drawn whole", g_fs_split_draws == split && g_stat_draw - draws == 2);
      CHECK("and gives the same picture", layer_is(&t, 0, 20, 2, 0, 0) && layer_is(&t, 1, 40, 4, 0, 0) && layer_is(&t, 2, 60, 6, 0, 0)); }

    // 3. the game's own channel masks hold in every part: red only in the first attachment, nothing in the second (no draw is made for it), all in the third
    { tex_t t = texture(NVN_TEXTURE_TARGET_2D_ARRAY, NVN_FORMAT_RGBA8, 8, 3); chain c = {0}; scene(&c, &split_pg[0], &t, 3, NULL, 0xf01, 1);
      uint64_t split = g_fs_split_draws, draws = g_stat_draw; execute(&c);
      CHECK("an attachment with every channel masked gets no draw", g_fs_split_draws - split == (on ? 1 : 0) && g_stat_draw - draws == (on ? 2 : 1));
      CHECK("each part keeps its attachment's channel mask", layer_is(&t, 0, 10, 0, 0, 0) && layer_is(&t, 1, 0, 0, 0, 0) && layer_is(&t, 2, 30, 3, 0, 0)); }

    // 4. the cases that are drawn whole: a depth attachment, a target past the listed size, one attachment
    { tex_t t = texture(NVN_TEXTURE_TARGET_2D_ARRAY, NVN_FORMAT_RGBA8, 8, 3), d = texture(NVN_TEXTURE_TARGET_2D, NVN_FORMAT_DEPTH32F_STENCIL8, 8, 1); chain c = {0}; scene(&c, &split_pg[0], &t, 3, &d, 0xfff, 2);
      uint64_t split = g_fs_split_draws, draws = g_stat_draw; execute(&c);
      CHECK("with a depth attachment the draw is made whole", g_fs_split_draws == split && g_stat_draw - draws == 2);
      CHECK("and gives the same picture", layer_is(&t, 0, 20, 2, 0, 0) && layer_is(&t, 1, 40, 4, 0, 0) && layer_is(&t, 2, 60, 6, 0, 0)); }
    { tex_t t = texture(NVN_TEXTURE_TARGET_2D_ARRAY, NVN_FORMAT_RGBA8, 16, 3); chain c = {0}; scene(&c, &split_pg[0], &t, 3, NULL, 0xfff, 2);
      uint64_t split = g_fs_split_draws, draws = g_stat_draw; execute(&c);
      CHECK("on a target past the listed size the draw is made whole", g_fs_split_draws == split && g_stat_draw - draws == 2);
      CHECK("and gives the same picture", layer_is(&t, 0, 20, 2, 0, 0) && layer_is(&t, 1, 40, 4, 0, 0) && layer_is(&t, 2, 60, 6, 0, 0)); }
    { tex_t t = texture(NVN_TEXTURE_TARGET_2D_ARRAY, NVN_FORMAT_RGBA8, 8, 3); chain c = {0}; scene(&c, &split_pg[0], &t, 1, NULL, 0xfff, 2);
      uint64_t split = g_fs_split_draws, draws = g_stat_draw; execute(&c);
      CHECK("with one attachment the draw is made whole", g_fs_split_draws == split && g_stat_draw - draws == 2);
      CHECK("and its attachment holds twice its value", layer_is(&t, 0, 20, 2, 0, 0)); }

    // 5. what else keeps a draw whole, asked of fs_split_draw with the scene's state set and no draw made yet: each on its own, then none (the draw is made in parts)
    { tex_t t = texture(NVN_TEXTURE_TARGET_2D_ARRAY, NVN_FORMAT_RGBA8, 8, 3); chain c = {0}; scene(&c, &split_pg[0], &t, 3, NULL, 0xfff, 0);
      emit(&c, OP_END, NULL, 0); reset(); mtl_sub_begin(); mtl_exec(c.p);
      chain end = {0}; emit(&end, OP_END, NULL, 0); g_exec_next = end.p;   // what a draw's look-ahead finds after it: nothing
      p_draw d = {.prim = NVN_DRAW_PRIMITIVE_TRIANGLES, .count = 3, .instances = 1}; p_draw_idx di = {.prim = NVN_DRAW_PRIMITIVE_TRIANGLES, .count = 3, .instances = 1};
      uint64_t split = g_fs_split_draws;
      g_vis_on = 1; CHECK("samples being counted: whole", !fs_split_draw(&d, NULL)); g_vis_on = 0;
      S.tf_on = 1; CHECK("transform feedback: whole", !fs_split_draw(&d, NULL)); S.tf_on = 0;
      S.rast_discard = 1; CHECK("rasterizer discard: whole", !fs_split_draw(&d, NULL)); S.rast_discard = 0;
      g_defer.active = 1; CHECK("a deferred pass being collected: whole", !fs_split_draw(&d, NULL)); g_defer.active = 0;
      g_defer_replaying = 1; CHECK("a deferred pass being replayed: whole", !fs_split_draw(&d, NULL)); g_defer_replaying = 0;
      g_fz.active = 1; CHECK("a merged pass: whole", !fs_split_draw(&d, NULL)); g_fz.active = 0;
      d.ind = 0x10000; CHECK("an indirect draw: whole", !fs_split_draw(&d, NULL)); d.ind = 0;
      d.mdi_cnt = 0x10000; CHECK("a draw of an indirect-count multi-draw: whole", !fs_split_draw(&d, NULL)); d.mdi_cnt = 0;
      di.ind = 0x10000; CHECK("an indexed indirect draw: whole", !fs_split_draw(NULL, &di)); di.ind = 0;
      CHECK("none of them made a draw", g_fs_split_draws == split);
      CHECK(on ? "with none of them the draw is made in parts" : "pipelines specialized from bases: whole", fs_split_draw(&d, NULL) == on);
      if (!on) draw_(&d, NULL);
      g_exec_next = NULL; finish();
      CHECK("every attachment holds its own value", layer_is(&t, 0, 10, 1, 0, 0) && layer_is(&t, 1, 20, 2, 0, 0) && layer_is(&t, 2, 30, 3, 0, 0)); }

    // 6. a listed shader that writes an image or a buffer would make that store once for each attachment: drawn whole
    { split_np[2]->sh[1]->rf.nb = 1; split_np[2]->sh[1]->rf.b[0] = (nvn_rbind){.kind = NVN_RB_IMG, .reg = 0, .rw = 1};
      CHECK("a listed shader that writes an image is not split", fs_split_px(split_np[2]->sh[1]) == 0);
      CHECK(on ? "the listed shader that writes none is, up to its size" : "pipelines specialized from bases: no shader is", fs_split_px(split_np[0]->sh[1]) == (on ? 64u : 0u)); }

    printf("split outputs%s: %d checks, %d failed\n", bases ? " (pipelines specialized from bases)" : "", checks, failed); return failed != 0;
} }
