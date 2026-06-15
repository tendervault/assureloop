/* SPDX-License-Identifier: Apache-2.0 */

#include <stdint.h>
#include <errno.h>
#include <stdbool.h>
#include <zephyr/sys/util.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <assureloop/release.h>
#include <assureloop/telemetry.h>

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_CONFIRM_ON_BOOT) || \
    IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT)
#include <zephyr/dfu/mcuboot.h>
#endif

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT)
#include <zephyr/sys/reboot.h>
#endif

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT)
#include <zephyr/storage/flash_map.h>
#endif

LOG_MODULE_REGISTER(assureloop, LOG_LEVEL_INF);

#define LOOP_PERIOD_MS CONFIG_ASSURELOOP_LOOP_PERIOD_MS
#define LOOP_ITERATIONS CONFIG_ASSURELOOP_LOOP_ITERATIONS

BUILD_ASSERT(LOOP_PERIOD_MS > 0, "loop period must be positive");
BUILD_ASSERT(LOOP_ITERATIONS > 0, "loop iterations must be positive");

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ONCE)
BUILD_ASSERT(FIXED_PARTITION_EXISTS(storage_partition),
             "one-shot MCUboot update request requires a storage_partition");
#endif

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT)
BUILD_ASSERT(FIXED_PARTITION_EXISTS(slot1_partition),
             "MCUboot update request requires a slot1_partition");
#endif

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ONCE)
#define ASSURELOOP_LIFECYCLE_MARKER_MAGIC 0x414c3136U
#define ASSURELOOP_LIFECYCLE_MARKER_VERSION 1U

struct assureloop_lifecycle_marker {
    uint32_t magic;
    uint32_t version;
    uint32_t reserved0;
    uint32_t reserved1;
};
#endif

static int64_t now_ns(void)
{
    return (int64_t)k_ticks_to_ns_floor64(k_uptime_ticks());
}

static void assureloop_log_lifecycle_role(void)
{
    if (CONFIG_ASSURELOOP_LIFECYCLE_ROLE[0] != '\0') {
        LOG_INF("lifecycle_role=%s", CONFIG_ASSURELOOP_LIFECYCLE_ROLE);
    }
}

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ONCE)
static int assureloop_lifecycle_request_marker_read(bool *already_requested)
{
    const struct flash_area *area;
    struct assureloop_lifecycle_marker marker;
    int rc;

    rc = flash_area_open(PARTITION_ID(storage_partition), &area);
    if (rc != 0) {
        return rc;
    }

    rc = flash_area_read(area, 0, &marker, sizeof(marker));
    flash_area_close(area);
    if (rc != 0) {
        return rc;
    }

    *already_requested = marker.magic == ASSURELOOP_LIFECYCLE_MARKER_MAGIC &&
                         marker.version == ASSURELOOP_LIFECYCLE_MARKER_VERSION;

    return 0;
}

static int assureloop_lifecycle_request_marker_write(void)
{
    static const struct assureloop_lifecycle_marker marker = {
        .magic = ASSURELOOP_LIFECYCLE_MARKER_MAGIC,
        .version = ASSURELOOP_LIFECYCLE_MARKER_VERSION,
        .reserved0 = 0U,
        .reserved1 = 0U,
    };
    const struct flash_area *area;
    struct flash_sector sectors[16];
    uint32_t sector_count = ARRAY_SIZE(sectors);
    size_t erase_size;
    int rc;

    rc = flash_area_open(PARTITION_ID(storage_partition), &area);
    if (rc != 0) {
        return rc;
    }

    rc = flash_area_get_sectors(PARTITION_ID(storage_partition), &sector_count, sectors);
    if (rc != 0) {
        flash_area_close(area);
        return rc;
    }
    if (sector_count == 0U) {
        flash_area_close(area);
        return -EINVAL;
    }

    erase_size = MIN(sectors[0].fs_size, area->fa_size);
    rc = flash_area_erase(area, sectors[0].fs_off, erase_size);
    if (rc == 0) {
        rc = flash_area_write(area, 0, &marker, sizeof(marker));
    }

    flash_area_close(area);

    return rc;
}
#endif

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT)
static int assureloop_lifecycle_validate_secondary_image(void)
{
    struct mcuboot_img_header header;
    int rc;

    rc = boot_read_bank_header(PARTITION_ID(slot1_partition), &header, sizeof(header));
    if (rc != 0) {
        return rc;
    }

    LOG_INF("mcuboot_update_request secondary_version=%u.%u.%u+%u image_size=%u",
            header.h.v1.sem_ver.major,
            header.h.v1.sem_ver.minor,
            header.h.v1.sem_ver.revision,
            header.h.v1.sem_ver.build_num,
            header.h.v1.image_size);

    return 0;
}
#endif

static void assureloop_mcuboot_lifecycle_hook(void)
{
#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_CONFIRM_ON_BOOT)
    if (boot_is_img_confirmed()) {
        LOG_INF("mcuboot_confirm status=already_confirmed");
    } else {
        int rc = boot_write_img_confirmed();

        if (rc == 0) {
            LOG_INF("mcuboot_confirm status=confirmed");
        } else {
            LOG_ERR("mcuboot_confirm status=failed rc=%d", rc);
        }
    }
#endif

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT)
    {
        const int mode = IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_PERMANENT)
            ? BOOT_UPGRADE_PERMANENT
            : BOOT_UPGRADE_TEST;
        int rc;

#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ONCE)
        bool already_requested = false;

        rc = assureloop_lifecycle_request_marker_read(&already_requested);
        if (rc != 0) {
            LOG_ERR("mcuboot_update_request_once marker=read_failed rc=%d", rc);
            return;
        }
        if (already_requested) {
            LOG_INF("mcuboot_update_request_once marker=present");
            LOG_INF("mcuboot_update_request status=already_requested");
            return;
        }
#endif

        rc = assureloop_lifecycle_validate_secondary_image();
        if (rc != 0) {
            LOG_ERR("mcuboot_update_request status=secondary_invalid rc=%d", rc);
            return;
        }

        rc = boot_request_upgrade(mode);

        LOG_INF("mcuboot_update_request mode=%s rc=%d",
                mode == BOOT_UPGRADE_PERMANENT ? "permanent" : "test",
                rc);

        if (rc == 0) {
#if IS_ENABLED(CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ONCE)
            rc = assureloop_lifecycle_request_marker_write();
            if (rc != 0) {
                LOG_ERR("mcuboot_update_request_once marker=write_failed rc=%d", rc);
                return;
            }
            LOG_INF("mcuboot_update_request_once marker=written");
#endif
            LOG_INF("mcuboot_update_request rebooting");
            sys_reboot(SYS_REBOOT_COLD);
        }
    }
#endif
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
    assureloop_log_lifecycle_role();
    assureloop_mcuboot_lifecycle_hook();
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
