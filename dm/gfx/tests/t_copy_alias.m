// Copies through distinct Metal buffers and sparse guest aliases must see earlier GPU writes.
#define nvn_game_fps nvn_game_fps_mtl_default
#include "../nvn/nvn_mtl.m"
#undef nvn_game_fps
#define g_ft g_ft_hle
#include "../nvn/hle_nvn.c"
#undef g_ft
uint64_t g_t0_ns;
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c, label) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)

static void finish(void) {
    CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull), "GPU submission completed");
    CHECK(!mtl_last_commit_error(), "GPU submission has no error");
}
static void bytes(const void *got, const void *want, size_t n, const char *label) {
    CHECK(!memcmp(got, want, n), label);
}
static void separate_buffers(void) {
    size_t pg = getpagesize();
    void *mem = mmap(NULL, pg, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    CHECK(mem != MAP_FAILED, "no-copy backing allocated"); if (mem == MAP_FAILED) abort();
    id<MTLBuffer> a = [g_dev newBufferWithBytesNoCopy:mem length:pg options:MTLResourceStorageModeShared deallocator:nil];
    id<MTLBuffer> b = [g_dev newBufferWithBytesNoCopy:mem length:pg options:MTLResourceStorageModeShared deallocator:nil];
    id<MTLBuffer> io = [g_dev newBufferWithLength:pg options:MTLResourceStorageModeShared];
    CHECK(a && b && io && a.gpuAddress != b.gpuAddress, "one allocation has distinct GPU addresses");
    if (!a || !b || !io) abort(); res_add(a); res_add(b); res_add(io);
    for (int split = 0; split < 2; split++) {
        memset(mem, 0, pg); memset(io.contents, 0, pg); memset(io.contents, 0x6d, 256);
        mtl_sub_begin();
        enc_b_copy_buffer(blit_buf(0x10000, 0x10100, (uint64_t)mem, (uint64_t)mem + 256), io, 0, a, 0, 256);
        if (split) { enc_b_end(g_blit); g_blit = nil; }
        enc_b_copy_buffer(blit_buf((uint64_t)mem, (uint64_t)mem + 256, 0x20000, 0x20100), b, 0, io, 512, 256);
        finish(); bytes((uint8_t *)io.contents + 512, io.contents, 256, "copy reads through a second no-copy buffer");
    }
    res_remove(a); res_remove(b); res_remove(io); a = b = nil; munmap(mem, pg);
}
// A texture of a sparse pool shares storage with one outside sparse pools only where its pool has mapped pages of the physical pool the other lies in (tex_storage_overlap)
static void sparse_shares(void) {
    const size_t len = 4 * getpagesize();
    uint8_t *m1 = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0), *m2 = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (m1 == MAP_FAILED || m2 == MAP_FAILED) abort();
    pool_t p1, p2, sparse;
    pool_builder_t pb = {.mem=m1, .size=len, .flags=0x24};
    CHECK(h_nvnMemoryPoolInitialize((NVNmemoryPool *)&p1, (const NVNmemoryPoolBuilder *)&pb), "first physical pool initialized");
    pb.mem = m2;
    CHECK(h_nvnMemoryPoolInitialize((NVNmemoryPool *)&p2, (const NVNmemoryPoolBuilder *)&pb), "second physical pool initialized");
    pb = (pool_builder_t){.size=DM_GAME_APP_POOL + 2 * len, .flags=0x200};
    CHECK(h_nvnMemoryPoolInitialize((NVNmemoryPool *)&sparse, (const NVNmemoryPoolBuilder *)&pb), "sparse pool initialized");
    tex_t ts = {0}, ts2 = {0}, t1 = {0}, t2 = {0};
    ts.serial = 99901; ts.pool = &sparse; ts.mem = sparse.mem; ts.L.size = len;
    ts2 = ts; ts2.serial = 99902; ts2.mem = sparse.mem + len;
    t1.serial = 99903; t1.pool = &p1; t1.mem = m1 + 256; t1.L.size = 1024;
    t2.serial = 99904; t2.pool = &p2; t2.mem = m2 + 256; t2.L.size = 1024;
    CHECK(!tex_storage_overlap(&ts, &t1) && !tex_storage_overlap(&t1, &ts), "a sparse pool with nothing mapped shares no storage");
    map_req one = {.phys=(NVNmemoryPool *)&p1, .size=len};
    CHECK(h_nvnMemoryPoolMapVirtual((NVNmemoryPool *)&sparse, 1, (const NVNmappingRequest *)&one), "pages of the first pool mapped");
    CHECK(tex_storage_overlap(&ts, &t1) && tex_storage_overlap(&t1, &ts), "a sparse texture and one in the physical pool its pool has pages of may share storage");
    CHECK(tex_storage_overlap(&ts2, &t1), "whatever part of the sparse pool it lies in");
    CHECK(!tex_storage_overlap(&ts, &t2) && !tex_storage_overlap(&t2, &ts), "a sparse texture and one in a pool its pool has no page of share none");
    CHECK(!tex_storage_overlap(&t1, &t2), "two textures of different physical pools share none");
    CHECK(tex_storage_overlap(&ts, &ts2), "two textures in sparse pools may share any page");
    map_req two = {.phys=(NVNmemoryPool *)&p2, .voff=len, .size=len};
    CHECK(h_nvnMemoryPoolMapVirtual((NVNmemoryPool *)&sparse, 1, (const NVNmappingRequest *)&two), "pages of the second pool mapped");
    CHECK(tex_storage_overlap(&ts, &t2) && tex_storage_overlap(&t2, &ts), "once the pool has pages of the second pool they may share storage");
    map_req gone = {.voff=len, .size=len};
    CHECK(h_nvnMemoryPoolMapVirtual((NVNmemoryPool *)&sparse, 1, (const NVNmappingRequest *)&gone), "those pages unmapped");
    CHECK(tex_storage_overlap(&ts, &t2), "an unmapping takes nothing back");
    h_nvnMemoryPoolFinalize((NVNmemoryPool *)&sparse);
    CHECK(!tex_storage_overlap(&ts, &t2) && !tex_storage_overlap(&ts, &t1), "with the sparse pool finalized its range is one like any other");
    h_nvnMemoryPoolFinalize((NVNmemoryPool *)&p1); h_nvnMemoryPoolFinalize((NVNmemoryPool *)&p2);
    munmap(m1, len); munmap(m2, len);
}
static void sparse_copies(void) {
    const size_t n = 256, len = 4 * getpagesize();
    uint8_t *mem = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    uint8_t *io = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    CHECK(mem != MAP_FAILED && io != MAP_FAILED, "sparse test storage allocated");
    if (mem == MAP_FAILED || io == MAP_FAILED) abort();
    pool_t physical, sparse;
    pool_builder_t pb = {.mem=mem, .size=len, .flags=0x24};
    CHECK(h_nvnMemoryPoolInitialize((NVNmemoryPool *)&physical, (const NVNmemoryPoolBuilder *)&pb), "physical pool initialized");
    pb = (pool_builder_t){.size=DM_GAME_APP_POOL + 2 * len, .flags=0x200};
    CHECK(h_nvnMemoryPoolInitialize((NVNmemoryPool *)&sparse, (const NVNmemoryPoolBuilder *)&pb), "sparse pool initialized");
    map_req maps[] = {{.phys=(NVNmemoryPool *)&physical, .size=len}, {.phys=(NVNmemoryPool *)&physical, .voff=len, .size=len}};
    CHECK(h_nvnMemoryPoolMapVirtual((NVNmemoryPool *)&sparse, 2, (const NVNmappingRequest *)maps), "two sparse aliases mapped");
    mtl_pool_add(io, len);
    CHECK(sparse.mem != mem, "sparse pool has a distinct guest address");
    mem[0] = 0x51; CHECK(sparse.mem[0] == 0x51 && sparse.mem[len] == 0x51, "sparse mappings share physical bytes");
    // Both dependency directions and two virtual aliases; separate encoders also
    // exercise the producer and consumer barriers at encoder boundaries.
    for (int split = 0; split < 2; split++) for (int direction = 0; direction < 3; direction++) for (int op = 0; op < 4; op++) {
        memset(mem, 0, len); memset(io, 0, len);
        uint32_t value = op == 3 ? 0x78563412 : 0x6d6d6d6d;
        for (size_t i = 0; i < n; i += 4) memcpy(io + i, &value, 4);
        uint64_t dst = (uint64_t)(direction == 0 ? mem : sparse.mem);
        uint64_t src = (uint64_t)(direction == 1 ? mem : sparse.mem + (direction == 2 ? len : 0));
        mtl_sub_begin();
        if (op == 0) mtl_sub_copy((uint64_t)io, dst, n);
        else if (op == 1) mtl_sub_update(io, dst, n);
        else mtl_sub_fill(dst, n, value);
        if (split) ubd_land_compute();
        if (split && g_blit) { enc_b_end(g_blit); g_blit = nil; }
        uint64_t before = mtl_blit_barriers();
        mtl_sub_copy(src, (uint64_t)io + 512, n);
        if (!split) CHECK(mtl_blit_barriers() > before, "sparse alias dependency inserts an intra-encoder barrier");
        finish(); bytes(io + 512, io, n, "sparse alias consumer reads the preceding copy/update/fill");
    }
    // Ordinary non-overlapping buffers keep their existing batching.
    mtl_sub_begin(); uint64_t before = mtl_blit_barriers();
    mtl_sub_copy((uint64_t)io, (uint64_t)mem, n);
    mtl_sub_copy((uint64_t)io + 1024, (uint64_t)mem + 1024, n);
    CHECK(mtl_blit_barriers() == before, "independent ordinary copies need no extra barrier"); finish();
    h_nvnMemoryPoolFinalize((NVNmemoryPool *)&sparse); h_nvnMemoryPoolFinalize((NVNmemoryPool *)&physical); mtl_pool_del(io);
    defer_drain(); munmap(mem, len); munmap(io, len);
}
// A shader's writes through one no-copy buffer, read by the next encoder's shader through another over the same memory, while overlapping buffers exist (g_big_n): the end
// barrier of the writing encoder flushes to the device only (m4_end), and the reading encoder's start barrier (enc_c_begin, resource_vis) carries the alias flush
static void shader_alias(void) {
    size_t pg = getpagesize(); NSError *e = nil;
    void *mem = mmap(NULL, pg, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0); if (mem == MAP_FAILED) abort();
    id<MTLBuffer> a = [g_dev newBufferWithBytesNoCopy:mem length:pg options:MTLResourceStorageModeShared deallocator:nil];
    id<MTLBuffer> b = [g_dev newBufferWithBytesNoCopy:mem length:pg options:MTLResourceStorageModeShared deallocator:nil];
    id<MTLBuffer> io = [g_dev newBufferWithLength:pg options:MTLResourceStorageModeShared];
    id<MTLLibrary> l = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void w(device uint *a [[buffer(0)]], constant uint &s [[buffer(2)]], uint i [[thread_position_in_grid]]) { a[i] = s + i; }\n"
        "kernel void r(device const uint *b [[buffer(0)]], device uint *o [[buffer(1)]], uint i [[thread_position_in_grid]]) { o[i] = b[i]; }\n" options:nil error:&e];
    if (!l || !a || !b || !io) { fprintf(stderr, "%s\n", e.localizedDescription.UTF8String); abort(); }
    id<MTLFunction> write_fn = [l newFunctionWithName:@"w"], read_fn = [l newFunctionWithName:@"r"];
    if (!write_fn || !read_fn) abort();
    id<MTLComputePipelineState> pw = [g_dev newComputePipelineStateWithFunction:write_fn error:&e], pr = [g_dev newComputePipelineStateWithFunction:read_fn error:&e];
    if (!pw || !pr) abort();
    id<MTLBuffer> seed = [g_dev newBufferWithLength:16 options:MTLResourceStorageModeShared];
    res_add(a); res_add(b); res_add(io); res_add(seed); atomic_fetch_add(&g_big_n, 1);
    CHECK(resource_vis() & MTL4VisibilityOptionResourceAlias, "overlapping buffers turn on the alias flush");
    for (int round = 0; round < 8; round++) {
        uint32_t s = 0x5a000000u + (uint32_t)round * 0x10000u; *(uint32_t *)seed.contents = s; memset(io.contents, 0, pg);
        mtl_sub_begin();
        id<MTL4ComputeCommandEncoder> c = enc_c_begin(NULL); enc_c_args(c, a.gpuAddress, 0); enc_c_args(c, seed.gpuAddress, 2);
        enc_c_pso(c, pw); enc_c_dispatch(c, MTLSizeMake(pg / 4 / 64, 1, 1), MTLSizeMake(64, 1, 1)); enc_c_end(c);
        c = enc_c_begin(NULL); enc_c_args(c, b.gpuAddress, 0); enc_c_args(c, io.gpuAddress, 1);
        enc_c_pso(c, pr); enc_c_dispatch(c, MTLSizeMake(pg / 4 / 64, 1, 1), MTLSizeMake(64, 1, 1)); enc_c_end(c);
        finish();
        int ok = 1; const uint32_t *o = io.contents; for (size_t i = 0; i < pg / 4; i++) ok &= o[i] == s + (uint32_t)i;
        CHECK(ok, "the next encoder's shader reads a shader's writes through a second no-copy buffer");
    }
    atomic_fetch_sub(&g_big_n, 1); res_remove(a); res_remove(b); res_remove(io); res_remove(seed); a = b = nil; munmap(mem, pg);
}
int main(void) { @autoreleasepool {
    mtl_init(); separate_buffers(); sparse_copies(); sparse_shares(); shader_alias();
    printf("t_copy_alias: %d checks, %d failed\n", checks, failed); return failed != 0;
} }
