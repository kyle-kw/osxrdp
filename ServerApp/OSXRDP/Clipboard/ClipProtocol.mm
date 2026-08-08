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
    size_t pathLen = strlen(path);
    if (pathLen >= 3 && path[1] == ':' && (path[2] == '\\' || path[2] == '/')) {
        return false;
    }

    // Reject oversized paths (avoid silent truncation of a malicious prefix).
    if (pathLen >= 1024) {
        return false;
    }

    // Walk components manually. strtok_r skips empty segments, so it would
    // accept "foo/", "foo//bar", and trailing separators — reject those here.
    const char* p = path;
    int componentCount = 0;
    while (*p != '\0') {
        const char* start = p;
        while (*p != '\0' && *p != '/' && *p != '\\') {
            p++;
        }
        size_t len = (size_t)(p - start);
        if (len == 0) {
            // Empty component: leading (already blocked), trailing, or "//"
            return false;
        }
        if ((len == 1 && start[0] == '.') ||
            (len == 2 && start[0] == '.' && start[1] == '.')) {
            return false;
        }
        componentCount++;
        if (*p == '/' || *p == '\\') {
            p++;
            if (*p == '\0') {
                return false;
            }
        }
    }

    return componentCount > 0;
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

bool ClipProtocol_ValidateFileChunk(int expectedStreamId,
                                    int actualStreamId,
                                    int requestedLength,
                                    uint64_t offset,
                                    uint64_t fileSize,
                                    int dataLen) {
    if (expectedStreamId <= 0 || actualStreamId != expectedStreamId ||
        requestedLength <= 0 || dataLen <= 0 || dataLen > requestedLength ||
        offset > fileSize) {
        return false;
    }

    return (uint64_t)dataLen <= fileSize - offset;
}
