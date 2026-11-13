#include "nvn_capture.h"
#include "nvn_hmap.h"

void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *);

// Ready continuations of NVN queues share the renderer's one ordered Metal queue.
// An unresolved wait parks its queue, never the submitting CPU or another queue.
typedef struct nq_receipt { unsigned refs, published; uint64_t fence, present, copy; } nq_receipt;   // present, copy: a present's display ticket and its snapshot copy (mtl_present)
typedef struct nq_signal { volatile uint32_t *event; unsigned mode; uint32_t value; } nq_signal;
typedef struct nq_node {
    struct nq_node *next;
    uint8_t *bytes; size_t length, capacity;
    unsigned kind, mode, closed, waiting; volatile uint32_t *event; uint32_t value;
    uint64_t wait_fence, event_predecessor; unsigned wait_kind; const sync_t *sync_source; nq_receipt *receipt;
    nq_signal *signals; unsigned signal_count;   // NQ_COMMANDS: every event signal it records, in order (nq_event_issued at its commit)
    tex_t texture; double period; int crop[4];
} nq_node;
typedef struct nq_owned { struct nq_owned *next, *pnext; const void *psrc; unsigned kind; uint64_t data[]; } nq_owned;   // pnext, psrc: a program whose snapshot waits for the submission lock (nq_resolve)
typedef struct nq_job { struct nq_job *next; nq_node *first, *last; nq_receipt *receipt; nq_owned *owned; nvn_hmap objects; uint64_t frame;
    nq_node *sfirst, *slast; nq_owned *pend; void *owner; int open, queued, waits, held, late; unsigned tick; } nq_job;   // sfirst..slast: the nodes its submit call is still copying (the worker sees first..last);
    // pend: programs to snapshot; owner: its queue_t; open: more nodes will come; queued: it is in its queue; held: the submit call holds the submission lock throughout (DM_NVN_SUBMIT_STREAM=0);
    // late: finished nodes are still with the submit call, the lock was busy at their cut (nq_late)
static void nq_job_free(nq_job *j) {
    for(nq_owned *o=j->owned,*next;o;o=next) { next=o->next; if(o->kind==CAP_K_PROG) mtl_prog_unpin((prog_t *)o->data); else if(o->kind==CAP_K_TEX) mtl_tex_unpin(((tex_t *)o->data)->serial); free(o); }
    free(j->objects.keys); free(j->objects.vals); free(j);
}
static int nq_snapshot_address(void *ctx,uint64_t *field,uint64_t len,int writable) { (void)ctx;(void)field;(void)len;(void)writable;return 1; }
static int nq_snapshot_object(void *ctx,int kind,uint64_t *field,uint8_t *payload,uint32_t size) {
    (void)payload;(void)size; nq_job *j=ctx; if(!*field || (kind!=CAP_K_PROG && kind!=CAP_K_TEX)) return 1;
    uint64_t key[2]={*field,(unsigned)kind}; nq_owned *o=nvn_hm_get(&j->objects,key);
    if(!o) {
        size_t bytes=kind==CAP_K_PROG?sizeof(prog_t):sizeof(tex_t); o=calloc(1,sizeof *o+bytes); if(!o) die("queue descriptor allocation failed");
        o->kind=kind; o->next=j->owned; j->owned=o;
        if(kind==CAP_K_PROG) {   // prog_get and the program pins belong to the submission lock: at once when the call holds it, else at the next cut (nq_resolve)
            if(j->held) mtl_prog_snapshot((prog_t *)o->data,(const prog_t *)(uintptr_t)*field);
            else { o->psrc=(const void *)(uintptr_t)*field; o->pnext=j->pend; j->pend=o; }
        } else { memcpy(o->data,(const void *)(uintptr_t)*field,bytes); mtl_tex_pin(((tex_t *)o->data)->serial); }
        nvn_hm_put(&j->objects,key,o);
    }
    *field=(uintptr_t)o->data;return 1;
}
static const cap_ops nq_snapshot_ops={nq_snapshot_address,nq_snapshot_object};
typedef struct nq_queue {
    struct nq_queue *next; uint64_t serial, physical, present, copy; int origin;
    nq_job *first, *last; nq_receipt *tail;
} nq_queue;
static pthread_mutex_t nq_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t nq_cv = PTHREAD_COND_INITIALIZER;
static pthread_once_t nq_once = PTHREAD_ONCE_INIT;
static nq_queue *nq_queues;
static int nq_test_held;   // nvn_queue_test_hold: replay takes no queued work while set (unit tests only)
// The last GPU write of each event word not yet landed: its submission's fence, and for a WRITE signal the value it leaves (exact). A wait the queued value satisfies needs no
// completion: its continuation is encoded after the writer's on the one ordered Metal queue, as the next submission of one NVN queue is, and memory the writer's completion lands
// on the CPU (reports, render-target readbacks) is that same in-flight case. An ADD's result depends on the writes landing before it, so such a wait still waits for them
typedef struct nq_event_write { struct nq_event_write *next; volatile uint32_t *word; uint64_t fence; uint32_t value; int exact; } nq_event_write;
static nq_event_write *nq_event_writes;
static uint64_t nq_event_pending(volatile uint32_t *word) { for(nq_event_write *w=nq_event_writes;w;w=w->next) if(w->word==word) return w->fence; return 0; }
static nq_event_write *nq_event_write_of(volatile uint32_t *word) { nq_event_write *w=nq_event_writes; while(w && w->word!=word) w=w->next; return w; }
static void nq_event_issued(volatile uint32_t *word,uint64_t fence,unsigned mode,uint32_t value) {
    nq_event_write *w=nq_event_write_of(word);
    if(!w) { w=calloc(1,sizeof *w); if(!w) die("event ordering allocation failed"); w->word=word; w->next=nq_event_writes; nq_event_writes=w; }
    w->fence=fence; w->value=value; w->exact=mode==0;
}

