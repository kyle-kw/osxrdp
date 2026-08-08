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

bool InFlightTracker::CancelLatest(unsigned int frameId) {
    if (_inFlightCount <= 0) {
        return false;
    }

    int tail = (_inFlightHead + _inFlightCount - 1) % IN_FLIGHT_SLOT_COUNT;
    int slot = _inFlightSlotQueue[tail];
    InFlightFrame* frame = &_inFlightFrames[slot];
    if (frame->inUse == false || frame->frameId != frameId) {
        return false;
    }

    if (frame->displayIdx >= 0 && frame->displayIdx < 16 &&
        _inFlightCountByDisplay[frame->displayIdx] > 0) {
        _inFlightCountByDisplay[frame->displayIdx]--;
    }
    frame->inUse = false;
    _freeInFlightSlots[_freeInFlightCount++] = slot;
    _inFlightCount--;
    return true;
}

bool InFlightTracker::GetLastPositionByDisplay(int displayIdx, unsigned int* outShmReadPos) const {
    if (displayIdx < 0 || displayIdx >= 16 || outShmReadPos == NULL) {
        return false;
    }

    for (int offset = _inFlightCount - 1; offset >= 0; offset--) {
        int queueIndex = (_inFlightHead + offset) % IN_FLIGHT_SLOT_COUNT;
        int slot = _inFlightSlotQueue[queueIndex];
        const InFlightFrame* frame = &_inFlightFrames[slot];
        if (frame->inUse && frame->displayIdx == displayIdx) {
            *outShmReadPos = frame->shmReadPos;
            return true;
        }
    }
    return false;
}

int InFlightTracker::PopAcked(int ackFrameId, unsigned int* outMaxReadPosByDisplay, bool* outHasReadPosByDisplay) {
    int popped = 0;
    bool seenDisplay[16] = {false,};

    while (_inFlightCount > 0) {
        int slot = _inFlightSlotQueue[_inFlightHead];
        InFlightFrame* frame = &_inFlightFrames[slot];

        if (ackFrameId >= 0 && (int)frame->frameId > ackFrameId) {
            break;
        }

        int displayIdx = frame->displayIdx;
        if (displayIdx >= 0 && displayIdx < 16) {
            if (outMaxReadPosByDisplay != NULL) {
                if (seenDisplay[displayIdx] == false ||
                    frame->shmReadPos > outMaxReadPosByDisplay[displayIdx]) {
                    outMaxReadPosByDisplay[displayIdx] = frame->shmReadPos;
                }
            }
            seenDisplay[displayIdx] = true;
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
