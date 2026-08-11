#include "../pch.h"
#include "Command.h"
#include "osxrdp/packet.h"
#include "ipc.h"

// Must stay under IPC body limit (MAX_BUFFER) after 6 int headers.
static const int kMaxClipboardIpcPayload = 14 * 1024;

bool Command::SendRecordStartMsg(xipc_t* agentIpc, int width, int height, int framerate,
                                 int recordFormat, int useVirtualmon, int monitorCount,
                                 struct monitor_info* monitorInfo, int policyVersion, int preset,
                                 int packetType) {
    assert(agentIpc != NULL);
    assert(width > 0);
    assert(height > 0);

    xstream_t* stream = xstream_create(1024);
    if (stream == NULL) {
        return false;
    }
    
    if (monitorCount < 0 || monitorInfo == NULL) {
        monitorCount = 0;
    }
    else if (monitorCount > 16) {
        monitorCount = 16;
    }

    xstream_writeInt32(stream, OSXRDP_CMDTYPE_SCREEN);
    if (packetType != OSXRDP_PACKETTYPE_REQ_SCREEN &&
        packetType != OSXRDP_PACKETTYPE_REQ_SCREENRECONFIGURE) {
        xstream_free(stream);
        return false;
    }
    xstream_writeInt32(stream, packetType);
    xstream_writeInt32(stream, 0);              // display index etc. (unused)
    xstream_writeInt32(stream, width);          // width
    xstream_writeInt32(stream, height);         // height
    xstream_writeInt32(stream, framerate);
    xstream_writeInt32(stream, recordFormat);   // recordFormat (BGRA32, NV12, RFX)
    xstream_writeInt32(stream, useVirtualmon);  // use virtual monitor (0, 1)
    
    if (monitorCount == 0) {
        xstream_writeInt32(stream, 1);
        xstream_writeInt32(stream, 0);
        xstream_writeInt32(stream, 0);
        xstream_writeInt32(stream, width);
        xstream_writeInt32(stream, height);
        xstream_writeInt32(stream, 1);
    }
    else {
        xstream_writeInt32(stream, monitorCount);
        
        for (int i = 0; i < monitorCount; i++) {
            xstream_writeInt32(stream, monitorInfo[i].left);
            xstream_writeInt32(stream, monitorInfo[i].top);
            xstream_writeInt32(stream, monitorInfo[i].right);
            xstream_writeInt32(stream, monitorInfo[i].bottom);
            xstream_writeInt32(stream, monitorInfo[i].is_primary);
        }
    }
    xstream_writeInt32(stream, policyVersion);
    xstream_writeInt32(stream, preset);
    
    bool sent = _SendMsg(agentIpc, stream);

    xstream_free(stream);
    return sent;
}

void Command::SendRecordStopMsg(xipc_t* agentIpc) {
    assert(agentIpc != NULL);

    xstream_t* stream = xstream_create(8);
    if (stream == NULL) {
        return;
    }

    xstream_writeInt32(stream, OSXRDP_CMDTYPE_SCREEN);
    xstream_writeInt32(stream, OSXRDP_PACKETTYPE_REQ_SCREENOFF);

    _SendMsg(agentIpc, stream);

    xstream_free(stream);
}

bool Command::SendScreenResizeMsg(xipc_t* agentIpc, int width, int height, int framerate,
                                  int recordFormat, int useVirtualmon, int monitorCount,
                                  const struct monitor_info* monitorInfo, int policyVersion, int preset) {
    if (agentIpc == NULL || width <= 0 || height <= 0) {
        return false;
    }

    xstream_t* stream = xstream_create(1024);
    if (stream == NULL) {
        return false;
    }

    // Cap at 16 to match ConnectionManager::SendResolutionChange (do not collapse to 1)
    if (monitorCount < 0 || monitorInfo == NULL) {
        monitorCount = 0;
    }
    else if (monitorCount > 16) {
        monitorCount = 16;
    }

    // Even-align dimensions (odd resolutions cause NV12 encoding issues)
    width &= ~0x1;
    height &= ~0x1;
    if (width <= 0 || height <= 0) {
        xstream_free(stream);
        return false;
    }

    xstream_writeInt32(stream, OSXRDP_CMDTYPE_SCREEN);
    xstream_writeInt32(stream, OSXRDP_PACKETTYPE_REQ_SCREENRESIZE);
    xstream_writeInt32(stream, 0);              // display index (unused)
    xstream_writeInt32(stream, width);
    xstream_writeInt32(stream, height);
    xstream_writeInt32(stream, framerate);
    xstream_writeInt32(stream, recordFormat);
    xstream_writeInt32(stream, useVirtualmon);

    if (monitorCount == 0) {
        xstream_writeInt32(stream, 1);
        xstream_writeInt32(stream, 0);
        xstream_writeInt32(stream, 0);
        xstream_writeInt32(stream, width);
        xstream_writeInt32(stream, height);
        xstream_writeInt32(stream, 1);
    }
    else {
        xstream_writeInt32(stream, monitorCount);

        for (int i = 0; i < monitorCount; i++) {
            xstream_writeInt32(stream, monitorInfo[i].left);
            xstream_writeInt32(stream, monitorInfo[i].top);
            xstream_writeInt32(stream, monitorInfo[i].right);
            xstream_writeInt32(stream, monitorInfo[i].bottom);
            xstream_writeInt32(stream, monitorInfo[i].is_primary);
        }
    }
    xstream_writeInt32(stream, policyVersion);
    xstream_writeInt32(stream, preset);

    bool sent = _SendMsg(agentIpc, stream);

    xstream_free(stream);
    return sent;
}

