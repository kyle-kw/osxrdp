#ifndef UserIdentityResolver_h
#define UserIdentityResolver_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int osxup_copy_canonical_username(const char* username, char* canonicalUsername, size_t canonicalUsernameSize);
int osxup_username_matches_canonical_case(const char* username, const char* canonicalUsername);
// Reads osxrdp.streamQualityPreset from the authenticated user's fixed app domain.
// Missing, non-numeric, and out-of-range values resolve to High Quality.
int osxup_get_stream_quality_preset(const char* canonicalUsername);

#ifdef __cplusplus
}
#endif

#endif /* UserIdentityResolver_h */
