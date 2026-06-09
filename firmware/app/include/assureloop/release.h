/* SPDX-License-Identifier: Apache-2.0 */
#ifndef ASSURELOOP_RELEASE_H
#define ASSURELOOP_RELEASE_H

#ifdef __cplusplus
extern "C" {
#endif

struct assureloop_release_info {
    const char *product;
    const char *version;
    const char *build_profile;
    const char *git_sha;
};

const struct assureloop_release_info *assureloop_release_info_get(void);
void assureloop_release_log_identity(void);

#ifdef __cplusplus
}
#endif

#endif /* ASSURELOOP_RELEASE_H */
