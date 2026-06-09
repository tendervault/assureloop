/* SPDX-License-Identifier: Apache-2.0 */
#ifndef ASSURELOOP_TELEMETRY_H
#define ASSURELOOP_TELEMETRY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct assureloop_loop_stats {
    uint32_t iterations;
    int64_t min_jitter_ns;
    int64_t max_jitter_ns;
    int64_t sum_abs_jitter_ns;
};

void assureloop_loop_stats_init(struct assureloop_loop_stats *stats);
void assureloop_loop_stats_update(struct assureloop_loop_stats *stats, int64_t jitter_ns);
int64_t assureloop_loop_stats_avg_abs_jitter_ns(const struct assureloop_loop_stats *stats);

#ifdef __cplusplus
}
#endif

#endif /* ASSURELOOP_TELEMETRY_H */
