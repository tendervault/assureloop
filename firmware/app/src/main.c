/* SPDX-License-Identifier: Apache-2.0 */

#include <stdint.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <assureloop/release.h>
#include <assureloop/telemetry.h>

LOG_MODULE_REGISTER(assureloop, LOG_LEVEL_INF);

#define LOOP_PERIOD_MS CONFIG_ASSURELOOP_LOOP_PERIOD_MS
#define LOOP_ITERATIONS CONFIG_ASSURELOOP_LOOP_ITERATIONS

BUILD_ASSERT(LOOP_PERIOD_MS > 0, "loop period must be positive");
BUILD_ASSERT(LOOP_ITERATIONS > 0, "loop iterations must be positive");

static int64_t now_ns(void)
{
    return (int64_t)k_cyc_to_ns_floor64(k_cycle_get_64());
}

int main(void)
{
    const int64_t expected_period_ns = (int64_t)LOOP_PERIOD_MS * 1000LL * 1000LL;
    struct assureloop_loop_stats stats;
    int64_t previous_ns;

    assureloop_loop_stats_init(&stats);

#if CONFIG_ASSURELOOP_ENABLE_STARTUP_BANNER
    LOG_INF("AssureLoop controller demo booting");
#endif

    assureloop_release_log_identity();
    LOG_INF("loop_config period_ms=%d iterations=%d", LOOP_PERIOD_MS, LOOP_ITERATIONS);

    previous_ns = now_ns();

    for (uint32_t i = 0U; i < LOOP_ITERATIONS; i++) {
        int64_t current_ns;
        int64_t actual_period_ns;
        int64_t jitter_ns;

        k_sleep(K_MSEC(LOOP_PERIOD_MS));

        current_ns = now_ns();
        actual_period_ns = current_ns - previous_ns;
        jitter_ns = actual_period_ns - expected_period_ns;
        previous_ns = current_ns;

        assureloop_loop_stats_update(&stats, jitter_ns);

        LOG_INF("loop iteration=%u expected_period_ns=%lld actual_period_ns=%lld jitter_ns=%lld",
                i + 1U,
                expected_period_ns,
                actual_period_ns,
                jitter_ns);
    }

    LOG_INF("loop_summary iterations=%u min_jitter_ns=%lld max_jitter_ns=%lld avg_abs_jitter_ns=%lld",
            stats.iterations,
            stats.min_jitter_ns,
            stats.max_jitter_ns,
            assureloop_loop_stats_avg_abs_jitter_ns(&stats));

    LOG_INF("AssureLoop controller demo complete");

    return 0;
}
