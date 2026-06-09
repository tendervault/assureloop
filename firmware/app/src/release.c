/* SPDX-License-Identifier: Apache-2.0 */

#include <zephyr/logging/log.h>
#include <assureloop/release.h>

LOG_MODULE_REGISTER(assureloop_release, LOG_LEVEL_INF);

#ifndef ASSURELOOP_PRODUCT
#define ASSURELOOP_PRODUCT "assureloop-controller-demo"
#endif

#ifndef ASSURELOOP_VERSION
#define ASSURELOOP_VERSION "0.1.0-dev"
#endif

#ifndef ASSURELOOP_BUILD_PROFILE
#define ASSURELOOP_BUILD_PROFILE "dev"
#endif

#ifndef ASSURELOOP_GIT_SHA
#define ASSURELOOP_GIT_SHA "unknown"
#endif

static const struct assureloop_release_info release_info = {
    .product = ASSURELOOP_PRODUCT,
    .version = ASSURELOOP_VERSION,
    .build_profile = ASSURELOOP_BUILD_PROFILE,
    .git_sha = ASSURELOOP_GIT_SHA,
};

const struct assureloop_release_info *assureloop_release_info_get(void)
{
    return &release_info;
}

void assureloop_release_log_identity(void)
{
    const struct assureloop_release_info *info = assureloop_release_info_get();

    LOG_INF("release product=%s version=%s profile=%s git_sha=%s",
            info->product,
            info->version,
            info->build_profile,
            info->git_sha);
}
