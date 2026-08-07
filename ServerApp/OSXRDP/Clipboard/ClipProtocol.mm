#include "ClipProtocol.h"
#include <string.h>

bool ClipProtocol_IsSafeRelativePath(const char* path) {
    if (path == NULL || path[0] == '\0') {
        return false;
    }

    // Reject absolute paths (Unix or Windows style)
    if (path[0] == '/' || path[0] == '\\') {
        return false;
    }

    // Check for Windows drive letter (e.g. "C:\")
    if (strlen(path) >= 3 && path[1] == ':' && (path[2] == '\\' || path[2] == '/')) {
        return false;
    }

    // Reject oversized paths (avoid silent truncation of a malicious prefix).
    size_t pathLen = strlen(path);
    if (pathLen >= 1024) {
        return false;
    }

    // Split on both / and \ to check each component
    char buf[1024];
    memcpy(buf, path, pathLen + 1);

    char* saveptr = NULL;
    char* component = strtok_r(buf, "/\\", &saveptr);
    while (component != NULL) {
        if (component[0] == '\0') {
            // Empty component (e.g. "foo//bar" or trailing "/")
            return false;
        }
        if (strcmp(component, ".") == 0 || strcmp(component, "..") == 0) {
            return false;
        }
        component = strtok_r(NULL, "/\\", &saveptr);
    }

    return true;
}

void ClipProtocol_WriteUInt64ToBuffer(unsigned char* buffer, uint64_t value) {
    buffer[0] = (unsigned char)(value & 0xFF);
    buffer[1] = (unsigned char)((value >> 8) & 0xFF);
    buffer[2] = (unsigned char)((value >> 16) & 0xFF);
    buffer[3] = (unsigned char)((value >> 24) & 0xFF);
    buffer[4] = (unsigned char)((value >> 32) & 0xFF);
    buffer[5] = (unsigned char)((value >> 40) & 0xFF);
    buffer[6] = (unsigned char)((value >> 48) & 0xFF);
    buffer[7] = (unsigned char)((value >> 56) & 0xFF);
}

uint64_t ClipProtocol_ReadUInt64FromLowHigh(uint32_t low, uint32_t high) {
    return ((uint64_t)high << 32) | (uint64_t)low;
}

int ClipProtocol_GetRequestedFormatPriority(int clipType, int formatId) {
    switch (clipType) {
        case CLIP_PROTOCOL_TYPE_RICHTEXT:
            return 40;
        case CLIP_PROTOCOL_TYPE_IMAGE:
            return 30;
        case CLIP_PROTOCOL_TYPE_TEXT:
            if (formatId == CLIP_PROTOCOL_CF_UNICODETEXT) {
                return 20;
            }
            return 0;
        default:
            return 0;
    }
}
