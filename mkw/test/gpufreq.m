// gpufreq.m: the GPU's performance-state residency, one line a second (IOReport; no root needed).
// It ran beside the timing runs of one evening (2026-11-12) and was suspected of the stalls those runs showed; a Grand Prix without it stalled the same way
// (mkw/KNOWLEDGE.md, section 0: the kernel ending idle daemons for memory). Still: sample the GPU's clock in a run of its own, not beside a run whose frame
// times you will use.
// build: clang -O2 -fobjc-arc -o gpufreq gpufreq.m -framework Foundation -framework IOKit -lIOReport
// usage: gpufreq [seconds between lines, default 1] [lines, default until killed]
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include <unistd.h>
#include <time.h>

typedef struct __IOReportSubscriptionCF *IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a, uint64_t b, uint64_t c);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *a, CFMutableDictionaryRef desired, CFMutableDictionaryRef *subbed, uint64_t channel_id, CFTypeRef b);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub, CFMutableDictionaryRef subbed, CFTypeRef a);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef cur, CFTypeRef a);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef ch);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef ch);
extern int IOReportStateGetCount(CFDictionaryRef ch);
extern CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef ch, int i);
extern int64_t IOReportStateGetResidency(CFDictionaryRef ch, int i);

static NSArray<NSNumber *> *freq_table(NSString *prop) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"));
    if (!s) return @[];
    NSData *d = CFBridgingRelease(IORegistryEntryCreateCFProperty(s, (__bridge CFStringRef)prop, kCFAllocatorDefault, 0));
    IOObjectRelease(s);
    if (![d isKindOfClass:[NSData class]]) return @[];
    NSMutableArray *a = [NSMutableArray array];
    const uint32_t *p = d.bytes;
    for (NSUInteger i = 0; i + 1 < d.length / 4; i += 2) [a addObject:@(p[i])];
    return a;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double step = argc > 1 ? atof(argv[1]) : 1.0;
        long lines = argc > 2 ? atol(argv[2]) : -1;
        setvbuf(stdout, NULL, _IOLBF, 0);
        for (NSString *prop in @[@"voltage-states9", @"voltage-states9-sram"]) {
            NSArray *f = freq_table(prop);
            printf("# pmgr %s:", prop.UTF8String);
            for (NSNumber *n in f) printf(" %.0f", n.doubleValue / 1e6);
            printf(" (MHz, %lu entries)\n", (unsigned long)f.count);
        }
        NSArray<NSNumber *> *freqs = freq_table(@"voltage-states9");
        CFDictionaryRef chans = IOReportCopyChannelsInGroup(CFSTR("GPU Stats"), CFSTR("GPU Performance States"), 0, 0, 0);
        if (!chans) { fprintf(stderr, "no GPU Stats / GPU Performance States channels\n"); return 1; }
        CFMutableDictionaryRef desired = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, chans);
        CFMutableDictionaryRef subbed = NULL;
        IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, desired, &subbed, 0, NULL);
        if (!sub) { fprintf(stderr, "no subscription\n"); return 1; }
        CFDictionaryRef prev = IOReportCreateSamples(sub, subbed, NULL);
        int head = 0;
        for (long n = 0; lines < 0 || n < lines; n++) {
            usleep((useconds_t)(step * 1e6));
            CFDictionaryRef cur = IOReportCreateSamples(sub, subbed, NULL);
            CFDictionaryRef delta = IOReportCreateSamplesDelta(prev, cur, NULL);
            CFRelease(prev); prev = cur;
            NSArray *arr = ((__bridge NSDictionary *)delta)[@"IOReportChannels"];
            for (id chobj in arr) {
                CFDictionaryRef ch = (__bridge CFDictionaryRef)chobj;
                NSString *name = (__bridge NSString *)IOReportChannelGetChannelName(ch);
                if (![name isEqualToString:@"GPUPH"]) continue;
                int cnt = IOReportStateGetCount(ch);
                if (!head) {
                    head = 1;
                    printf("# channel %s, %d states:", name.UTF8String, cnt);
                    for (int i = 0; i < cnt; i++) printf(" %s", ((__bridge NSString *)IOReportStateGetNameForIndex(ch, i)).UTF8String);
                    printf("\n# time  on%%  avg MHz while on (table entry i for state Pi)  then each state's share of the on time\n");
                }
                double tot = 0, on = 0, fsum = 0; double r[64] = {0};
                for (int i = 0; i < cnt && i < 64; i++) { r[i] = (double)IOReportStateGetResidency(ch, i); tot += r[i]; }
                for (int i = 0; i < cnt && i < 64; i++) {
                    NSString *sn = (__bridge NSString *)IOReportStateGetNameForIndex(ch, i);
                    if (![sn hasPrefix:@"P"]) continue;
                    int pi = [[sn substringFromIndex:1] intValue];
                    on += r[i];
                    if (pi >= 0 && pi < (int)freqs.count) fsum += r[i] * freqs[pi].doubleValue / 1e6;
                }
                time_t t = time(NULL); struct tm tmv; localtime_r(&t, &tmv);
                printf("%02d:%02d:%02d %5.1f %6.0f ", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, tot > 0 ? 100 * on / tot : 0, on > 0 ? fsum / on : 0);
                for (int i = 0; i < cnt && i < 64; i++) {
                    NSString *sn = (__bridge NSString *)IOReportStateGetNameForIndex(ch, i);
                    if (![sn hasPrefix:@"P"] || on <= 0) continue;
                    double sh = 100 * r[i] / on;
                    if (sh >= 0.5) printf(" %s=%.0f", sn.UTF8String, sh);
                }
                printf("\n");
            }
            CFRelease(delta);
        }
    }
    return 0;
}
