#include "../pch.h"
#include "PaintH264.h"
#include "../osxup.h"
#include <limits.h>


typedef struct _XRDP_EFGX_CMD_HEADER {
    short cmdId;
    short flags;
    int pduLength; // header + body size
} __attribute__((packed)) XRDP_EFGX_CMD_HEADER;

typedef struct _XRDP_EGFX_CREATE_SURFACE {
    XRDP_EFGX_CMD_HEADER header;
    short surfaceId;
    short width;
    short height;
    char fmt;
} __attribute__((packed)) XRDP_EGFX_CREATE_SURFACE;

typedef struct _XRDP_EGFX_START_FRAME {
    XRDP_EFGX_CMD_HEADER header;
    int frame_id;
    int timestamp;
} __attribute__((packed)) XRDP_EGFX_START_FRAME;

typedef struct _XRDP_EGFX_END_FRAME {
    XRDP_EFGX_CMD_HEADER header;
    int frame_id;
} __attribute__((packed)) XRDP_EGFX_END_FRAME;

typedef struct _XRDP_EGFX_MAP_SURFACE_TO_OUTPUT {
    XRDP_EFGX_CMD_HEADER header;
    short surfaceId;
    int outputX;
    int outputY;
} __attribute__((packed)) XRDP_EGFX_MAP_SURFACE_TO_OUTPUT;

typedef struct _XRDP_EGFX_RESET_GRAPHICS_PDU {
    XRDP_EFGX_CMD_HEADER header;
    int width;
    int height;
    int monitor_count;
    // TODO : dynamic
    int left;
    int top;
    int right;
    int bottom;
    int is_primary;
} __attribute__((packed)) XRDP_EGFX_RESET_GRAPHICS_PDU;

void PaintH264::Initialize(const struct mod* mod) {
    /*
    XRDP_EGFX_RESET_GRAPHICS_PDU reset;
    reset.header.cmdId = 0x0E;
    reset.header.flags = 0;
    reset.header.pduLength = sizeof(reset);
    
    reset.width = mod->width;
    reset.height = mod->height;
    reset.monitor_count = 1;
    reset.top = 0;
    reset.left = 0;
    reset.right = mod->width;
    reset.bottom = mod->height;
    reset.is_primary = 1;
    
    mod->server_egfx_cmd((struct mod*)mod, (char*)&reset, sizeof(reset), NULL, 0);
    
    
    XRDP_EGFX_CREATE_SURFACE cmd;
    cmd.header.cmdId = 0x0009;
    cmd.header.flags = 0;
    cmd.header.pduLength = sizeof(cmd);
    
    cmd.surfaceId = 0;
    cmd.width = mod->width;
    cmd.height = mod->height;
    cmd.fmt = 0x20;
    
    mod->server_egfx_cmd((struct mod*)mod, (char*)&cmd, sizeof(cmd), NULL, 0);

    
    XRDP_EGFX_MAP_SURFACE_TO_OUTPUT output;
    output.header.cmdId = 0x0F;
    output.header.flags = 0;
    output.header.pduLength = sizeof(output);
    
    output.surfaceId = 0;
    output.outputX = 0;
    output.outputY = 0;
    
    mod->server_egfx_cmd((struct mod*)mod, (char*)&output, sizeof(output), NULL, 0);
     */
    
    _drawCmd = xstream_create(8192);
}

void PaintH264::Release() {
    if (_drawCmd != NULL) {
        xstream_free(_drawCmd);
        _drawCmd = NULL;
    }
}

