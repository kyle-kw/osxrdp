#include "../pch.h"
#include "../osxup.h"
#include "PaintManager.h"
#include "osxrdp/packet.h"
#include "PaintBitmap.h"
#include "PaintH264.h"
#include "PaintRFX.h"
#include "utils.h"
#include <unistd.h>

static const char* OSXRDP_SCREENSHM_NAME = "/osxrdpshm";
static const char* OSXRDP_CURSORSHM_NAME = "/osxrdpcursorshm";

PaintManager::PaintManager() :
    _inited(false),
    _mod(NULL),
    _paint(NULL),
    _cursorShm(NULL),
    _inPainting(false),
    _releasePending(false),
    _recordShmCnt(0),
    _sessionId(0),
    _isLockScreen(false)
{
    for (int i = 0; i < 16; i++) {
        _recordShm[i] = NULL;
        _needPaintDisplay[i] = 0;
    }
}

PaintManager::~PaintManager() {
    Release();
}

int PaintManager::CheckRecordFormat(const struct mod* mod) {
    assert(mod != NULL);
    if (mod == NULL) return -1;
    
    if (mod->client_info.gfx == 1) {
        if (mod->client_info.capture_code == CC_GFX_A2) {
            // using H.264
            if (mod->usevtoolbox == 1) {
                return OSXRDP_RECORDFORMAT_NV12_ALIGNED;
            }
            else {
                return OSXRDP_RECORDFORMAT_NV12_PACKED;
            }
        }
        
        return OSXRDP_RECORDFORMAT_RFX;
    }
    else {
        return OSXRDP_RECORDFORMAT_BGRA32;
    }
}

int PaintManager::Initialize(const struct mod* mod, int recordFormat, int sessionId, bool isLockScreen) {
    assert(mod != NULL);
    assert(recordFormat >= 0);
    assert(_recordShmCnt == 0);
    assert(_inited == false);
    
    if (_inited == true) {
        return false;
    }
    
    if (mod == NULL || recordFormat < 0) {
        // log
        return false;
    }
    
    char shm_name[512] = {0,};
    int monitorCount = mod->client_info.display_sizes.monitorCount;
    if (monitorCount == 0) {
        monitorCount = 1;
    }

    if (monitorCount > 16) {
        monitorCount = 16;
    }

    if (get_object_name(sessionId, OSXRDP_SCREENSHM_NAME, shm_name, sizeof(shm_name), isLockScreen) == 0) {
        // log
        return false;
    }

    for (int i = 0; i < monitorCount; i++) {
        char shm_name_with_idx[512];
        snprintf(shm_name_with_idx, sizeof(shm_name_with_idx), "%s_%d", shm_name, i);

        // SHM may exist only for some output monitors (e.g. lock screen).
        _recordShm[i] = xshm_open(shm_name_with_idx);

        if (mod->client_info.display_sizes.monitorCount == 0 && _recordShm[i] == NULL) {
            // log
            ReleaseResources();
            return false;
        }

        _recordShmCnt++;
    }
    
    if (get_object_name(sessionId, OSXRDP_CURSORSHM_NAME, shm_name, sizeof(shm_name), isLockScreen) == 0) {
        // log
        ReleaseResources();
        return false;
    }
    
    // Open shared memory containing cursor data
    _cursorShm = xshm_open(shm_name);
    if (_cursorShm == NULL) {
        // log
        ReleaseResources();
        return false;
    }
    
    if (recordFormat == OSXRDP_RECORDFORMAT_NV12_PACKED || recordFormat == OSXRDP_RECORDFORMAT_NV12_ALIGNED) {
        _paint = new PaintH264();
    }
    else if (recordFormat == OSXRDP_RECORDFORMAT_RFX) {
        _paint = new PaintRFX();
    }
    else {
        _paint = new PaintBitmap();
    }

    if (_paint == NULL) {
        ReleaseResources();
        return false;
    }
    
    // painter initialize
    _paint->Initialize(mod);
    
    _mod = mod;
    _sessionId = sessionId;
    _isLockScreen = isLockScreen;
    _releasePending = false;
    _inFlightTracker.Reset();
    
    _inited = true;
    
    return true;
}

void PaintManager::Release() {
    _releasePending = false;
    ReleaseResources();
}

bool PaintManager::TryReleaseForReconnect() {
    if (_inited == false && _recordShmCnt == 0 && _cursorShm == NULL && _paint == NULL) {
        return true;
    }

    _releasePending = true;

    if (_inFlightTracker.TotalCount() > 0) {
        return false;
    }

    ReleaseResources();
    _releasePending = false;
    return true;
}

