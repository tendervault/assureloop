/* SPDX-License-Identifier: Apache-2.0 */

#include <limits.h>
#include <stdlib.h>
#include <assureloop/telemetry.h>

void assureloop_loop_stats_init(struct assureloop_loop_stats *stats)
{
    stats->iterations = 0U;
    stats->min_jitter_ns = INT64_MAX;
    stats->max_jitter_ns = INT64_MIN;
    stats->sum_abs_jitter_ns = 0;
}

void assureloop_loop_stats_update(struct assureloop_loop_stats *stats, int64_t jitter_ns)
{
    int64_t abs_jitter_ns = llabs(jitter_ns);

    if (jitter_ns < stats->min_jitter_ns) {
        stats->min_jitter_ns = jitter_ns;
    }

    if (jitter_ns > stats->max_jitter_ns) {
        stats->max_jitter_ns = jitter_ns;
    }

    stats->sum_abs_jitter_ns += abs_jitter_ns;
    stats->iterations++;
}

int64_t assureloop_loop_stats_avg_abs_jitter_ns(const struct assureloop_loop_stats *stats)
{
    if (stats->iterations == 0U) {
        return 0;
    }

    return stats->sum_abs_jitter_ns / (int64_t)stats->iterations;
}