void Command::SendMouseInputMsg(xipc_t* agentIpc, int inputType, short x, short y) {
    struct {
        int cmdType;
        int packetType;
        int inputType;
        int x;
        int y;
    } __attribute__((packed)) msg = {
        OSXRDP_CMDTYPE_SCREEN,
        OSXRDP_PACKETTYPE_MOUSEEVT,
        inputType,
        x,
        y
    };
    
    xipc_send_data(agentIpc, (void*)&msg, sizeof(msg));
}

void Command::SendKeyboardInputMsg(xipc_t* agentIpc, int inputType, int keycode, int flags) {
    struct {
        int cmdType;
        int packetType;
        int inputType;
        int keycode;
        int flags;
    } __attribute__((packed)) msg = {
        OSXRDP_CMDTYPE_SCREEN,
        OSXRDP_PACKETTYPE_KEYBOARDEVT,
        inputType,
        keycode,
        flags
    };
    
    xipc_send_data(agentIpc, (void*)&msg, sizeof(msg));
}

void Command::SendSessionRequestMsg(xipc_t* sessionIpc, const char* username, int usernameLen) {
    assert(sessionIpc != NULL);
    assert(username != NULL);
    
    xstream_t* stream = xstream_create(512);
    if (stream == NULL) {
        return;
    }
    xstream_writeInt32(stream, OSXRDP_SESSMAN_REQUEST_SESSION);
    xstream_writeStr(stream, username, (int)usernameLen);
    
    _SendMsg(sessionIpc, stream);
    
    xstream_free(stream);
}

void Command::SendSessionReleaseMsg(xipc_t* sessionIpc, int sessionId) {
    assert(sessionIpc != NULL);
    
    xstream_t* stream = xstream_create(8);
    if (stream == NULL) {
        return;
    }
    xstream_writeInt32(stream, OSXRDP_SESSMAN_REQUEST_RELEASESESSION);
    xstream_writeInt32(stream, sessionId);

    _SendMsg(sessionIpc, stream);
    
    xstream_free(stream);
}

void Command::SendClipboardMsg(xipc_t* agentIpc, int channelId, int channelFlags, const char* data, int dataLen, int totalLen) {
    assert(agentIpc != NULL);

    if (data == NULL || dataLen <= 0 || totalLen <= 0 || dataLen > totalLen) {
        return;
    }
    if (dataLen > kMaxClipboardIpcPayload) {
        return;
    }

    xstream_t* stream = xstream_create(dataLen + (int)sizeof(int) * 6);
    if (stream == NULL) {
        return;
    }

    xstream_writeInt32(stream, OSXRDP_CMDTYPE_CLIPBOARD);
    xstream_writeInt32(stream, OSXRDP_PACKETTYPE_REQ_SETCLIENTCLIP);
    xstream_writeInt32(stream, channelId);
    xstream_writeInt32(stream, channelFlags);
    xstream_writeInt32(stream, totalLen);
    xstream_writeInt32(stream, dataLen);
    xstream_writeData(stream, (void*)data, dataLen);
    
    _SendMsg(agentIpc, stream);

    xstream_free(stream);
}

bool Command::_SendMsg(xipc_t* ipc, xstream_t* stream) {
    if (ipc == NULL || stream == NULL) {
        return false;
    }
    
    int bufferLen = 0;
    const void* buffer = xstream_get_raw_buffer(stream, &bufferLen);
    if (buffer == NULL || bufferLen <= 0 || bufferLen >= MAX_BUFFER) {
        return false;
    }

    return xipc_send_data(ipc, buffer, bufferLen) >= 0;
}