bool PaintH264::DoPaint(const struct mod* mod, screenrecord_frame_t* frameInfo, char* imgData, size_t imgDataSize, int frame_id, int displayId, int width, int height) {
    assert(mod != NULL);
    assert(frameInfo != NULL);
    assert(imgData != NULL);

    if (_drawCmd == NULL || displayId < 0 || displayId >= 16 || width <= 0 || height <= 0 ||
        imgDataSize == 0 || imgDataSize > INT_MAX) {
        return false;
    }
    if (_alreadyCompressed &&
        (frameInfo->payloadFlags & OSXRDP_FRAME_PAYLOAD_H264_ANNEXB) == 0) {
        return false;
    }
    
    XRDP_EGFX_START_FRAME startCmd;
    startCmd.header.cmdId = 11;
    startCmd.header.flags = 0;
    startCmd.header.pduLength = sizeof(startCmd);
    startCmd.timestamp = 0;
    startCmd.frame_id = frame_id;
    
    if (mod->server_egfx_cmd((struct mod*)mod, (char*)&startCmd, sizeof(startCmd), NULL, 0) != 0) {
        return false;
    }
    
    xstream_resetPos(_drawCmd);
    
    // header
    if (xstream_writeInt16(_drawCmd, 0x1) != 0 ||
        xstream_writeInt16(_drawCmd, 0) != 0 ||
        xstream_writeInt32(_drawCmd, 0) != 0) {
        return false;
    }
    
    // body
    if (xstream_writeInt16(_drawCmd, displayId) != 0 ||
        xstream_writeInt16(_drawCmd, 0x000B) != 0 ||
        xstream_writeInt8(_drawCmd, 0x20) != 0 ||
        xstream_writeInt32(_drawCmd,
            osxrdp_gfx_h264_surface_flags(displayId, _alreadyCompressed)) != 0) {
        return false;
    }

    int rectsStart = xstream_getPosition(_drawCmd);
    
    // rects
    if (frameInfo->updateKind == OSXRDP_FRAME_UPDATE_DIRTY &&
        frameInfo->dirtyCount > 0 && frameInfo->dirtyCount <= MAX_DIRTY_COUNT) {
        if (xstream_writeInt16(_drawCmd, frameInfo->dirtyCount) != 0) return false;
        
        for (int i = 0; i < frameInfo->dirtyCount; i++) {
            if (xstream_writeInt16(_drawCmd, frameInfo->dirtys[i].x) != 0 ||
                xstream_writeInt16(_drawCmd, frameInfo->dirtys[i].y) != 0 ||
                xstream_writeInt16(_drawCmd, frameInfo->dirtys[i].width) != 0 ||
                xstream_writeInt16(_drawCmd, frameInfo->dirtys[i].height) != 0) return false;
        }
    }
    else {
        if (xstream_writeInt16(_drawCmd, 1) != 0 ||
            xstream_writeInt32(_drawCmd, 0) != 0 ||
            xstream_writeInt16(_drawCmd, width) != 0 ||
            xstream_writeInt16(_drawCmd, height) != 0) return false;
    }
    
    // Copy once more (as-is)
    int rectsDataLen = xstream_getPosition(_drawCmd) - rectsStart;
    int rawLen = 0;
    const char* raw = (const char*)xstream_get_raw_buffer(_drawCmd, &rawLen);
    if (rectsStart < 0 || rectsDataLen <= 0 || raw == NULL ||
        xstream_writeData(_drawCmd, (void*)(raw + rectsStart), rectsDataLen) != 0 ||
        xstream_writeInt32(_drawCmd, 0) != 0 ||
        xstream_writeInt16(_drawCmd, width) != 0 ||
        xstream_writeInt16(_drawCmd, height) != 0) return false;

    int dataLen = xstream_getPosition(_drawCmd);
    if (xstream_patchInt32(_drawCmd, sizeof(int), dataLen) != 0) return false;
    raw = (const char*)xstream_get_raw_buffer(_drawCmd, &rawLen);
    int drawResult = mod->server_egfx_cmd((struct mod*)mod, (char*)raw, dataLen, imgData, (int)imgDataSize);

    XRDP_EGFX_END_FRAME endCmd;
    endCmd.header.cmdId = 12;
    endCmd.header.flags = 0;
    endCmd.header.pduLength = sizeof(endCmd);
    endCmd.frame_id = frame_id;
    
    int endResult = mod->server_egfx_cmd((struct mod*)mod, (char*)&endCmd, sizeof(endCmd), NULL, 0);
    return drawResult == 0 && endResult == 0;
}
