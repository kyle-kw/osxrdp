#ifndef H264VideoToolboxEncoder_h
#define H264VideoToolboxEncoder_h

#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <stddef.h>
#include <stdint.h>
#include <vector>

// Strict length-prefixed AVCC to start-code-delimited Annex-B conversion.
// Returns false for truncated lengths, zero-sized NALs, or size overflows.
bool OSXRDPConvertAVCCToAnnexB(const uint8_t* avcc, size_t avccSize,
                               size_t nalLengthBytes,
                               std::vector<uint8_t>* annexB);

enum class H264EncodeStatus {
    Error,
    Encoded,
    Dropped,
};

// Classifies the callback result. A VideoToolbox frame drop is an informational
// outcome, not an encoder failure, and must not trigger session recreation.
H264EncodeStatus OSXRDPClassifyH264EncodeResult(OSStatus status, bool completed,
                                                bool dropped, size_t outputSize);

class H264VideoToolboxEncoder {
public:
    H264VideoToolboxEncoder();
    ~H264VideoToolboxEncoder();

    bool Initialize(int width, int height, int framerate,
                    int targetBitrate, int maximumBitrate,
                    int keyframeIntervalSeconds);
    H264EncodeStatus Encode(CVPixelBufferRef source, bool forceKeyframe,
                            std::vector<uint8_t>* annexB, bool* isKeyframe);
    void Invalidate();

private:
    static void CompressionOutputCallback(void* outputCallbackRefCon,
                                          void* sourceFrameRefCon,
                                          OSStatus status,
                                          VTEncodeInfoFlags infoFlags,
                                          CMSampleBufferRef sampleBuffer);
    void* _session;
    void* _activeResult;
    int _width;
    int _height;
    int _alignedWidth;
    int _alignedHeight;
    int _framerate;
    int64_t _frameNumber;

    H264VideoToolboxEncoder(const H264VideoToolboxEncoder&) = delete;
    H264VideoToolboxEncoder& operator=(const H264VideoToolboxEncoder&) = delete;
};

#endif /* H264VideoToolboxEncoder_h */
