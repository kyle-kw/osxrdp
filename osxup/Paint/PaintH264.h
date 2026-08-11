
#ifndef PaintH264_h
#define PaintH264_h

#include "PaintBase.h"
#include "xstream.h"

class PaintH264 : public PaintBase {
public:
    explicit PaintH264(bool alreadyCompressed) : _alreadyCompressed(alreadyCompressed) {}
    void Initialize(const struct mod* mod) override;
    void Release() override;
    bool DoPaint(const struct mod* mod, screenrecord_frame_t* frameInfo, char* imgData, size_t imgDataSize, int frame_id, int displayId, int width, int height) override;
    bool FrameIsSelfContained() const override { return !_alreadyCompressed; }
    
private:
    xstream_t* _drawCmd = NULL;
    bool _alreadyCompressed;
};


#endif /* PaintH264_h */
