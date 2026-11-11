// A memory pool's Finalize costs what the pool holds, and the replay's next pool lookup costs a walk, not a sort (docs/reference/frame-rate.md, "A run of memory pool
// Finalizes held the replay up"):
//   - the address index of the pools is put right after a pool is added or removed, and sorted anew only when it is far out of order (pidx_sort)
//   - the texture IDs registered with a pool's textures are listed by pool: its Finalize marks those gone and looks at no other ID (treg_drop_pool_views)
//   - the view cache is walked only for a pool that has sets in it (vc_drop_pool)
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(label, c) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__); } } while (0)
static uint64_t rnd_s = 12345;
static unsigned rnd(void) { rnd_s = rnd_s * 6364136223846793005ull + 1442695040888963407ull; return (unsigned)(rnd_s >> 33); }

// ---- the address index: NP pools of one page, a page apart
enum { NP = 5238 };   // as many as Mario Kart World keeps while it drives
static uint8_t *g_base; static size_t g_page; static char g_live[NP];
static uint8_t *pool_at(int k) { return g_base + (size_t)k * 2 * g_page; }
static int index_right(void) {   // sorted by start, every table entry once
    pthread_mutex_lock(&g_mu);
    pidx_sort(); int ok = g_pidx_n == g_npool;
    char *seen = calloc((size_t)g_npool + 1, 1);
    for (int i = 0; i < g_npool && ok; i++) { int v = g_pidx[i]; ok = v >= 0 && v < g_npool && !seen[v] && (!i || g_pools[g_pidx[i - 1]].lo <= g_pools[v].lo); if (ok) seen[v] = 1; }
    free(seen);
    pthread_mutex_unlock(&g_mu);
    return ok;
}
static int finds(int k) {   // pool k is found at its address while it lives and not after, the page after it never
    uint64_t a = (uint64_t)(uintptr_t)pool_at(k);
    pthread_mutex_lock(&g_mu);
    int i = pool_find(a + 64, 256), gap = pool_find(a + g_page + 64, 256);
    int ok = gap < 0 && (g_live[k] ? i >= 0 && g_pools[i].lo == (uintptr_t)a : i < 0);
    pthread_mutex_unlock(&g_mu);
    return ok;
}
static void pool_put(int k) { mtl_pool_add(pool_at(k), g_page); g_live[k] = 1; }
static void pool_take(int k) { mtl_pool_del(pool_at(k)); g_live[k] = 0; }
static int pick(int live) { int k; do k = (int)(rnd() % NP); while (g_live[k] != live); return k; }

