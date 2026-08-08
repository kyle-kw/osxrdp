#ifndef osxrdp_session_protocol_h
#define osxrdp_session_protocol_h

#include "xstream.h"
#include "utils.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Parse the payload following OSXRDP_SESSMAN_REQUEST_SESSION. The existing
 * wire format is an xstream string and must contain no trailing fields. */
static inline int osxrdp_parse_session_request(xstream_t* stream,
                                                const char** username,
                                                int* usernameLen) {
    if (stream == NULL || username == NULL || usernameLen == NULL) {
        return 1;
    }

    *username = NULL;
    *usernameLen = 0;
    const char* parsed = xstream_readStr(stream, usernameLen);
    if (parsed == NULL || xstream_getRemaining(stream) != 0 ||
        !osxrdp_validate_utf8_username(parsed, *usernameLen)) {
        *usernameLen = 0;
        return 1;
    }

    *username = parsed;
    return 0;
}

static inline int osxrdp_pending_session_is_reusable(int sessionId,
                                                      uint64_t createdMs,
                                                      uint64_t nowMs) {
    return sessionId > 0 && nowMs >= createdMs && nowMs - createdMs <= 10000;
}

#ifdef __cplusplus
}
#endif

#endif /* osxrdp_session_protocol_h */
