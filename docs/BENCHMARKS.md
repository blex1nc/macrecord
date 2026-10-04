# Benchmarks

`macrecord-bench jitter [events] [intervalUs] [spinUs]` plays a synthetic macro on the real-time playback thread in
**dry-run mode**: every event goes through the real `CGEventPost` path to the WindowServer as a no-op event, so the
user's cursor and keyboard are never touched. It reports *lateness* = time the post call completed − scheduled time.

Phase 1 gate: p99 < 1 ms.

## Results — 2026-10-04, Apple silicon, macOS 26.2, release build

| Events | Interval | Spin | mean | p50 | p99 | max |
|---:|---:|---:|---:|---:|---:|---:|
| 1000 | 1 ms | 200 µs | 8.7 µs | 8.0 µs | 20.5 µs | 29.4 µs |
| 4000 | 250 µs | 200 µs | 5.5 µs | 5.2 µs | 13.9 µs | 69.5 µs |
| 200 | 10 ms | 200 µs | 21.3 µs | 20.0 µs | 39.8 µs | 62.5 µs |
| 1000 | 1 ms | 0 | 14.1 µs | 13.5 µs | 24.7 µs | 35.5 µs |

Drift at the last event stays below 30 µs: scheduling uses absolute deadlines, so errors never accumulate.

## Findings

- **The first `CGEventPost` takes ~18 ms** (WindowServer connection setup). Unmitigated, it delayed every following event
  (p99 6.6 ms). The player and autoclicker now post a no-op event *before* starting the schedule.
- **Real-time thread policy matters:** without `THREAD_TIME_CONSTRAINT_POLICY`, p50 lateness was ~590 µs.
- A short spin before each deadline trims the remaining wake-up latency (≈14 µs → ≈8 µs median).
