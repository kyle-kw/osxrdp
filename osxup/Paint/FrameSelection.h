#ifndef FrameSelection_h
#define FrameSelection_h

#include "osxrdp/screenrecordshm.h"

struct FrameSelectionDecision {
    bool hasFrame;
    bool requestRFXFullRedraw;
    bool forceFullDirty;
    unsigned int targetPos;
    unsigned int skippedFrames;
};

inline FrameSelectionDecision SelectFramePosition(unsigned int readPos,
                                                  unsigned int writePos,
                                                  int inFlightCount,
                                                  bool hasLastSubmitted,
                                                  unsigned int lastSubmitted,
                                                  bool selfContained) {
    FrameSelectionDecision result = {false, false, false, readPos, 0};
    if (readPos == writePos) return result;

    if (inFlightCount > 0) {
        if (!hasLastSubmitted) return result;
        result.targetPos = lastSubmitted + 1;
        result.hasFrame = result.targetPos < writePos;
        return result;
    }

    unsigned int backlog = writePos - readPos;
    if (!selfContained && backlog >= FRAME_SLOTS) {
        result.requestRFXFullRedraw = true;
        return result;
    }

    result.hasFrame = true;
    if (selfContained && backlog > 1) {
        result.targetPos = writePos - 1;
        result.skippedFrames = backlog - 1;
        result.forceFullDirty = true;
    }
    return result;
}

#endif
