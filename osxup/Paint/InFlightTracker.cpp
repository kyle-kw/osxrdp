#include "InFlightTracker.h"

InFlightTracker::InFlightTracker() :
    _freeInFlightCount(0),
    _inFlightHead(0),
    _inFlightCount(0),
    _nextFrameGeneration(1)
{
    for (int i = 0; i < 16; i++) {
        _inFlightCountByDisplay[i] = 0;
    }
    Reset();
}

bool InFlightTracker::Push(int displayIdx, unsigned int shmReadPos, unsigned int* outFrameId) {
    if (displayIdx < 0 || displayIdx >= 16) {
        return false;
    }

    if (outFrameId == NULL) {
        return false;
    }

    if (_freeInFlightCount <= 0) {
        return false;
    }

    if (_inFlightCountByDisplay[displayIdx] >= FRAME_SLOTS) {
        return false;
    }

    if (_nextFrameGeneration >= 0x7FFFFFFFU / IN_FLIGHT_SLOT_COUNT) {
        if (_inFlightCount > 0) {
            return false;
        }
        _nextFrameGeneration = 1;
    }

    int slot = _freeInFlightSlots[--_freeInFlightCount];
    unsigned int frameId = (_nextFrameGeneration * IN_FLIGHT_SLOT_COUNT) + (unsigned int)slot;
    _nextFrameGeneration++;

    _inFlightFrames[slot].frameId = frameId;
    _inFlightFrames[slot].displayIdx = displayIdx;
    _inFlightFrames[slot].shmReadPos = shmReadPos;
    _inFlightFrames[slot].inUse = true;

    int tail = (_inFlightHead + _inFlightCount) % IN_FLIGHT_SLOT_COUNT;
    _inFlightSlotQueue[tail] = slot;

    _inFlightCount++;
    _inFlightCountByDisplay[displayIdx]++;
    *outFrameId = frameId;
    return true;
}

int InFlightTracker::PopAcked(int ackFrameId, unsigned int* outMaxReadPosByDisplay, bool* outHasReadPosByDisplay) {
    int popped = 0;

    while (_inFlightCount > 0) {
        int slot = _inFlightSlotQueue[_inFlightHead];
        InFlightFrame* frame = &_inFlightFrames[slot];

        if (ackFrameId >= 0 && (int)frame->frameId > ackFrameId) {
            break;
        }

        int displayIdx = frame->displayIdx;
        if (displayIdx >= 0 && displayIdx < 16) {
            if (outMaxReadPosByDisplay != NULL) {
                outMaxReadPosByDisplay[displayIdx] = frame->shmReadPos;
            }
            if (outHasReadPosByDisplay != NULL) {
                outHasReadPosByDisplay[displayIdx] = true;
            }
            if (_inFlightCountByDisplay[displayIdx] > 0) {
                _inFlightCountByDisplay[displayIdx]--;
            }
        }

        frame->inUse = false;
        _freeInFlightSlots[_freeInFlightCount++] = slot;
        _inFlightHead = (_inFlightHead + 1) % IN_FLIGHT_SLOT_COUNT;
        _inFlightCount--;
        popped++;
    }

    return popped;
}

void InFlightTracker::Reset() {
    _freeInFlightCount = IN_FLIGHT_SLOT_COUNT;
    _inFlightHead = 0;
    _inFlightCount = 0;
    for (int i = 0; i < IN_FLIGHT_SLOT_COUNT; i++) {
        _inFlightFrames[i].frameId = 0;
        _inFlightFrames[i].displayIdx = 0;
        _inFlightFrames[i].shmReadPos = 0;
        _inFlightFrames[i].inUse = false;
        _inFlightSlotQueue[i] = 0;
        _freeInFlightSlots[i] = i;
    }
    for (int i = 0; i < 16; i++) {
        _inFlightCountByDisplay[i] = 0;
    }
}

int InFlightTracker::CountByDisplay(int displayIdx) const {
    if (displayIdx < 0 || displayIdx >= 16) return 0;
    return _inFlightCountByDisplay[displayIdx];
}
