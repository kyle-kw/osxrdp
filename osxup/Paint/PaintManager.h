#ifndef PaintManager_h
#define PaintManager_h

#include "PaintBase.h"
#include "InFlightTracker.h"
#include "osxrdp/screenrecordshm.h"
#include "xshm.h"

struct mod;

class PaintManager {

public:
    PaintManager();
    ~PaintManager();
    
    int Initialize(const struct mod* mod, int recordFormat, int sessionId, bool isLockScreen);
    void Release();
    bool TryReleaseForReconnect();
    bool ReinitializeForResize();
    
    void Paint();
    void PaintEnd(int ackFrameId);
    
    // Not thread-safe, but safe because called from the same thread
    void PreparePaint(int displayIdx) {
        if (displayIdx >= 16) return;
        _needPaintDisplay[displayIdx] = 1;
    }
    
    static int CheckRecordFormat(const struct mod* mod);
    
private:
    bool _inited;
    PaintBase* _paint;
    
    xshm_t* _recordShm[16];
    int _recordShmCnt;
    
    xshm_t* _cursorShm;
    const struct mod* _mod;
    volatile bool _inPainting;
    volatile bool _releasePending;

    InFlightTracker _inFlightTracker;
    int _sessionId;
    int _needPaintDisplay[16];
    bool _isLockScreen;
    
    bool GetPaintData(screenrecord_frame_t** outFrameInfo, char** outImgData, size_t* outImgDataSize, int* outWidth, int* outHeight, unsigned int* frame_id, int displayIdx);
    void ReleaseResources();
    
    void PaintMouseCursor();
};

#endif
