#ifndef InFlightTracker_h
#define InFlightTracker_h

#include "osxrdp/screenrecordshm.h"

// Standalone in-flight frame tracker extracted from PaintManager.
// Pure data structure - no mod/paint/SHM dependencies.
class InFlightTracker {
public:
    static const int IN_FLIGHT_SLOT_COUNT = FRAME_SLOTS * 16;

    struct InFlightFrame {
        unsigned int frameId;
        int displayIdx;
        unsigned int shmReadPos;
        bool inUse;
    };

    InFlightTracker();

    bool Push(int displayIdx, unsigned int shmReadPos, unsigned int* outFrameId);
    bool CancelLatest(unsigned int frameId);
    bool GetLastPositionByDisplay(int displayIdx, unsigned int* outShmReadPos) const;
    int PopAcked(int ackFrameId, unsigned int* outMaxReadPosByDisplay, bool* outHasReadPosByDisplay);
    void Reset();

    int CountByDisplay(int displayIdx) const;
    int TotalCount() const { return _inFlightCount; }

private:
    InFlightFrame _inFlightFrames[IN_FLIGHT_SLOT_COUNT];
    int _inFlightSlotQueue[IN_FLIGHT_SLOT_COUNT];
    int _freeInFlightSlots[IN_FLIGHT_SLOT_COUNT];
    int _freeInFlightCount;
    int _inFlightCountByDisplay[16];
    int _inFlightHead;
    int _inFlightCount;
    unsigned int _nextFrameGeneration;
};

#endif
