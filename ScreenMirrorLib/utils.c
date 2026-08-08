
#include "utils.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>

#include <CoreGraphics/CoreGraphics.h>

extern CFDictionaryRef CGSCopyCurrentSessionDictionary(void);

/*
int get_object_name_by_username(const char* prefix, char* buffer, int cchMax) {
    uid_t uid = getuid();
    
    struct passwd* pwd = getpwuid(uid);
    if (pwd == NULL) return 0;
    
    return get_object_name(pwd->pw_name, prefix, buffer, cchMax);
}

int get_object_name(const char* username, const char* prefix, char* buffer, int cchMax) {
    if (username == NULL || prefix == NULL) return 0;
    
    int prefixLen = (int)strlen(prefix);
    if (prefixLen == 0) return 0;

    int usernameLen = (int)strlen(username);
    if (usernameLen == 0) return 0;
    
    if (prefixLen + usernameLen + (sizeof(char) * 2) > cchMax) return 0;
    
    return sprintf(buffer, "%s_%s", prefix, username);
}
 */

int get_object_name_by_sessionid(const char* prefix, char* buffer, int cchMax, int isLockscreen) {
    int sessionId = get_current_session_id();
    if (sessionId <= 0) return 0;
    return get_object_name(sessionId, prefix, buffer, cchMax, isLockscreen);
}

int get_current_session_id(void) {
    CFDictionaryRef sessionInfo = CGSCopyCurrentSessionDictionary();
    if (sessionInfo == NULL) return 0;

    CFNumberRef sessionIdRef = CFDictionaryGetValue(sessionInfo, CFSTR("kCGSSessionIDKey"));
    if (sessionIdRef == NULL) {
        CFRelease(sessionInfo);
        
        return 0;
    }
    
    int sessionId = 0;
    CFNumberGetValue(sessionIdRef, kCFNumberIntType, &sessionId);

    CFRelease(sessionInfo);
    
    return sessionId;
}

int get_object_name(int sessionid, const char* prefix, char* buffer, int cchMax, int isLockscreen) {
    if (prefix == NULL) return 0;
    
    int prefixLen = (int)strlen(prefix);
    if (prefixLen == 0) return 0;
    
    if (prefixLen + 14 + (sizeof(char) * 2) > (size_t)cchMax) return 0;
    
    if (isLockscreen == 0) {
        return sprintf(buffer, "%s_%d", prefix, sessionid);
    }
    else {
        return sprintf(buffer, "%s_l_%d", prefix, sessionid);
    }
}

int osxrdp_get_sessionmanager_socket_path(char* buffer, int cchMax) {
    static const char* path = "/var/run/osxrdp/sessionmanager.sock";
    if (buffer == NULL || cchMax <= 0 || strlen(path) + 1 > (size_t)cchMax) return 0;
    memcpy(buffer, path, strlen(path) + 1);
    return (int)strlen(path);
}

int osxrdp_get_agent_socket_directory(uid_t uid, char* buffer, int cchMax) {
    if (buffer == NULL || cchMax <= 0) return 0;
    int result = snprintf(buffer, (size_t)cchMax, "/tmp/osxrdp-%u", (unsigned int)uid);
    return result > 0 && result < cchMax ? result : 0;
}

int osxrdp_get_agent_socket_path(uid_t uid, int sessionid, char* buffer, int cchMax, int isLockscreen) {
    if (buffer == NULL || cchMax <= 0 || sessionid <= 0) return 0;
    int result = snprintf(buffer, (size_t)cchMax, "/tmp/osxrdp-%u/agent%s-%d.sock",
                          (unsigned int)uid, isLockscreen ? "-lock" : "", sessionid);
    return result > 0 && result < cchMax ? result : 0;
}

int osxrdp_validate_utf8_username(const char* username, int usernameLen) {
    if (username == NULL || usernameLen < 1 || usernameLen > 260 ||
        strnlen(username, (size_t)usernameLen + 1) != (size_t)usernameLen) {
        return 0;
    }

    const unsigned char* bytes = (const unsigned char*)username;
    int index = 0;
    while (index < usernameLen) {
        unsigned char first = bytes[index++];
        if (first <= 0x7f) {
            continue;
        }

        int continuationCount = 0;
        unsigned int codePoint = 0;
        unsigned int minimum = 0;
        if (first >= 0xc2 && first <= 0xdf) {
            continuationCount = 1;
            codePoint = first & 0x1f;
            minimum = 0x80;
        }
        else if (first >= 0xe0 && first <= 0xef) {
            continuationCount = 2;
            codePoint = first & 0x0f;
            minimum = 0x800;
        }
        else if (first >= 0xf0 && first <= 0xf4) {
            continuationCount = 3;
            codePoint = first & 0x07;
            minimum = 0x10000;
        }
        else {
            return 0;
        }

        if (continuationCount > usernameLen - index) {
            return 0;
        }
        for (int part = 0; part < continuationCount; part++) {
            unsigned char next = bytes[index++];
            if ((next & 0xc0) != 0x80) {
                return 0;
            }
            codePoint = (codePoint << 6) | (next & 0x3f);
        }

        if (codePoint < minimum || codePoint > 0x10ffff ||
            (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
            return 0;
        }
    }

    return 1;
}

int is_root_process(void) {
    return getuid() == 0 ? 1 : 0;
}
