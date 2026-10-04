#ifndef CSUPPORT_H
#define CSUPPORT_H

#include <stdint.h>
#include <stdbool.h>

/// Lock-free flag shared between UI and real-time threads.
typedef struct mr_flag mr_flag;
mr_flag *mr_flag_create(bool initial);
void mr_flag_destroy(mr_flag *flag);
bool mr_flag_load(const mr_flag *flag);
void mr_flag_store(mr_flag *flag, bool value);

/// Lock-free counter (relaxed ordering; for progress display only).
typedef struct mr_counter mr_counter;
mr_counter *mr_counter_create(void);
void mr_counter_destroy(mr_counter *counter);
int64_t mr_counter_load(const mr_counter *counter);
void mr_counter_store(mr_counter *counter, int64_t value);
void mr_counter_add(mr_counter *counter, int64_t delta);

/// Promote the calling thread to the Mach real-time (time-constraint) band.
/// Values are nanoseconds. Returns true on success.
bool mr_thread_set_realtime(uint64_t period_ns, uint64_t computation_ns, uint64_t constraint_ns);

/// Mach absolute time helpers.
uint64_t mr_now_ticks(void);
uint64_t mr_ns_to_ticks(uint64_t ns);
uint64_t mr_ticks_to_ns(uint64_t ticks);

/// Sleep until `deadline_ticks`, waking `spin_ns` early and busy-waiting the rest.
/// Returns mach_absolute_time() at return.
uint64_t mr_wait_until(uint64_t deadline_ticks, uint64_t spin_ns);

#endif