enum { NQ_COMMANDS, NQ_EVENT, NQ_SYNC, NQ_FENCE, NQ_PRESENT };
static nq_receipt *nq_new(void) { nq_receipt *r=calloc(1,sizeof *r); if(!r) die("queue receipt allocation failed"); r->refs=1; return r; }
static void nq_put(nq_receipt *r) { if(r && !--r->refs) free(r); }
static void nq_set_sync(sync_t *s,nq_receipt *r) { if(s->fenced==3) nq_put((nq_receipt *)(uintptr_t)s->fence); r->refs++; s->fence=(uintptr_t)r; s->fenced=3; }
void nvn_sync_release(sync_t *s) { pthread_mutex_lock(&nq_mu); if(s->fenced==3) nq_put((nq_receipt *)(uintptr_t)s->fence); s->fenced=0; s->fence=0; pthread_mutex_unlock(&nq_mu); }
static nq_queue *nq_get(queue_t *q) {
    nq_queue *p=nq_queues; while(p && p->serial!=q->serial) p=p->next;
    if(!p) { p=calloc(1,sizeof *p); if(!p) die("queue state allocation failed"); p->serial=q->serial; p->origin=q->origin_ll; p->next=nq_queues; nq_queues=p; }
    return p;
}
static void nq_publish(nq_receipt *r,uint64_t fence) { r->fence=fence; r->published=1; pthread_cond_broadcast(&nq_cv); }
static int nq_predicate(uint32_t current,unsigned mode,uint32_t target) { return mode==0 ? current==target : (uint32_t)(current-target)<0x80000000u; }
static int nq_sync_encoded(const sync_t *s,uint64_t *fence) {
    if(s->fenced==3) { nq_receipt *r=(nq_receipt *)(uintptr_t)s->fence; if(!r->published) return 0; *fence=r->fence; return 1; }
    if(!s->fenced) return 0; *fence=s->fence; return 1;
}
void nvn_queue_gpu_progress(void) {
    pthread_mutex_lock(&nq_mu); uint64_t done=mtl_completed_fence(); nq_event_write **p=&nq_event_writes;
    while(*p) { nq_event_write *w=*p; if(w->fence<=done) { *p=w->next; free(w); } else p=&w->next; }
    pthread_cond_broadcast(&nq_cv); pthread_mutex_unlock(&nq_mu);
}
static void nq_event_publish(volatile uint32_t *word,unsigned mode,uint32_t value,uint64_t gpu_fence) {
    pthread_mutex_lock(&nq_mu);
    if(mode==1) atomic_fetch_add_explicit((_Atomic uint32_t *)word,value,memory_order_release);
    else atomic_store_explicit((_Atomic uint32_t *)word,value,memory_order_release);
    atomic_thread_fence(memory_order_seq_cst);
    // Latch waits already reached: a subsequent signal must not erase a release.
    for(nq_queue *q=nq_queues;q;q=q->next) if(q->first && q->first->first) {
        nq_node *n=q->first->first;
        if(n->kind==NQ_EVENT && n->waiting && n->event==word && (gpu_fence ? gpu_fence>=n->event_predecessor : nq_event_pending(word)<=mtl_completed_fence()) && nq_predicate(atomic_load_explicit((_Atomic uint32_t *)word,memory_order_acquire),n->mode,n->value)) { n->event=NULL; n->wait_fence=gpu_fence; }
    }
    pthread_cond_broadcast(&nq_cv); pthread_mutex_unlock(&nq_mu);
}
void nvn_event_publish(volatile uint32_t *word,unsigned mode,uint32_t value) { nq_event_publish(word,mode,value,0); }
void nvn_event_publish_gpu(volatile uint32_t *word,unsigned mode,uint32_t value,uint64_t fence) { nq_event_publish(word,mode,value,fence); }
static void nq_snapshot_sync(nq_node *n,const sync_t *s) {
    n->wait_kind=s->fenced; n->wait_fence=s->fence;
    if(s->fenced==3) { n->receipt=(nq_receipt *)(uintptr_t)s->fence; n->receipt->refs++; }
}
typedef struct { uint64_t wall, cpu, instr, cycles, sys; } nq_cost;
static nq_cost nq_cost_begin(void) {
    nq_cost c={.wall=now_ns(),.cpu=clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID),.sys=thr_sys_ns()};
    thr_counts(&c.instr,&c.cycles); return c;
}
static void nq_cost_end(nq_cost c) {
    uint64_t dw=now_ns()-c.wall, dc=clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)-c.cpu, ins, cyc; thr_counts(&ins,&cyc);
    atomic_fetch_add(&g_nvn_ns,dw); atomic_fetch_add(&g_sub_wall_ns,dw); atomic_fetch_add(&g_cum_sub_wall_ns,dw);
    atomic_fetch_add(&g_sub_cpu_ns,dc); atomic_fetch_add(&g_cum_sub_cpu_ns,dc);
    atomic_fetch_add(&g_sub_instr,ins-c.instr); atomic_fetch_add(&g_cum_sub_instr,ins-c.instr);
    atomic_fetch_add(&g_cum_sub_cyc,cyc-c.cycles); atomic_fetch_add(&g_cum_sub_sys_ns,thr_sys_ns()-c.sys);
}
// DM_SUBPROF=<ms>[,all] (diagnostic): what the submissions of a long frame were doing. Once the queue worker's replays of one frame (commands and presents) have run for longer
// than <ms> in all, a helper thread takes the worker's stack every 0.4 ms (suspend, registers, frame-pointer chain, resume: nothing else between the two, so no lock the worker
// holds is asked for), and when a replay ends the worker logs the stacks taken in it, innermost frame first, equal stacks in a row counted. A stack that waits for a lock
// (__ulock_wait2: an os_unfair_lock; __psynch_mutexwait: a pthread mutex) names the lock and is followed by the stack of the thread that holds it, taken at once: the kernel
// call's arguments, still in the registers, say which thread that is. With ",all" every other thread that is running at that moment gives its stack too, logged by thread and
// stack, the most frequent first. Other threads' stacks are read through the kernel, so a bad frame pointer ends the walk. A frame that takes 50 ms once in half a minute cannot
// be told from the 2,000 ordinary ones in a sampler's totals; here only the long one is looked at, with the time into the frame's replays of every stack
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <os/lock.h>
enum { SP_DEPTH = 20, SP_MAX = 400, SP_ODEPTH = 12, SP_OMAX = 512 };
typedef struct { uint32_t n; uint64_t tid, pc[SP_ODEPTH]; char name[32]; } sp_stack;   // another thread's
static double sp_ms = -1; static int sp_all; static _Atomic uint64_t sp_t0; static uint64_t sp_acc, sp_frame = ~0ull; static thread_act_t sp_port; static pthread_t sp_pth;
static os_unfair_lock sp_lock = OS_UNFAIR_LOCK_INIT; static uintptr_t sp_ulock, sp_mwait;
static struct { uint32_t us, n; uint64_t pc[SP_DEPTH], lock; sp_stack own; } sp_s[SP_MAX]; static int sp_n;
static struct { sp_stack s; uint32_t count; } sp_o[SP_OMAX]; static int sp_on; static uint32_t sp_olost;
static int sp_take(thread_act_t t, sp_stack *o) {   // the stack of a thread other than the worker
    o->n = 0; o->name[0] = 0; o->tid = 0;
    if (thread_suspend(t) != KERN_SUCCESS) return 0;
    arm_thread_state64_t st; mach_msg_type_number_t cnt = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(t, ARM_THREAD_STATE64, (thread_state_t)&st, &cnt) == KERN_SUCCESS) {
        o->pc[o->n++] = (uint64_t)arm_thread_state64_get_pc(st); o->pc[o->n++] = (uint64_t)arm_thread_state64_get_lr(st);
        uint64_t fp = (uint64_t)arm_thread_state64_get_fp(st), f[2]; mach_vm_size_t got = 0;
        while (o->n < SP_ODEPTH && fp && !(fp & 7) && mach_vm_read_overwrite(mach_task_self(), fp, 16, (mach_vm_address_t)(uintptr_t)f, &got) == KERN_SUCCESS && got == 16 && f[1]) {
            o->pc[o->n++] = f[1]; if (f[0] <= fp) break; fp = f[0]; }
    }
    thread_resume(t);
    thread_identifier_info_data_t ii; mach_msg_type_number_t c = THREAD_IDENTIFIER_INFO_COUNT;
    if (thread_info(t, THREAD_IDENTIFIER_INFO, (thread_info_t)&ii, &c) == KERN_SUCCESS) o->tid = ii.thread_id;
    thread_extended_info_data_t xi; c = THREAD_EXTENDED_INFO_COUNT;
    if (thread_info(t, THREAD_EXTENDED_INFO, (thread_info_t)&xi, &c) == KERN_SUCCESS) snprintf(o->name, sizeof o->name, "%s", xi.pth_name);
    return o->n > 0;
}
// The lock's owner (by its thread port for an os_unfair_lock, by its thread ID for a pthread mutex) into *own, and with DM_SUBPROF=…,all every running thread into sp_o
static void sp_others(thread_act_t self, sp_stack *own, thread_act_t owner, uint64_t owner_tid) {
    if (owner != MACH_PORT_NULL && !sp_all) { sp_take(owner, own); return; }
    thread_act_array_t th; mach_msg_type_number_t nth;
    if (task_threads(mach_task_self(), &th, &nth) != KERN_SUCCESS) return;
    for (mach_msg_type_number_t i = 0; i < nth; i++) {
        thread_act_t t = th[i];
        if (t != self && t != sp_port) {
            mach_msg_type_number_t c; int is_owner = owner != MACH_PORT_NULL && t == owner;
            if (!is_owner && owner_tid) { thread_identifier_info_data_t ii; c = THREAD_IDENTIFIER_INFO_COUNT; is_owner = thread_info(t, THREAD_IDENTIFIER_INFO, (thread_info_t)&ii, &c) == KERN_SUCCESS && ii.thread_id == owner_tid; }
            thread_basic_info_data_t bi; c = THREAD_BASIC_INFO_COUNT;
            int running = sp_all && thread_info(t, THREAD_BASIC_INFO, (thread_info_t)&bi, &c) == KERN_SUCCESS && bi.run_state == TH_STATE_RUNNING;
            sp_stack st;
            if ((is_owner || running) && sp_take(t, &st)) {
                if (is_owner) *own = st;
                if (running) {
                    int k = 0; while (k < sp_on && !(sp_o[k].s.tid == st.tid && sp_o[k].s.n == st.n && !memcmp(sp_o[k].s.pc, st.pc, st.n * sizeof *st.pc))) k++;
                    if (k < sp_on) sp_o[k].count++; else if (sp_on < SP_OMAX) { sp_o[sp_on].s = st; sp_o[sp_on++].count = 1; } else sp_olost++;
                }
            }
        }
        mach_port_deallocate(mach_task_self(), t);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)th, nth * sizeof *th);
}
static void *sp_main(void *unused) {
    (void)unused; pthread_setname_np("submission profiler");
    uint64_t limit = (uint64_t)(sp_ms * 1e6);
    uintptr_t hi = (uintptr_t)pthread_get_stackaddr_np(sp_pth), lo = hi - pthread_get_stacksize_np(sp_pth);
    thread_act_t self = mach_thread_self();
    for (;;) {
        usleep(400);
        uint64_t t0 = atomic_load(&sp_t0), now = now_ns();
        if (!t0 || now < t0 || now - t0 < limit) continue;
        os_unfair_lock_lock(&sp_lock);
        if (atomic_load(&sp_t0) == t0 && sp_n < SP_MAX && thread_suspend(sp_port) == KERN_SUCCESS) {
            arm_thread_state64_t st; mach_msg_type_number_t cnt = ARM_THREAD_STATE64_COUNT; __typeof__(sp_s[0]) *x = NULL; thread_act_t owner = MACH_PORT_NULL; uint64_t owner_tid = 0;
            if (thread_get_state(sp_port, ARM_THREAD_STATE64, (thread_state_t)&st, &cnt) == KERN_SUCCESS) {
                x = &sp_s[sp_n++]; x->us = (uint32_t)((now - t0) / 1000); x->n = 0; x->lock = 0; x->own.n = 0;
                uintptr_t pc = (uintptr_t)arm_thread_state64_get_pc(st);
                x->pc[x->n++] = pc; x->pc[x->n++] = (uint64_t)arm_thread_state64_get_lr(st);
                uintptr_t fp = (uintptr_t)arm_thread_state64_get_fp(st);
                while (x->n < SP_DEPTH && fp >= lo && fp + 16 <= hi && !(fp & 7)) {
                    const uint64_t *f = (const uint64_t *)fp; if (!f[1]) break;
                    x->pc[x->n++] = f[1]; if ((uintptr_t)f[0] <= fp) break; fp = (uintptr_t)f[0]; }
                // In the kernel call that waits for a lock the arguments are still in the registers: an os_unfair_lock's word (the value waited on) is its owner's thread port
                // with bit 0 cleared once somebody waits; a pthread mutex's wait names its owner's thread ID
                if (sp_ulock && pc - sp_ulock < 16) { x->lock = st.__x[1]; owner = (thread_act_t)(st.__x[2] | 1); }
                else if (sp_mwait && pc - sp_mwait < 16) { x->lock = st.__x[0]; owner_tid = st.__x[3]; }
            }
            thread_resume(sp_port);
            if (x && (owner != MACH_PORT_NULL || owner_tid || sp_all)) sp_others(self, &x->own, owner, owner_tid);
        }
        os_unfair_lock_unlock(&sp_lock);
    }
    return NULL;
}
static void sp_begin(uint64_t frame) {
    if (sp_ms < 0) { const char *e = getenv("DM_SUBPROF"); sp_ms = e ? atof(e) : 0; sp_all = e && strstr(e, "all");
        if (sp_ms > 0) { sp_port = mach_thread_self(); sp_pth = pthread_self(); sp_ulock = (uintptr_t)dlsym(RTLD_DEFAULT, "__ulock_wait2"); sp_mwait = (uintptr_t)dlsym(RTLD_DEFAULT, "__psynch_mutexwait");
            pthread_t t; if (pthread_create(&t, NULL, sp_main, NULL)) sp_ms = 0; else { pthread_detach(t);
            LOG("[subprof] stacks of the queue worker once a frame's replays have run longer than %.1f ms%s (DM_SUBPROF); lock owners are %s", sp_ms, sp_all ? ", and of every running thread" : "",
                sp_ulock && sp_mwait ? "named" : "not named (the kernel call stubs were not found)"); } } }
    if (sp_ms <= 0) return;
    if (frame != sp_frame) { sp_frame = frame; sp_acc = 0; }
    atomic_store(&sp_t0, now_ns() - sp_acc);   // as if this replay had begun when the frame's first one did, with no time between them
}
static const char *sp_name(uint64_t pc, char *buf, size_t n, int offset) {
    Dl_info di;
    if (dladdr((void *)(uintptr_t)pc, &di) && di.dli_sname) { if (offset && (uintptr_t)pc != (uintptr_t)di.dli_saddr) snprintf(buf, n, "%s+%#lx", di.dli_sname, (unsigned long)((uintptr_t)pc - (uintptr_t)di.dli_saddr)); else snprintf(buf, n, "%s", di.dli_sname); return buf; }
    snprintf(buf, n, "%#llx", (unsigned long long)pc); return buf;
}
static const char *sp_line(const uint64_t *pc, uint32_t n, char *line, size_t cap) {
    size_t at = 0; char nm[160]; line[0] = 0;
    for (uint32_t k = 0; k < n && at + 170 < cap; k++) {
        if (k == 1 && n > 2 && pc[1] == pc[2]) continue;   // the link register is the first frame record's return address in a function that has made its frame
        at += (size_t)snprintf(line + at, cap - at, "%s%s", at ? " < " : "", sp_name(pc[k], nm, sizeof nm, 0)); }
    return line;
}
static void sp_end(uint64_t frame) {
    if (sp_ms <= 0) return;
    uint64_t t0 = atomic_exchange(&sp_t0, 0); if (t0) sp_acc = now_ns() - t0;
    os_unfair_lock_lock(&sp_lock); int n = sp_n, on = sp_on; uint32_t lost = sp_olost; sp_n = 0; sp_on = 0; sp_olost = 0; os_unfair_lock_unlock(&sp_lock);   // the helper takes no stack once sp_t0 has changed
    if (!n || !t0) return;
    LOG("[subprof] frame %llu: %.1f ms of replays so far, %d stacks from %.1f ms on (innermost first; ms into the frame's replays, stacks in a row)", (unsigned long long)frame, sp_acc / 1e6, n, sp_s[0].us / 1e3);
    char line[1400], nm[160];
    for (int i = 0; i < n; ) {
        int j = i + 1; while (j < n && !sp_s[i].lock && !sp_s[j].lock && sp_s[j].n == sp_s[i].n && !memcmp(sp_s[j].pc, sp_s[i].pc, sp_s[i].n * sizeof(uint64_t))) j++;
        LOG("[subprof]   %6.1f ms x%-3d %s", sp_s[i].us / 1e3, j - i, sp_line(sp_s[i].pc, sp_s[i].n, line, sizeof line));
        if (sp_s[i].lock) {
            if (sp_s[i].own.n) LOG("[subprof]              the lock %s is held by thread %#llx '%s': %s", sp_name(sp_s[i].lock, nm, sizeof nm, 1), (unsigned long long)sp_s[i].own.tid, sp_s[i].own.name, sp_line(sp_s[i].own.pc, sp_s[i].own.n, line, sizeof line));
            else LOG("[subprof]              the lock %s: its owner's stack was not taken", sp_name(sp_s[i].lock, nm, sizeof nm, 1));
        }
        i = j;
    }
    for (int shown = 0; shown < 40 && shown < on; shown++) {   // the most frequent first
        int b = shown; for (int k = shown + 1; k < on; k++) if (sp_o[k].count > sp_o[b].count) b = k;
        __typeof__(sp_o[0]) t = sp_o[b]; sp_o[b] = sp_o[shown]; sp_o[shown] = t;
        LOG("[subprof]   running x%-3u thread %#llx '%s': %s", t.count, (unsigned long long)t.s.tid, t.s.name, sp_line(t.s.pc, t.s.n, line, sizeof line));
    }
    if (on > 40 || lost) LOG("[subprof]   %d more stacks of running threads not shown, %u not kept", on > 40 ? on - 40 : 0, lost);
}
static void *nq_worker(void *unused) {
    (void)unused; pthread_setname_np("NVN queue replay");
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0);
    uint64_t frame=UINT64_MAX;
    for(;;) {
        pthread_mutex_lock(&nq_mu); nq_queue *q=NULL; nq_node *n=NULL; nq_job *j=NULL;
        for(;;) {
        scan_again:;
            if(nq_test_held) { pthread_cond_wait(&nq_cv,&nq_mu); continue; }
            int mapped_event_wait=0;
            for(q=nq_queues;q;q=q->next) {
                j=q->first; if(!j) continue; n=j->first;
                if(!n && j->open) continue;   // its submit call is still copying: the next nodes come with a cut (nq_cut)
                if(!n) { nq_publish(j->receipt,q->physical); q->first=j->next; if(!q->first) q->last=NULL; nq_put(j->receipt);
                    pthread_mutex_unlock(&nq_mu); pthread_mutex_lock(&g_sub_mu); void *pool=objc_autoreleasePoolPush(); nq_job_free(j); objc_autoreleasePoolPop(pool); pthread_mutex_unlock(&g_sub_mu); pthread_mutex_lock(&nq_mu); goto scan_again; }
                if(n->kind==NQ_EVENT && n->event) {
                    uint64_t predecessor=nq_event_pending(n->event);
                    if(!n->waiting) n->event_predecessor=predecessor;
                    // The queued GPU write satisfies the wait: the GPU runs this continuation after it (nq_event_write). Ocarina of Time waits on about 25 events a frame; each wait
                    // for the writer's completion left the GPU idle while the host encoded the next submission, 2 ms of its 14.5 ms frame, which its dynamic resolution read as work
                    nq_event_write *queued=predecessor>mtl_completed_fence() ? nq_event_write_of(n->event) : NULL;
                    if(queued && queued->exact && nq_predicate(queued->value,n->mode,n->value)) break;
                    if(predecessor>mtl_completed_fence() || !nq_predicate(atomic_load_explicit((_Atomic uint32_t *)n->event,memory_order_acquire),n->mode,n->value)) { n->waiting=1; mapped_event_wait=1; continue; }
                }
                if(n->kind==NQ_SYNC) {
                    if(n->receipt && !n->receipt->published) continue;
                    // Targets are immutable snapshots. One Metal queue orders an encoded producer before this continuation. A sync not yet fenced when the wait was submitted
                    // (wait_kind 0) is a snapshot of nothing to wait for, and the wait passes. Sparking! ZERO, on one NVN queue, waits on a sync before that queue's own first
                    // fence of it at its first load, which runs on the console; parked here, the fence behind the wait never published and its SyncWait stalled the game (#1808)
                }
                break;
            }
            if(q) break;
            // NVN events can also be changed by plain stores through mapped pool memory.
            // A bounded notification poll only while such a word is awaited complements API/callback wakes.
            if(mapped_event_wait) { struct timespec tick={0,1000000}; pthread_cond_timedwait_relative_np(&nq_cv,&nq_mu,&tick); }
            else pthread_cond_wait(&nq_cv,&nq_mu);
        }
        j->first=n->next; if(!j->first) j->last=NULL;
        // Round-robin ready queues: a continually fed independent producer cannot starve another queue.
        if(q->next) { nq_queue **link=&nq_queues; while(*link!=q) link=&(*link)->next; *link=q->next; nq_queue *tail=nq_queues; while(tail->next) tail=tail->next; tail->next=q; q->next=NULL; }
        if(n->kind==NQ_SYNC || n->kind==NQ_EVENT) { uint64_t f=n->receipt?n->receipt->fence:n->wait_fence; if(f>q->physical) q->physical=f; }
        if(n->kind==NQ_FENCE) nq_publish(n->receipt,q->physical);
        pthread_mutex_unlock(&nq_mu);
        uint64_t fence=0, present=0, copy=0;
        if(n->kind==NQ_COMMANDS || n->kind==NQ_PRESENT) {
            dm_host_mutex_lock(&g_sub_mu); void *pool=objc_autoreleasePoolPush();
            dm_host_work++; mtl_prepare(); dm_host_work--;
            gfx_enter(); nq_cost cost=nq_cost_begin(); sp_begin(j->frame);
            if(frame!=j->frame) { frame=j->frame; mtl_set_frame(frame); }
            mtl_queue_activate(q->serial); mtl_set_queue_origin_lower_left(q->origin);
            if(n->kind==NQ_COMMANDS) {
                uint64_t handle=(uintptr_t)n->bytes;
                nvn_cap_submit(1,&handle);
                mtl_sub_begin(); nvn_ft_poll(); mtl_sub_index(&handle,1);
                mtl_exec_rest(NULL,0); mtl_exec(n->bytes); fence=mtl_sub_commit();
            } else {
                nvn_cap_present(&n->texture,n->crop);
                present=mtl_present(&n->texture,n->period,n->crop,&copy); mtl_tex_unpin(n->texture.serial);
            }
            sp_end(frame); nq_cost_end(cost); gfx_leave(); objc_autoreleasePoolPop(pool); pthread_mutex_unlock(&g_sub_mu);
        }
        pthread_mutex_lock(&nq_mu); if(n->kind==NQ_PRESENT) { q->present=present; q->copy=copy; j->receipt->present=present; j->receipt->copy=copy; } if(fence) { q->physical=fence; for(unsigned i=0;i<n->signal_count;i++) nq_event_issued(n->signals[i].event,fence,n->signals[i].mode,n->signals[i].value); } if(n->receipt) nq_put(n->receipt); free(n->signals); free(n->bytes); free(n); pthread_cond_broadcast(&nq_cv); pthread_mutex_unlock(&nq_mu);
    }
    return NULL;
}
static void nq_start(void) { pthread_t t; if(pthread_create(&t,NULL,nq_worker,NULL)) die("NVN queue worker failed"); pthread_detach(t); }
static nq_node *nq_append(nq_job *j,unsigned kind) { nq_node *n=calloc(1,sizeof *n); if(!n) die("queue continuation allocation failed"); n->kind=kind; if(j->last) j->last->next=n; else j->first=n; j->last=n; return n; }
static void nq_bytes(nq_node *n,const void *bytes,size_t length) { if(n->length+length>n->capacity) { size_t want=n->length+length, cap=n->capacity<65536?65536:n->capacity; while(cap<want) cap*=2; n->capacity=cap;   /* doubling, not 4 KiB steps: a frame's MBs of commands were re-copied thousands of times */ n->bytes=realloc(n->bytes,n->capacity); if(!n->bytes) die("queue commands allocation failed"); } memcpy(n->bytes+n->length,bytes,length); n->length+=length; } // NOLINT(bugprone-suspicious-realloc-usage): allocation failure aborts, so the old buffer cannot leak into a continuing process
static void nq_signal_add(nq_node *n,nq_signal s) {
    if(!(n->signal_count&(n->signal_count-1))) { n->signals=realloc(n->signals,(n->signal_count?2*n->signal_count:1)*sizeof *n->signals); if(!n->signals) die("queue signals allocation failed"); } // NOLINT(bugprone-suspicious-realloc-usage): allocation failure aborts
    n->signals[n->signal_count++]=s;
}
static nq_node *nq_stage(nq_job *j,unsigned kind) { nq_node *n=calloc(1,sizeof *n); if(!n) die("queue continuation allocation failed"); n->kind=kind; if(j->slast) j->slast->next=n; else j->sfirst=n; j->slast=n; return n; }
static void nq_end(nq_job *j) { nq_node *n=j->slast; if(n && n->kind==NQ_COMMANDS && !n->closed) { op_hdr end={OP_END,8}; nq_bytes(n,&end,8); n->closed=1; } }
static void nq_enqueue(nq_queue *q,nq_job *j);
// A submit call copies a whole frame's recordings before it returns (Mario Kart World: 1.2 ms with two players, 2.0 ms with four, submitted the moment the previous frame's GPU work
// ends), and it used to hold the submission lock for all of it and to queue the job only at the end: the worker, and with it the GPU, waited for the whole copy before the frame's
// first command. Now the copy holds the lock only for the programs it snapshots (prog_get and the program pins belong to that lock; a texture's pin has its own, g_smu), and each cut
// (a wait or a fence) hands the nodes copied so far to the worker. DM_NVN_SUBMIT_STREAM=0: as before
static int nq_stream_on(void) { static int v=-1; if(v<0) { const char *e=getenv("DM_NVN_SUBMIT_STREAM"); v=!(e && !strcmp(e,"0")); } return v; }
static int nq_resolve(nq_job *j,int block) {   // the programs of the nodes copied so far, snapshotted; block 0: only if the lock is free → whether they are
    if(!j->pend) return 1;
    if(block) dm_host_mutex_lock(&g_sub_mu); else if(pthread_mutex_trylock(&g_sub_mu)) return 0;
    void *pool=objc_autoreleasePoolPush(); dm_host_work++; mtl_prepare(); dm_host_work--;
    for(nq_owned *o=j->pend;o;o=o->pnext) mtl_prog_snapshot((prog_t *)o->data,(const prog_t *)o->psrc);
    j->pend=NULL; objc_autoreleasePoolPop(pool); pthread_mutex_unlock(&g_sub_mu); return 1;
}
static void nq_hand_over(nq_job *j,int final) {   // the copied nodes join the job's list, in order, and the job its queue; their sync snapshots are taken here, as they were at the submit's end
    pthread_mutex_lock(&nq_mu);
    for(nq_node *node=j->sfirst;node;node=node->next) if(node->sync_source) {
        if(node->kind==NQ_FENCE) nq_set_sync((sync_t *)node->sync_source,node->receipt); else nq_snapshot_sync(node,node->sync_source);
        node->sync_source=NULL;
    }
    nq_node *keep=!final && j->slast && j->slast->kind==NQ_COMMANDS && !j->slast->closed ? j->slast : NULL, *end=j->sfirst;   // the node still being copied stays with the submit call
    if(keep) { if(end==keep) end=NULL; else { while(end->next!=keep) end=end->next; end->next=NULL; } } else end=j->slast;
    if(end) { if(j->last) j->last->next=j->sfirst; else j->first=j->sfirst; j->last=end; }
    j->sfirst=j->slast=keep; j->late=0;
    if(final) j->open=0;
    if(!j->queued) { j->queued=1; nq_enqueue(nq_get((queue_t *)j->owner),j); } else pthread_cond_broadcast(&nq_cv);
    pthread_mutex_unlock(&nq_mu);
}
// With the lock busy at a cut the worker is replaying, and needs no node yet: the nodes stay, and the copy asks again every 32 records (nq_late), so that a worker that has run
// out finds them within microseconds and not at the next cut, which can be a whole pass of draws away
static void nq_cut(nq_job *j) { if(j->held || !j->sfirst) return; if(nq_resolve(j,0)) nq_hand_over(j,0); else j->late=1; }
static void nq_late(nq_job *j) { if(nq_resolve(j,0)) nq_hand_over(j,0); }
// One record of a recording, copied into the job (its object pointers snapshotted); waits and fences cut the job. A signal does not: its value is published when the commands
// it is among complete (mtl_sub_event), and a wait on it is ordered by that value or, while it is in flight, by the fence of those commands (nq_event_write), so the node keeps
// every signal it records. Each node is a Metal command buffer of its own, so a cut ends the open render pass: BioShock Infinite signals an event per occlusion query, and a cut
// at each took its title screen from 88 to 189 passes a frame and from 734 MB to 2.58 GB of attachment loads (issue #2112)
static void nq_record_one(nq_job *j,const uint8_t *p,op_hdr h) {
    const uint8_t *a=p+8;
    if(h.op==OP_END || h.op==OP_JUMP || h.op==OP_CALL) die("NVN command list: a %s record inside a recording's piece at %p",h.op==OP_END?"END":h.op==OP_JUMP?"JUMP":"CALL",(const void *)p);
    if(h.op==OP_WAIT_EVENT || h.op==OP_WAIT_SYNC || h.op==OP_FENCE_SYNC) {
        nq_end(j); nq_cut(j); nq_node *n=nq_stage(j,h.op==OP_WAIT_EVENT?NQ_EVENT:h.op==OP_WAIT_SYNC?NQ_SYNC:NQ_FENCE); if(h.op!=OP_FENCE_SYNC) j->waits=1;
        if(h.op==OP_WAIT_EVENT) { memcpy(&n->event,a,8); memcpy(&n->mode,a+8,4); memcpy(&n->value,a+12,4); }
        else { memcpy(&n->sync_source,a,8); if(h.op==OP_FENCE_SYNC) n->receipt=nq_new(); }
    } else {
        nq_node *n=j->slast; if(!n || n->kind!=NQ_COMMANDS || n->closed) n=nq_stage(j,NQ_COMMANDS);
        if(j->late && !(++j->tick&31)) nq_late(j);
        size_t offset=n->length; nq_bytes(n,p,h.size); if(!n->bytes) die("queue commands: a record of %u bytes",h.size);
        if(!cap_rec_fields(h.op,n->bytes+offset+8,h.size,&nq_snapshot_ops,j)) die("queue snapshot: unknown command %u",h.op);
        if(h.op==OP_SIGNAL_EVENT) {
            nq_signal sig; memcpy(&sig.event,a,8); memcpy(&sig.mode,a+8,4); memcpy(&sig.value,a+12,4); nq_signal_add(n,sig);
        }
    }
}
// A compact record (nvn_obj.h OPC_*) goes into the job as the canonical records it stands for
static void nq_record(nq_job *j,const uint8_t *p,op_hdr h) {
    if(!rec_compact(h.op)) { nq_record_one(j,p,h); return; }
    uint8_t x[REC_EXPAND_MAX] __attribute__((aligned(8))); size_t n=rec_expand(p,x);
    for(size_t o=0;o<n;) { op_hdr c; memcpy(&c,x+o,8); nq_record_one(j,x+o,c); o+=c.size; }
}
// A handle is the recording's control list (nvn_obj.h ctl_e): its pieces of records, its links to more control memory. Calls were copied in when they were recorded
static void nq_flatten(nq_job *j,const uint8_t *list) {
    for(const uint8_t *e=list;;e+=8) {
        uint64_t v; memcpy(&v,e,8); unsigned k=ctl_kind(v);
        if(k==CTL_LINK) { e=ctl_addr(v)-8; continue; }
        if(k!=CTL_CHUNK) die("NVN command list %p: corrupt control entry %#llx at %p",(const void *)list,(unsigned long long)v,(const void *)e);
        const uint8_t *p=ctl_addr(v),*pe=p+ctl_chunk_bytes(v);
        while(p<pe) { op_hdr h; memcpy(&h,p,8);
            if(h.size<8 || h.size&7 || h.size>(size_t)(pe-p)) die("NVN command list %p: record {op %u, size %u} at %p, %zu bytes into its piece of %zu at %p",(const void *)list,h.op,h.size,(const void *)p,(size_t)(p-ctl_addr(v)),ctl_chunk_bytes(v),(const void *)ctl_addr(v));
            nq_record(j,p,h); p+=h.size; }
        if(v&CTL_LAST) return;
    }
}
static void nq_enqueue(nq_queue *q,nq_job *j) { if(q->last) q->last->next=j; else q->first=j; q->last=j; nq_put(q->tail); q->tail=j->receipt; q->tail->refs++; pthread_cond_broadcast(&nq_cv); }
void nvn_queue_submit(queue_t *q,int count,const uint64_t *handles) {
    pthread_once(&nq_once,nq_start); nq_job *j=calloc(1,sizeof *j); if(!j) die("queue job allocation failed"); j->receipt=nq_new();
    j->objects.klen=16; j->frame=dm_nvn_frame_count(); j->owner=q; j->open=1; j->held=!nq_stream_on();
    // No scheduler lock while copying descriptors or resolving shader libraries. The submission lock: for the first call's prepare step, then only in nq_resolve (see nq_stream_on)
    static _Atomic int prepared; void *pool=objc_autoreleasePoolPush();
    if(j->held || !atomic_load(&prepared)) { dm_host_mutex_lock(&g_sub_mu); dm_host_work++; mtl_prepare(); dm_host_work--; atomic_store(&prepared,1); if(!j->held) pthread_mutex_unlock(&g_sub_mu); }
    nq_cost cost=nq_cost_begin();
    for(int i=0;i<count;i++) nq_flatten(j,(const uint8_t *)(uintptr_t)handles[i]); nq_end(j);
    nq_resolve(j,1);
    nq_cost_end(cost); if(j->held) pthread_mutex_unlock(&g_sub_mu); objc_autoreleasePoolPop(pool);
    nvn_cap_queue(q->serial,j->waits);
    nq_hand_over(j,1);
}
// The window retains this logical receipt until it reacquires or finalizes that image.
// Only replay turns it into a physical display ticket; present never waits on the guest thread.
uint64_t nvn_queue_present(queue_t *q,const tex_t *t,double period,const int crop[4]) {
    nvn_cap_queue(q->serial,0);
    pthread_once(&nq_once,nq_start); nq_job *j=calloc(1,sizeof *j); if(!j) die("queue present allocation failed");
    j->receipt=nq_new(); j->frame=dm_nvn_frame_count(); nq_node *n=nq_append(j,NQ_PRESENT);
    n->texture=*t; mtl_tex_pin(t->serial); n->period=period; if(crop) memcpy(n->crop,crop,sizeof n->crop);
    pthread_mutex_lock(&nq_mu); j->receipt->refs++; uint64_t ticket=(uintptr_t)j->receipt;
    nq_enqueue(nq_get(q),j); pthread_mutex_unlock(&nq_mu); return ticket;
}
void nvn_queue_test_hold(int on) { pthread_mutex_lock(&nq_mu); nq_test_held=on; pthread_cond_broadcast(&nq_cv); pthread_mutex_unlock(&nq_mu); }
void nvn_queue_present_release(uint64_t ticket) {
    if(!ticket) return; pthread_mutex_lock(&nq_mu); nq_put((nq_receipt *)(uintptr_t)ticket); pthread_mutex_unlock(&nq_mu);
}
void nvn_queue_present_wait(uint64_t ticket) {
    if(!ticket) return; nq_receipt *r=(nq_receipt *)(uintptr_t)ticket;
    pthread_mutex_lock(&nq_mu); while(!r->published) pthread_cond_wait(&nq_cv,&nq_mu); uint64_t physical=r->present, copy=r->copy; pthread_mutex_unlock(&nq_mu);
    if(physical) mtl_present_wait_texture(physical,copy);   // the texture's next acquire: a snapshot's copy, else the present itself
}
void nvn_queue_fence(queue_t *q,sync_t *s) {
    pthread_mutex_lock(&nq_mu); nq_queue *p=nq_get(q);
    if(p->tail) nq_set_sync(s,p->tail); else { if(s->fenced==3) nq_put((nq_receipt *)(uintptr_t)s->fence); s->fenced=1; s->fence=p->physical; }
    pthread_mutex_unlock(&nq_mu);
}
int nvn_sync_wait(const sync_t *s,uint64_t timeout) {
    uint64_t start=now_ns(),fence=0; pthread_mutex_lock(&nq_mu);
    while(!nq_sync_encoded(s,&fence)) {
        uint64_t elapsed=now_ns()-start; if(timeout!=UINT64_MAX && elapsed>=timeout) { pthread_mutex_unlock(&nq_mu); return 0; }
        if(timeout==UINT64_MAX) pthread_cond_wait(&nq_cv,&nq_mu);
        else { uint64_t left=timeout-elapsed; struct timespec ts={(time_t)(left/1000000000ull),(long)(left%1000000000ull)}; pthread_cond_timedwait_relative_np(&nq_cv,&nq_mu,&ts); }
    }
    pthread_mutex_unlock(&nq_mu); uint64_t elapsed=now_ns()-start;
    return mtl_wait(fence,timeout==UINT64_MAX?timeout:elapsed>=timeout?0:timeout-elapsed);
}
void nvn_queue_wait_sync(queue_t *q,const sync_t *s) {
    nvn_cap_queue(q->serial,1);
    pthread_once(&nq_once,nq_start); nq_job *j=calloc(1,sizeof *j); if(!j) die("queue wait allocation failed"); j->receipt=nq_new();
    pthread_mutex_lock(&nq_mu); nq_snapshot_sync(nq_append(j,NQ_SYNC),s); nq_enqueue(nq_get(q),j); pthread_mutex_unlock(&nq_mu);
}
void nvn_queue_finish(queue_t *q) { sync_t s={0}; nvn_queue_fence(q,&s); nvn_sync_wait(&s,UINT64_MAX); nvn_sync_release(&s);
    pthread_mutex_lock(&nq_mu); nq_queue *p=nq_get(q); uint64_t present=p->present, copy=p->copy; pthread_mutex_unlock(&nq_mu);
    if(present) mtl_present_wait_texture(present,copy);   // a snapshot present: its copy has run, not the screen (the display link would pace a game that finishes every frame)
}
void nvn_queue_forget(queue_t *q) { nvn_queue_finish(q); pthread_mutex_lock(&nq_mu); nq_queue **p=&nq_queues; while(*p && (*p)->serial!=q->serial) p=&(*p)->next; if(*p) { nq_queue *old=*p; *p=old->next; nq_put(old->tail); free(old); } pthread_mutex_unlock(&nq_mu); }