bool PaintManager::ReinitializeForResize() {
    const struct mod* savedMod = _mod;
    int savedSessionId = _sessionId;
    bool savedIsLockScreen = _isLockScreen;
    int recordFormat = CheckRecordFormat(savedMod);

    for (int attempt = 0; attempt < 3; attempt++) {
        ReleaseResources();
        if (Initialize(savedMod, recordFormat, savedSessionId, savedIsLockScreen) == true) {
            return true;
        }
        usleep(100 * 1000); // 100ms
    }

    return false;
}

void PaintManager::ReleaseResources() {
    if (_paint != NULL) {
        delete _paint;
        _paint = NULL;
    }

    // close shm
    for (int i = 0; i < 16; i++) {
        if (_recordShm[i] != NULL) {
            xshm_close(_recordShm[i]);
            xshm_destroy(_recordShm[i]);
            _recordShm[i] = NULL;
        }
        
        _needPaintDisplay[i] = 0;
    }
    _recordShmCnt = 0;
    
    if (_cursorShm != NULL) {
        xshm_close(_cursorShm);
        xshm_destroy(_cursorShm);
        
        _cursorShm = NULL;
    }
    
    _mod = NULL;
    _inFlightTracker.Reset();
    _inPainting = false;
    _releasePending = false;
    _inited = false;
}

void PaintManager::Paint() {
    if (_inited == false || _paint == NULL || _recordShmCnt == 0 || _cursorShm == NULL) {
        return;
    }

    // During reconnection, stop submitting new paints to previous shared memory
    // and only wait for existing in-flight frame ACKs.
    if (_releasePending == true) {
        return;
    }
    
    // Draw mouse cursor
    PaintMouseCursor();
    
    if (_inFlightTracker.TotalCount() >= FRAME_SLOTS * _recordShmCnt) {
        return;
    }
    
    for (int i = 0; i < _recordShmCnt; i++) {
        // Check if it's a valid display to paint
        if (_recordShm[i] == NULL)
            continue;

        _needPaintDisplay[i] = 0;

        // Paint up to 3 times while in-flight capacity is available
        int cnt = 0;
        while (_inFlightTracker.CountByDisplay(i) < FRAME_SLOTS && cnt < 3) {
            screenrecord_frame_t* frameInfo = NULL;
            char* imgData = NULL;
            size_t imgDataSize = 0;
            int width = 0;
            int height = 0;
            unsigned int shm_frame_id = 0;

            // Check if there is data to read
            if (GetPaintData(&frameInfo, &imgData, &imgDataSize, &width, &height, &shm_frame_id, i) == false) {
                break;
            }

            unsigned int frame_id = 0;
            if (_inFlightTracker.Push(i, shm_frame_id, &frame_id) == false) {
                break;
            }
            _inPainting = (_inFlightTracker.TotalCount() > 0);

            // Paint
            _paint->DoPaint(_mod, frameInfo, imgData, imgDataSize, frame_id, i, width, height);
            
            cnt++;
        }
    }
}

