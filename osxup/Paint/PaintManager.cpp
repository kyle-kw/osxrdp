#include "../pch.h"
#include "../osxup.h"
#include "PaintManager.h"
#include "osxrdp/packet.h"
#include "PaintBitmap.h"
#include "PaintH264.h"
#include "PaintRFX.h"
#include "FrameSelection.h"
#include "CursorSnapshot.h"
#include "utils.h"
#include <stdio.h>
#include <unistd.h>
#include <time.h>

static const char* OSXRDP_CURSORSHM_NAME = "/osxrdpcursorshm";

static uint64_t MonotonicNanos() {
    struct timespec ts = {0, 0};
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ((uint64_t)ts.tv_sec * 1000000000ULL) + (uint64_t)ts.tv_nsec;
}

PaintManager::PaintManager() :
    _inited(false),
    _mod(NULL),
    _paint(NULL),
    _cursorShm(NULL),
    _lastCursorGeneration(0),
    _inPainting(false),
    _releasePending(false),
    _recordShmCnt(0),
    _sessionId(0),
    _recordFormat(-1),
    _submittedFrameCount(0),
    _ackedFrameCount(0),
    _skippedFrameCount(0),
    _rfxFullRedrawRequestCount(0),
    _isLockScreen(false)
{
    memset(_submittedFrameIds, 0, sizeof(_submittedFrameIds));
    memset(_submittedAtNanos, 0, sizeof(_submittedAtNanos));
    for (int i = 0; i < 16; i++) {
        _recordShm[i] = NULL;
        _needPaintDisplay[i] = 0;
        _lastSubmittedPos[i] = 0;
        _hasLastSubmittedPos[i] = false;
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

    if (get_object_name(sessionId, OSXRDP_SCREENRECORD_SHM_NAME,
                        shm_name, sizeof(shm_name), isLockScreen) == 0) {
        // log
        return false;
    }

    bool hasCompatibleRecordShm = false;
    for (int i = 0; i < monitorCount; i++) {
        char shm_name_with_idx[512];
        snprintf(shm_name_with_idx, sizeof(shm_name_with_idx), "%s_%d", shm_name, i);

        // SHM may exist only for some output monitors (e.g. lock screen).
        _recordShm[i] = xshm_open(shm_name_with_idx);

        if (_recordShm[i] != NULL &&
            !osxrdp_screenrecord_shm_is_compatible(
                (const screenrecord_shm_t*)_recordShm[i]->mem,
                _recordShm[i]->size)) {
            ReleaseResources();
            return false;
        }
        if (_recordShm[i] != NULL) {
            hasCompatibleRecordShm = true;
        }

        if (mod->client_info.display_sizes.monitorCount == 0 && _recordShm[i] == NULL) {
            // log
            ReleaseResources();
            return false;
        }

        _recordShmCnt++;
    }
    if (!hasCompatibleRecordShm) {
        ReleaseResources();
        return false;
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
    
    if (recordFormat == OSXRDP_RECORDFORMAT_NV12_PACKED ||
        recordFormat == OSXRDP_RECORDFORMAT_NV12_ALIGNED ||
        recordFormat == OSXRDP_RECORDFORMAT_H264_ANNEXB) {
        _paint = new PaintH264(recordFormat == OSXRDP_RECORDFORMAT_H264_ANNEXB);
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
    _recordFormat = recordFormat;
    _isLockScreen = isLockScreen;
    _releasePending = false;
    _inFlightTracker.Reset();
    _lastCursorGeneration = 0;
    memset(_submittedFrameIds, 0, sizeof(_submittedFrameIds));
    memset(_submittedAtNanos, 0, sizeof(_submittedAtNanos));
    _submittedFrameCount = 0;
    _ackedFrameCount = 0;
    _skippedFrameCount = 0;
    _rfxFullRedrawRequestCount = 0;
    for (int i = 0; i < 16; i++) {
        _lastSubmittedPos[i] = 0;
        _hasLastSubmittedPos[i] = false;
    }
    
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

bool PaintManager::ReinitializeForResize(int requestedRecordFormat) {
    const struct mod* savedMod = _mod;
    int savedSessionId = _sessionId;
    bool savedIsLockScreen = _isLockScreen;
    int recordFormat = requestedRecordFormat >= 0 ? requestedRecordFormat : _recordFormat;

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
    if (_submittedFrameCount > 0 || _skippedFrameCount > 0 ||
        _rfxFullRedrawRequestCount > 0) {
        fprintf(stderr,
                "[osxup][paint] summary submitted=%llu acked=%llu skipped=%llu rfx_full_redraw=%llu\n",
                (unsigned long long)_submittedFrameCount,
                (unsigned long long)_ackedFrameCount,
                (unsigned long long)_skippedFrameCount,
                (unsigned long long)_rfxFullRedrawRequestCount);
    }
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
        _lastSubmittedPos[i] = 0;
        _hasLastSubmittedPos[i] = false;
    }
    _recordShmCnt = 0;
    
    if (_cursorShm != NULL) {
        xshm_close(_cursorShm);
        xshm_destroy(_cursorShm);
        
        _cursorShm = NULL;
    }
    _lastCursorGeneration = 0;
    
    _mod = NULL;
    _recordFormat = -1;
    _inFlightTracker.Reset();
    memset(_submittedFrameIds, 0, sizeof(_submittedFrameIds));
    memset(_submittedAtNanos, 0, sizeof(_submittedAtNanos));
    _submittedFrameCount = 0;
    _ackedFrameCount = 0;
    _skippedFrameCount = 0;
    _rfxFullRedrawRequestCount = 0;
    _inPainting = false;
    _releasePending = false;
    _inited = false;
}

bool PaintManager::Paint() {
    if (_inited == false || _paint == NULL || _recordShmCnt == 0 || _cursorShm == NULL) {
        return true;
    }

    // During reconnection, stop submitting new paints to previous shared memory
    // and only wait for existing in-flight frame ACKs.
    if (_releasePending == true) {
        return true;
    }
    
    // Draw mouse cursor
    PaintMouseCursor();
    
    if (_inFlightTracker.TotalCount() >= FRAME_SLOTS * _recordShmCnt) {
        return true;
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
            _lastSubmittedPos[i] = shm_frame_id;
            _hasLastSubmittedPos[i] = true;
            _inPainting = (_inFlightTracker.TotalCount() > 0);

            const unsigned int trackerSlot =
                frame_id % InFlightTracker::IN_FLIGHT_SLOT_COUNT;
            _submittedFrameIds[trackerSlot] = frame_id;
            _submittedAtNanos[trackerSlot] = MonotonicNanos();
            _submittedFrameCount++;
            if (_submittedFrameCount == 1 || (_submittedFrameCount % 120) == 0) {
                fprintf(stderr,
                        "[osxup][paint] submit display=%d shm_pos=%u frame_id=%u submitted=%llu skipped=%llu\n",
                        i, shm_frame_id, frame_id,
                        (unsigned long long)_submittedFrameCount,
                        (unsigned long long)_skippedFrameCount);
            }

            // A failed painter cannot produce an ACK. Roll back the tracker tail and
            // terminate the session rather than pinning the SHM ring forever.
            if (_paint->DoPaint(_mod, frameInfo, imgData, imgDataSize, frame_id, i, width, height) == false) {
                _inFlightTracker.CancelLatest(frame_id);
                _submittedFrameIds[trackerSlot] = 0;
                _submittedAtNanos[trackerSlot] = 0;
                _hasLastSubmittedPos[i] =
                    _inFlightTracker.GetLastPositionByDisplay(i, &_lastSubmittedPos[i]);
                _inPainting = (_inFlightTracker.TotalCount() > 0);
                return false;
            }
            
            cnt++;
        }
    }
    return true;
}

bool PaintManager::GetPaintData(screenrecord_frame_t** outFrameInfo, char** outImgData, size_t* outImgDataSize, int* outWidth, int* outHeight, unsigned int* frame_id, int displayIdx) {
    if (displayIdx < 0 || displayIdx >= 16 || _recordShm[displayIdx] == NULL || _recordShm[displayIdx]->mem == NULL) {
        return false;
    }

    xshm_t* recordShm = _recordShm[displayIdx];
    if (!osxrdp_screenrecord_shm_is_compatible(
            (const screenrecord_shm_t*)recordShm->mem, recordShm->size)) {
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

    int displayInFlightCount = _inFlightTracker.CountByDisplay(displayIdx);
    bool selfContained = (_paint == NULL || _paint->FrameIsSelfContained() == true);
    FrameSelectionDecision decision = SelectFramePosition(
        read_pos, write_pos, displayInFlightCount,
        _hasLastSubmittedPos[displayIdx], _lastSubmittedPos[displayIdx],
        selfContained);
    if (decision.requestRFXFullRedraw) {
        atomic_store_explicit(&shm->consumer_request_full, 1, memory_order_release);
        atomic_store_explicit(&shm->read_pos, write_pos, memory_order_release);
        _hasLastSubmittedPos[displayIdx] = false;
        _rfxFullRedrawRequestCount++;
        fprintf(stderr,
                "[osxup][paint] rfx_full_redraw display=%d read=%u write=%u requests=%llu\n",
                displayIdx, read_pos, write_pos,
                (unsigned long long)_rfxFullRedrawRequestCount);
        return false;
    }
    if (!decision.hasFrame) {
        return false;
    }
    unsigned int targetPos = decision.targetPos;
    
    unsigned int idx = targetPos % FRAME_SLOTS;
    size_t slotSize = (size_t)shm->screenrecord_data_size;
    if (idx != 0 && slotSize > SIZE_MAX / (size_t)idx) return false;
    size_t slotOffset = slotSize * (size_t)idx;
    size_t dataOffset = offsetof(screenrecord_shm_t, screenrecord_datas);
    if (slotOffset > SIZE_MAX - dataOffset ||
        slotSize > SIZE_MAX - (dataOffset + slotOffset)) return false;
    size_t minMapped = dataOffset + slotOffset + slotSize;
    // screenrecord_datas is the flexible tail; validate against mapped region size.
    if (minMapped > recordShm->size) {
        return false;
    }

    screenrecord_frame_t* frame = &(shm->frames[idx]);
    char* imgData = shm->screenrecord_datas + slotOffset;

    size_t imgDataSize = 0;
    memcpy(&imgDataSize, imgData, sizeof(size_t));

    // abnormal data --> skip it (size field is payload length; must fit after the size header)
    if (imgDataSize == 0 || (sizeof(size_t) + imgDataSize) > (size_t)shm->screenrecord_data_size)
        return false;

    if (decision.forceFullDirty) {
        frame->updateKind = OSXRDP_FRAME_UPDATE_FULL;
        frame->payloadFlags |= OSXRDP_FRAME_PAYLOAD_FORCE_FULL;
        frame->dirtyCount = 0;
    }
    if (decision.skippedFrames > 0) {
        uint64_t previousSkipped = _skippedFrameCount;
        _skippedFrameCount += decision.skippedFrames;
        if (previousSkipped == 0 ||
            previousSkipped / 120 != _skippedFrameCount / 120) {
            fprintf(stderr,
                    "[osxup][paint] chase_latest display=%d read=%u write=%u submit=%u skipped_now=%llu skipped_total=%llu\n",
                    displayIdx, read_pos, write_pos, targetPos,
                    (unsigned long long)decision.skippedFrames,
                    (unsigned long long)_skippedFrameCount);
        }
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

    uint64_t nowNanos = MonotonicNanos();
    uint64_t oldestSubmittedAt = 0;
    for (int i = 0; i < InFlightTracker::IN_FLIGHT_SLOT_COUNT; i++) {
        unsigned int submittedFrameId = _submittedFrameIds[i];
        if (submittedFrameId == 0 ||
            (ackFrameId >= 0 && (int)submittedFrameId > ackFrameId)) continue;
        uint64_t submittedAt = _submittedAtNanos[i];
        if (submittedAt != 0 && (oldestSubmittedAt == 0 || submittedAt < oldestSubmittedAt)) {
            oldestSubmittedAt = submittedAt;
        }
    }

    int popped = _inFlightTracker.PopAcked(ackFrameId, maxReadPosByDisplay, hasReadPosByDisplay);
    if (popped <= 0) {
        _inPainting = (_inFlightTracker.TotalCount() > 0);
        return;
    }

    for (int i = 0; i < InFlightTracker::IN_FLIGHT_SLOT_COUNT; i++) {
        unsigned int submittedFrameId = _submittedFrameIds[i];
        if (submittedFrameId != 0 &&
            (ackFrameId < 0 || (int)submittedFrameId <= ackFrameId)) {
            _submittedFrameIds[i] = 0;
            _submittedAtNanos[i] = 0;
        }
    }
    _ackedFrameCount += (uint64_t)popped;
    double ackLatencyMs = (oldestSubmittedAt != 0 && nowNanos >= oldestSubmittedAt)
        ? (double)(nowNanos - oldestSubmittedAt) / 1000000.0 : 0.0;
    bool periodicAckLog = _ackedFrameCount == (uint64_t)popped ||
        (_ackedFrameCount % 120) < (uint64_t)popped;
    bool slowAckLog = ackLatencyMs >= 33.3 &&
        (_ackedFrameCount % 30) < (uint64_t)popped;
    if (periodicAckLog || slowAckLog) {
        fprintf(stderr,
                "[osxup][paint] ack frame_id=%d popped=%d latency_ms=%.2f acked=%llu in_flight=%d\n",
                ackFrameId, popped, ackLatencyMs,
                (unsigned long long)_ackedFrameCount,
                _inFlightTracker.TotalCount());
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

        if (_inFlightTracker.CountByDisplay(i) == 0) {
            _hasLastSubmittedPos[i] = false;
        }
        else {
            _hasLastSubmittedPos[i] =
                _inFlightTracker.GetLastPositionByDisplay(i, &_lastSubmittedPos[i]);
        }
    }
    
    _inPainting = (_inFlightTracker.TotalCount() > 0);
}

void PaintManager::PaintMouseCursor() {
    if (_cursorShm == NULL || _cursorShm->mem == NULL || _mod == NULL) {
        return;
    }

    cursor_data_t* cursorData = (cursor_data_t*)_cursorShm->mem;
    CursorSnapshot snapshot = {};
    if (!TryCopyCursorSnapshot(cursorData, _lastCursorGeneration, &snapshot)) return;

    _mod->server_set_pointer_large((struct mod*)_mod,
                                   snapshot.hotspotX, snapshot.hotspotY,
                                   snapshot.image, snapshot.mask, 32,
                                   snapshot.width, snapshot.height);
    _lastCursorGeneration = snapshot.generation;
}
