#include "CSupport.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <pthread.h>

struct mr_flag { _Atomic bool value; };
struct mr_counter { _Atomic int64_t value; };

mr_flag *mr_flag_create(bool initial) {
    mr_flag *flag = malloc(sizeof(mr_flag));
    atomic_init(&flag->value, initial);
    return flag;
}
void mr_flag_destroy(mr_flag *flag) { free(flag); }
bool mr_flag_load(const mr_flag *flag) { return atomic_load_explicit(&((mr_flag *)flag)->value, memory_order_acquire); }
void mr_flag_store(mr_flag *flag, bool value) { atomic_store_explicit(&flag->value, value, memory_order_release); }

mr_counter *mr_counter_create(void) {
    mr_counter *counter = malloc(sizeof(mr_counter));
    atomic_init(&counter->value, 0);
    return counter;
}
void mr_counter_destroy(mr_counter *counter) { free(counter); }
int64_t mr_counter_load(const mr_counter *counter) { return atomic_load_explicit(&((mr_counter *)counter)->value, memory_order_relaxed); }
void mr_counter_store(mr_counter *counter, int64_t value) { atomic_store_explicit(&counter->value, value, memory_order_relaxed); }
void mr_counter_add(mr_counter *counter, int64_t delta) { atomic_fetch_add_explicit(&counter->value, delta, memory_order_relaxed); }

static mach_timebase_info_data_t timebase_info;
static pthread_once_t timebase_once = PTHREAD_ONCE_INIT;
static void timebase_init(void) { mach_timebase_info(&timebase_info); }

static mach_timebase_info_data_t timebase(void) {
    pthread_once(&timebase_once, timebase_init);
    return timebase_info;
}

uint64_t mr_now_ticks(void) { return mach_absolute_time(); }

uint64_t mr_ns_to_ticks(uint64_t ns) {
    mach_timebase_info_data_t tb = timebase();
    return (uint64_t)((__uint128_t)ns * tb.denom / tb.numer);
}

uint64_t mr_ticks_to_ns(uint64_t ticks) {
    mach_timebase_info_data_t tb = timebase();
    return (uint64_t)((__uint128_t)ticks * tb.numer / tb.denom);
}

bool mr_thread_set_realtime(uint64_t period_ns, uint64_t computation_ns, uint64_t constraint_ns) {
    thread_time_constraint_policy_data_t policy;
    policy.period = (uint32_t)mr_ns_to_ticks(period_ns);
    policy.computation = (uint32_t)mr_ns_to_ticks(computation_ns);
    policy.constraint = (uint32_t)mr_ns_to_ticks(constraint_ns);
    policy.preemptible = 1;
    kern_return_t kr = thread_policy_set(pthread_mach_thread_np(pthread_self()),
                                         THREAD_TIME_CONSTRAINT_POLICY,
                                         (thread_policy_t)&policy,
                                         THREAD_TIME_CONSTRAINT_POLICY_COUNT);
    return kr == KERN_SUCCESS;
}

uint64_t mr_wait_until(uint64_t deadline_ticks, uint64_t spin_ns) {
    uint64_t spin_ticks = mr_ns_to_ticks(spin_ns);
    uint64_t now = mach_absolute_time();
    if (deadline_ticks > now + spin_ticks) {
        mach_wait_until(deadline_ticks - spin_ticks);
    }
    while ((now = mach_absolute_time()) < deadline_ticks) {
#if defined(__aarch64__)
        __asm__ volatile("yield");
#else
        __asm__ volatile("pause");
#endif
    }
    return now;
}