bool PaintManager::GetPaintData(screenrecord_frame_t** outFrameInfo, char** outImgData, size_t* outImgDataSize, int* outWidth, int* outHeight, unsigned int* frame_id, int displayIdx) {
    if (displayIdx < 0 || displayIdx >= 16 || _recordShm[displayIdx] == NULL || _recordShm[displayIdx]->mem == NULL) {
        return false;
    }

    xshm_t* recordShm = _recordShm[displayIdx];
    if (recordShm->size < sizeof(screenrecord_shm_t)) {
        return false;
    }

    screenrecord_shm_t* shm = (screenrecord_shm_t*)recordShm->mem;

    // Check if there is data to read
    unsigned int read_pos = atomic_load_explicit(&shm->read_pos,  memory_order_acquire);
    unsigned int write_pos = atomic_load_explicit(&shm->write_pos, memory_order_acquire);

    if (read_pos == write_pos) {
        return false;
    }

    if (shm->screenrecord_data_size <= sizeof(size_t) || shm->width <= 0 || shm->height <= 0) {
        return false;
    }

    int forceRedrawAll = 0;
    int displayInFlightCount = _inFlightTracker.CountByDisplay(displayIdx);
    unsigned int targetPos = read_pos + (unsigned int)displayInFlightCount;
    if (targetPos >= write_pos) {
        return false;
    }

    bool selfContained = (_paint == NULL || _paint->FrameIsSelfContained() == true);
    bool trueBacklog = (displayInFlightCount == 0 && (write_pos - read_pos >= FRAME_SLOTS));
    
    // How to handle backlog
    //   - self-contained format (BGRA32 / NV12) : jump to latest slot and process full.
    //   - partial-frame format (RFX)          : cannot reconstruct intermediate dirty tiles, so drop entire backlog and request full redraw from producer. Skip this paint.
    if (selfContained == false) {
        if (trueBacklog == true) {
            atomic_store_explicit(&shm->consumer_request_full, 1, memory_order_release);
            atomic_store_explicit(&shm->read_pos, write_pos, memory_order_release);
            return false;
        }
    }
    else {
        if (trueBacklog == true || (displayInFlightCount == 0 && read_pos == 0)) {
            targetPos = write_pos - 1;
            forceRedrawAll = 1;
        }
    }
    
    unsigned int idx = targetPos % FRAME_SLOTS;
    size_t slotOffset = (size_t)shm->screenrecord_data_size * (size_t)idx;
    size_t minMapped = sizeof(screenrecord_shm_t) + slotOffset + (size_t)shm->screenrecord_data_size;
    // screenrecord_datas is the flexible tail; validate against mapped region size.
    if (minMapped > recordShm->size) {
        return false;
    }

    screenrecord_frame_t* frame = &(shm->frames[idx]);
    char* imgData = *(&shm->screenrecord_datas + slotOffset);

    size_t imgDataSize = 0;
    memcpy(&imgDataSize, imgData, sizeof(size_t));

    // abnormal data --> skip it (size field is payload length; must fit after the size header)
    if (imgDataSize == 0 || (sizeof(size_t) + imgDataSize) > (size_t)shm->screenrecord_data_size)
        return false;

    if (forceRedrawAll != 0) {
        frame->dirtyCount = 0;
    }

    *outFrameInfo = frame;
    *outImgData = imgData + sizeof(size_t);
    *outImgDataSize = imgDataSize;
    *outWidth = shm->width;
    *outHeight = shm->height;

    *frame_id = targetPos;

    //atomic_store_explicit(&shm->read_pos, read_pos + 1, memory_order_release);

    return true;
}

void PaintManager::PaintEnd(int ackFrameId) {
    if (_inited == false || _recordShmCnt == 0) {
        _inPainting = false;
        return;
    }
    
    if (_inFlightTracker.TotalCount() <= 0) {
        _inPainting = false;
        return;
    }

    unsigned int maxReadPosByDisplay[16] = {0,};
    bool hasReadPosByDisplay[16] = {false,};

    int popped = _inFlightTracker.PopAcked(ackFrameId, maxReadPosByDisplay, hasReadPosByDisplay);
    if (popped <= 0) {
        _inPainting = (_inFlightTracker.TotalCount() > 0);
        return;
    }

    for (int i = 0; i < _recordShmCnt; i++) {
        if (hasReadPosByDisplay[i] == false) {
            continue;
        }
        if (_recordShm[i] == NULL || _recordShm[i]->mem == NULL) {
            continue;
        }

        screenrecord_shm_t* shm = (screenrecord_shm_t*)_recordShm[i]->mem;
        unsigned int read_pos = atomic_load_explicit(&shm->read_pos, memory_order_relaxed);
        unsigned int nextReadPos = maxReadPosByDisplay[i] + 1;

        if (nextReadPos > read_pos) {
            atomic_store_explicit(&shm->read_pos, nextReadPos, memory_order_release);
        }
    }
    
    _inPainting = (_inFlightTracker.TotalCount() > 0);
}

void PaintManager::PaintMouseCursor() {
    if (_cursorShm == NULL || _cursorShm->mem == NULL || _mod == NULL) {
        return;
    }

    cursor_data_t* cursorData = (cursor_data_t*)_cursorShm->mem;
    
    int updated = atomic_load_explicit(&cursorData->updated,  memory_order_acquire);
    if (updated == 1) {
        int width = cursorData->width;
        int height = cursorData->height;
        if (width <= 0 || height <= 0 ||
            width > MAX_CURSOR_IMG_BUFFER_SIZE ||
            height > MAX_CURSOR_IMG_BUFFER_SIZE) {
            atomic_store_explicit(&cursorData->updated, 0, memory_order_release);
            return;
        }

        _mod->server_set_pointer_large((struct mod*)_mod, cursorData->hotspotX, cursorData->hotspotY, cursorData->cursorImgData, cursorData->cursorMaskData, 32, width, height);
        
        atomic_store_explicit(&cursorData->updated, 0, memory_order_release);
    }
}