int main(void) { @autoreleasepool {
    mtl_init();
    g_page = (size_t)getpagesize();
    g_base = mmap(NULL, (size_t)NP * 2 * g_page, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0); if (g_base == MAP_FAILED) abort();
    int *order = malloc(NP * sizeof *order); for (int i = 0; i < NP; i++) order[i] = i;
    for (int i = NP - 1; i > 0; i--) { int j = (int)(rnd() % (unsigned)(i + 1)), t = order[i]; order[i] = order[j]; order[j] = t; }   // addresses in no order, as an allocator hands them out
    for (int i = 0; i < NP; i++) pool_put(order[i]);
    free(order);
    CHECK("the index of all the pools is sorted and whole", index_right());
    int ok = 1; for (int i = 0; i < NP; i += 37) ok &= finds(i);
    CHECK("a pool is found at its address and the page after it is not", ok);

    // One pool goes and the next lookup puts the index right: 200 times, and it is never sorted anew
    uint64_t anew0 = g_pidx_anew, sorts0 = g_pidx_sorts; ok = 1;
    for (int n = 0; n < 200; n++) { int k = pick(1); pool_take(k); ok &= finds(k) && finds(pick(1)); }
    CHECK("after each removal the removed pool is not found and another one is", ok);
    CHECK("each removal made the next lookup put the index right, once", g_pidx_sorts - sorts0 == 200);
    CHECK("no removal had the index sorted anew", g_pidx_anew == anew0);
    CHECK("the index is sorted and whole after the removals", index_right());
    anew0 = g_pidx_anew; ok = 1;
    for (int n = 0; n < 200; n++) { int k = pick(0); pool_put(k); ok &= finds(k) && finds(pick(1)); }
    CHECK("after each addition the new pool is found", ok);
    CHECK("no addition had the index sorted anew", g_pidx_anew == anew0);
    CHECK("the index is sorted and whole after the additions", index_right());
    // Many changes between two lookups: sorted anew, once
    anew0 = g_pidx_anew;
    for (int n = 0; n < 1500; n++) pool_take(pick(1));
    for (int n = 0; n < 1500; n++) pool_put(pick(0));
    ok = 1; for (int i = 0; i < NP; i += 11) ok &= finds(i);
    CHECK("after 3,000 changes with no lookup between them every pool is found", ok);
    CHECK("that index was sorted anew, once", g_pidx_anew == anew0 + 1);
    CHECK("and is sorted and whole", index_right());
    {   // what a lookup after one removal costs (printed, not checked): put right, against sorted anew as it was
        uint64_t right_ns = 0, anew_ns = 0;
        for (int n = 0; n < 50; n++) {
            pool_take(pick(1));
            pthread_mutex_lock(&g_mu); uint64_t t0 = bp_now(); pidx_sort(); right_ns += bp_now() - t0; pthread_mutex_unlock(&g_mu);
        }
        pthread_mutex_lock(&g_mu);
        for (int n = 0; n < 50; n++) { uint64_t t0 = bp_now(); for (int i = 0; i < g_npool; i++) g_pidx[i] = i; qsort(g_pidx, (size_t)g_npool, sizeof *g_pidx, pidx_cmp); anew_ns += bp_now() - t0; }
        pthread_mutex_unlock(&g_mu);
        printf("  the index of %d pools after one removal: put right in %.1f us, sorted anew in %.1f us\n", g_npool, right_ns / 50e3, anew_ns / 50e3);
        for (int n = 0; n < 50; n++) pool_put(pick(0));
    }

    // ---- texture IDs by pool: registrations, removals and Finalizes at random against a model of what the walk over every ID did
    enum { NPOOL = 6, NID = 300 };
    static pool_t pl[NPOOL]; static tex_t tx[NID]; static int m_ok[NID], m_pool[NID], m_gone[NID];
    uint64_t serial = 1ull << 40; int seen_ok = 1, nfin = 0; ok = 1;
    for (int step = 0; step < 8000; step++) {
        unsigned r = rnd() % 100; int id = 1 + (int)(rnd() % (NID - 1));
        if (r < 60) {   // a texture into the ID: one of some pool, or one time in five the texture it holds again
            if (!(m_ok[id] && rnd() % 5 == 0)) { tx[id] = (tex_t){0}; tx[id].pool = &pl[rnd() % NPOOL]; tx[id].serial = serial++; tx[id].d.width = tx[id].d.height = 4; }
            mtl_reg_tex(id, &tx[id], NULL); m_ok[id] = 1; m_pool[id] = (int)(tx[id].pool - pl); m_gone[id] = 0;
        } else if (r < 75) { mtl_reg_tex(id, NULL, NULL); m_ok[id] = 0; m_gone[id] = 0; }
        else if (r < 80) {   // a pool's Finalize: its IDs are gone, and it looked at those only
            int p = (int)(rnd() % NPOOL), want = 0; for (int i = 0; i < NID; i++) if (m_ok[i] && m_pool[i] == p) { want++; m_gone[i] = 1; }
            uint64_t seen0 = g_treg_pool_seen; mtl_alias_drop_pool(&pl[p]); seen_ok &= g_treg_pool_seen - seen0 == (uint64_t)want; nfin++;
        } else continue;
        os_unfair_lock_lock(&g_rmu);
        for (int i = 1; i < NID && i < g_ntreg; i++) ok &= g_treg[i].ok == m_ok[i] && (!m_ok[i] || g_treg[i].gone == m_gone[i]);
        os_unfair_lock_unlock(&g_rmu);
    }
    CHECK("after every step each ID is registered and gone as the walk over every ID left it", ok);
    CHECK("each Finalize looked at the IDs of its pool and at no other", seen_ok && nfin > 100);
    {   // an ID is listed once however often its texture is registered
        static pool_t once; tex_t t = {0}; t.pool = &once; t.serial = serial++; t.d.width = t.d.height = 4;
        for (int n = 0; n < 3; n++) mtl_reg_tex(NID, &t, NULL);
        uint64_t seen0 = g_treg_pool_seen; mtl_alias_drop_pool(&once);
        CHECK("an ID registered three times with one texture is looked at once", g_treg_pool_seen - seen0 == 1 && g_treg[NID].gone);
        mtl_reg_tex(NID, &t, NULL);
        CHECK("registered again, it is not gone", !g_treg[NID].gone);
        seen0 = g_treg_pool_seen; mtl_alias_drop_pool(&once);
        CHECK("and its pool's next Finalize finds it", g_treg_pool_seen - seen0 == 1 && g_treg[NID].gone);
        mtl_reg_tex(NID, NULL, NULL);
        seen0 = g_treg_pool_seen; mtl_alias_drop_pool(&once);
        CHECK("an emptied ID is in no pool's list", g_treg_pool_seen == seen0);
    }
    {   // registrations of one pool's textures in a row ask the table of the lists once, and once more when the list's first ID goes
        static pool_t ring; tex_t t = {0}; t.pool = &ring; t.d.width = t.d.height = 4; enum { R0 = 1000, RN = 1000 };
        uint64_t asks0 = g_treg_pool_asks;
        for (int n = 0; n < 5 * RN; n++) { t.serial = serial++; mtl_reg_tex(R0 + n % RN, &t, NULL); }   // five times round a ring of 1,000 IDs, a new texture each time
        CHECK("5,000 registrations of one pool's textures asked the table of the lists once", g_treg_pool_asks - asks0 == 1);
        uint64_t seen0 = g_treg_pool_seen; mtl_alias_drop_pool(&ring);
        CHECK("and the pool's Finalize finds the ring's 1,000 IDs", g_treg_pool_seen - seen0 == RN);
        for (int n = 0; n < RN; n++) mtl_reg_tex(R0 + n, NULL, NULL);
        seen0 = g_treg_pool_seen; mtl_alias_drop_pool(&ring);
        CHECK("emptied, none", g_treg_pool_seen == seen0 && !nvn_hm_get(&g_treg_pool, &(uint64_t){(uint64_t)(uintptr_t)&ring}));
    }
    {   // as many IDs as Mario Kart World's texture pool has, over 64 pools: a pool with no ID looks at none, a pool with three at three
        enum { BIG = 131072 }; static pool_t many[64], none, three; tex_t t = {0}; t.d.width = t.d.height = 4;
        for (int i = NID + 1; i < BIG; i++) { t.pool = &many[i % 64]; t.serial = serial++; mtl_reg_tex(i, &t, NULL); }
        for (int i = 0; i < 3; i++) { t.pool = &three; t.serial = serial++; mtl_reg_tex(BIG + i, &t, NULL); }
        uint64_t seen0 = g_treg_pool_seen, t0 = bp_now(); mtl_alias_drop_pool(&none); uint64_t ns = bp_now() - t0;
        CHECK("the Finalize of a pool with no ID looks at none of 131,072", g_treg_pool_seen == seen0);
        printf("  the Finalize of a pool with nothing registered, %d IDs registered: %.1f us\n", g_ntreg, ns / 1e3);
        mtl_alias_drop_pool(&three);
        CHECK("the Finalize of a pool with three IDs looks at three", g_treg_pool_seen == seen0 + 3 && g_treg[BIG].gone && g_treg[BIG + 1].gone && g_treg[BIG + 2].gone);
        CHECK("and leaves another pool's IDs", !g_treg[BIG - 1].gone && g_treg[BIG - 1].ok);
        seen0 = g_treg_pool_seen; mtl_alias_drop_pool(&many[5]);
        int want = 0, gone = 0, others = 0; for (int i = NID + 1; i < BIG; i++) { if (i % 64 == 5) { want++; gone += g_treg[i].gone; } else others += g_treg[i].gone; }
        CHECK("a pool with some 2,000 IDs: all of them gone, no other", want > 2000 && gone == want && !others && g_treg_pool_seen - seen0 == (uint64_t)want);
    }

    // ---- the view cache by pool
    {
        static tex_t va[3], vb[2]; uint64_t vs = 1ull << 41;
        pthread_mutex_lock(&g_smu);
        for (int i = 0; i < 3; i++) { va[i].serial = vs++; nvn_hm_put(&g_tex_live, &va[i].serial, &va[i]); }
        for (int i = 0; i < 2; i++) { vb[i].serial = vs++; nvn_hm_put(&g_tex_live, &vb[i].serial, &vb[i]); }
        pthread_mutex_unlock(&g_smu);
        uint64_t ka = (uint64_t)(uintptr_t)&pl[0], kb = (uint64_t)(uintptr_t)&pl[1], kc = (uint64_t)(uintptr_t)&pl[2];
        os_unfair_lock_lock(&g_rmu);
        unsigned n0 = g_vc.n;
        for (int i = 0; i < 3; i++) vc_set_for(va[i].serial, &pl[0]);
        for (int i = 0; i < 2; i++) vc_set_for(vb[i].serial, &pl[1]);
        int made = g_vc.n == n0 + 5 && (intptr_t)nvn_hm_get(&g_vc_pools, &ka) == 3 && (intptr_t)nvn_hm_get(&g_vc_pools, &kb) == 2 && !nvn_hm_get(&g_vc_pools, &kc);
        vc_set_for(va[0].serial, &pl[0]);
        int again = g_vc.n == n0 + 5 && (intptr_t)nvn_hm_get(&g_vc_pools, &ka) == 3;
        vc_drop_pool(&pl[2]); int none = g_vc.n == n0 + 5;
        vc_drop_pool(&pl[0]); int one = g_vc.n == n0 + 2 && !nvn_hm_get(&g_vc_pools, &ka) && (intptr_t)nvn_hm_get(&g_vc_pools, &kb) == 2;
        os_unfair_lock_unlock(&g_rmu);
        mtl_vc_drop(vb[0].serial);
        os_unfair_lock_lock(&g_rmu);
        int tex = g_vc.n == n0 + 1 && (intptr_t)nvn_hm_get(&g_vc_pools, &kb) == 1;
        nvn_hm_clear(&g_vc, vc_set_free); int all = !g_vc.n && !g_vc_pools.n;
        os_unfair_lock_unlock(&g_rmu);
        CHECK("view cache sets are counted by their texture's pool", made);
        CHECK("a texture's set is made and counted once", again);
        CHECK("the Finalize of a pool with no set leaves the cache", none);
        CHECK("the Finalize of a pool drops its sets and no other pool's", one);
        CHECK("a finalized texture's set leaves its pool's count", tex);
        CHECK("clearing the cache clears the counts", all);
        pthread_mutex_lock(&g_smu);
        for (int i = 0; i < 3; i++) nvn_hm_del(&g_tex_live, &va[i].serial);
        for (int i = 0; i < 2; i++) nvn_hm_del(&g_tex_live, &vb[i].serial);
        pthread_mutex_unlock(&g_smu);
    }

    for (int k = 0; k < NP; k++) if (g_live[k]) pool_take(k);
    mtl_drain();
    printf("t_pool_finalize: %d checks, %d failed\n", checks, failed);
    return failed != 0;
} }
