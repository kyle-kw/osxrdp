#ifndef ClipProtocol_h
#define ClipProtocol_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Shared clip-type ids — must stay in sync with ClipboardManager::PendingClipType.
enum {
    CLIP_PROTOCOL_TYPE_NONE     = 0,
    CLIP_PROTOCOL_TYPE_TEXT     = 1,
    CLIP_PROTOCOL_TYPE_RICHTEXT = 2,
    CLIP_PROTOCOL_TYPE_IMAGE    = 3,
    CLIP_PROTOCOL_TYPE_FILELIST = 4
};

// Windows CF_UNICODETEXT (see xrdp_constants.h / ClipboardManager).
#define CLIP_PROTOCOL_CF_UNICODETEXT 13

// Pure-C path safety check (extracted from ClipboardManager::IsSafeRelativeFileName)
// Rejects absolute paths, ".", "..", empty components, backslash-separated paths.
bool ClipProtocol_IsSafeRelativePath(const char* path);

// Pure-C uint64 LE buffer helpers (extracted from ClipboardManager)
void ClipProtocol_WriteUInt64ToBuffer(unsigned char* buffer, uint64_t value);
uint64_t ClipProtocol_ReadUInt64FromLowHigh(uint32_t low, uint32_t high);

// GetRequestedFormatPriority extracted from ClipboardManager.
// clipType: CLIP_PROTOCOL_TYPE_*; formatId: CLIP_PROTOCOL_CF_UNICODETEXT, etc.
int ClipProtocol_GetRequestedFormatPriority(int clipType, int formatId);

#ifdef __cplusplus
}
#endif

#endif
