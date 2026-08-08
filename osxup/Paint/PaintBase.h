#ifndef PaintBase_h
#define PaintBase_h

#include "osxrdp/packet.h"
#include "osxrdp/screenrecordshm.h"

struct mod;

class PaintBase {
public:
    PaintBase() {};
    virtual ~PaintBase() {}

    virtual void Initialize(const struct mod* mod) = 0;
    virtual void Release() = 0;
    virtual bool DoPaint(const struct mod* mod, screenrecord_frame_t* frameInfo, char* imgData, size_t imgDataSize, int frame_id, int displayId, int width, int height) = 0;

    // Whether the slot frame is a full frame or contains only partial changes
    //   - BGRA32 / NV12 : slot = full frame image         -> true  (default)
    //   - RFX           : slot = only "changed tiles"      -> false
    virtual bool FrameIsSelfContained() const { return true; }
};

#endif
