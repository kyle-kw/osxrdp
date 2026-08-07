#include "../pch.h"
#include "ChannelManager.h"
#include "osxrdp/packet.h"
#include "../osxup.h"
#include "xstream.h"

static const int CB_MONITOR_READY = 1;
static const int CB_CLIP_CAPS = 7;

static const int CB_CAPSTYPE_GENERAL = 1;
static const int CB_CAPS_VERSION_2 = 2;

static const int CB_USE_LONG_FORMAT_NAMES = 0x00000002;
static const int CB_STREAM_FILECLIP_ENABLED = 0x00000004;
static const int CB_FILECLIP_NO_FILE_PATHS = 0x00000008;

ChannelManager::ChannelManager() :
    _inited(false),
    _mod(NULL),
    _clipboardChannelId(-1)
{}

ChannelManager::~ChannelManager()
{}


bool ChannelManager::Initialize(const struct mod* mod) {
    assert(mod != NULL);

    _mod = mod;
    _inited = true;
    
    // Get clipboard channel ID
    _clipboardChannelId = mod->server_get_channel_id((struct mod*)mod, CLIPRDR_SVC_CHANNEL_NAME);
    if (_clipboardChannelId < 0) {
        return false;
    }
    
    return true;
}

void ChannelManager::SendClipboardServerInit() {
    assert(_inited == true);
    assert(_mod != NULL);
    
    if (_inited == false || _mod == NULL || _clipboardChannelId < 0) {
        return;
    }

    // Set clipboard capabilities
    xstream_t* caps = xstream_create(28);
    if (caps != NULL) {
        int flags = CB_USE_LONG_FORMAT_NAMES |
                    CB_STREAM_FILECLIP_ENABLED |
                    CB_FILECLIP_NO_FILE_PATHS;

        xstream_writeInt16(caps, CB_CLIP_CAPS);
        xstream_writeInt16(caps, 0);
        xstream_writeInt32(caps, 16); // total data length
        xstream_writeInt16(caps, 1);
        xstream_writeInt16(caps, 0);
        xstream_writeInt16(caps, CB_CAPSTYPE_GENERAL);
        xstream_writeInt16(caps, 12); // subsequent data length
        xstream_writeInt32(caps, CB_CAPS_VERSION_2);
        xstream_writeInt32(caps, flags);
        xstream_writeInt32(caps, 0);

        _SendChannelData(caps);
        
        xstream_free(caps);
    }

    xstream_t* ready = xstream_create(12);
    if (ready != NULL) {
        xstream_writeInt16(ready, CB_MONITOR_READY);
        xstream_writeInt16(ready, 0);
        xstream_writeInt32(ready, 0);
        xstream_writeInt32(ready, 0);

        _SendChannelData(ready);
        
        xstream_free(ready);
    }
}

void ChannelManager::SendClipboardChannelData(const void* data, int dataLen, int totalLen, int channelFlags) {
    assert(_inited == true);
    assert(_mod != NULL);
    
    if (_mod == NULL || _clipboardChannelId < 0 || data == NULL || dataLen <= 0 || totalLen <= 0) {
        return;
    }

    _mod->server_send_to_channel((struct mod*)_mod, _clipboardChannelId, (char*)data, dataLen, totalLen, channelFlags);
}

void ChannelManager::Release() {
    _mod = NULL;
    _clipboardChannelId = -1;
    _inited = false;
}

// Only handle clipboard among RDP channels (for now)
int ChannelManager::IsValidChannelMsg(int channelId, int channelFlags, const char* data, int dataLen, int totalLen) {
    (void)channelFlags;
    (void)data;
    (void)dataLen;
    (void)totalLen;
    
    if (channelId == _clipboardChannelId) {
        return OSXRDP_CHANNEL_CLIPBOARD;
    }
    
    return OSXRDP_CHANNEL_INVALID;
}

void ChannelManager::_SendChannelData(xstream_t* stream) {
    if (_mod == NULL || _clipboardChannelId < 0 || stream == NULL) {
        return;
    }

    int bufferLen = 0;
    const void* buffer = xstream_get_raw_buffer(stream, &bufferLen);
    if (buffer == NULL || bufferLen <= 0) {
        return;
    }

    _mod->server_send_to_channel((struct mod*)_mod, _clipboardChannelId, (char*)buffer, bufferLen, bufferLen, XR_CHANNEL_FLAG_FIRST | XR_CHANNEL_FLAG_LAST);
}
