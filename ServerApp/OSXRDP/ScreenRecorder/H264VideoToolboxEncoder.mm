#include "H264VideoToolboxEncoder.h"

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#include <limits.h>

namespace {
struct EncodeResult {
    OSStatus status;
    bool completed;
    bool keyframe;
    std::vector<uint8_t> bytes;
};

bool AppendNAL(std::vector<uint8_t>* output, const uint8_t* bytes, size_t length) {
    static const uint8_t startCode[] = {0, 0, 0, 1};
    if (output == NULL || bytes == NULL || length == 0 ||
        output->size() > SIZE_MAX - sizeof(startCode) ||
        output->size() + sizeof(startCode) > SIZE_MAX - length) {
        return false;
    }
    output->insert(output->end(), startCode, startCode + sizeof(startCode));
    output->insert(output->end(), bytes, bytes + length);
    return true;
}

bool IsKeyframe(CMSampleBufferRef sampleBuffer) {
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (attachments == NULL || CFArrayGetCount(attachments) == 0) return false;
    CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    return attachment != NULL &&
        !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
}

bool AppendParameterSets(CMFormatDescriptionRef format, std::vector<uint8_t>* output,
                         size_t* nalLengthBytes) {
    if (format == NULL || output == NULL || nalLengthBytes == NULL) return false;
    size_t parameterSetCount = 0;
    const uint8_t* parameterSet = NULL;
    size_t parameterSetSize = 0;
    int headerLength = 0;
    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        format, 0, &parameterSet, &parameterSetSize,
        &parameterSetCount, &headerLength);
    if (status != noErr || parameterSetCount < 2 ||
        headerLength < 1 || headerLength > 4) {
        return false;
    }
    *nalLengthBytes = (size_t)headerLength;
    for (size_t index = 0; index < parameterSetCount; ++index) {
        status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, index, &parameterSet, &parameterSetSize, NULL, NULL);
        if (status != noErr || !AppendNAL(output, parameterSet, parameterSetSize)) {
            return false;
        }
    }
    return true;
}

bool SetSessionInt(VTCompressionSessionRef session, CFStringRef key, int value) {
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
    if (number == NULL) return false;
    OSStatus status = VTSessionSetProperty(session, key, number);
    CFRelease(number);
    return status == noErr;
}

CVPixelBufferRef CreateAlignedPixelBuffer(CVPixelBufferRef source,
                                          int actualWidth, int actualHeight,
                                          int alignedWidth, int alignedHeight) {
    if (source == NULL) return NULL;
    if (actualWidth == alignedWidth && actualHeight == alignedHeight) {
        CVPixelBufferRetain(source);
        return source;
    }

    CVPixelBufferRef padded = NULL;
    CVReturn createResult = CVPixelBufferCreate(kCFAllocatorDefault,
        alignedWidth, alignedHeight,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        NULL, &padded);
    if (createResult != kCVReturnSuccess || padded == NULL) return NULL;

    if (CVPixelBufferLockBaseAddress(padded, 0) != kCVReturnSuccess) {
        CVPixelBufferRelease(padded);
        return NULL;
    }
    bool valid = CVPixelBufferGetPlaneCount(source) >= 2 &&
        CVPixelBufferGetPlaneCount(padded) >= 2;
    for (size_t plane = 0; valid && plane < 2; ++plane) {
        uint8_t* src = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(source, plane);
        uint8_t* dst = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(padded, plane);
        size_t srcStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane);
        size_t dstStride = CVPixelBufferGetBytesPerRowOfPlane(padded, plane);
        size_t copyWidth = plane == 0 ? (size_t)actualWidth
                                      : ((size_t)(actualWidth + 1) & ~(size_t)1);
        size_t copyRows = plane == 0 ? (size_t)actualHeight
                                     : ((size_t)actualHeight + 1) / 2;
        size_t paddedRows = plane == 0 ? (size_t)alignedHeight : (size_t)alignedHeight / 2;
        valid = src != NULL && dst != NULL && srcStride >= copyWidth &&
            dstStride >= (size_t)alignedWidth && copyRows > 0;
        for (size_t row = 0; valid && row < copyRows; ++row) {
            memcpy(dst + row * dstStride, src + row * srcStride, copyWidth);
            uint8_t* dstRow = dst + row * dstStride;
            if (plane == 0) {
                memset(dstRow + copyWidth, dstRow[copyWidth - 1], alignedWidth - copyWidth);
            }
            else {
                for (size_t column = copyWidth; column < (size_t)alignedWidth; column += 2) {
                    dstRow[column] = dstRow[copyWidth - 2];
                    dstRow[column + 1] = dstRow[copyWidth - 1];
                }
            }
        }
        if (valid) {
            uint8_t* lastRow = dst + (copyRows - 1) * dstStride;
            for (size_t row = copyRows; row < paddedRows; ++row) {
                memcpy(dst + row * dstStride, lastRow, alignedWidth);
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(padded, 0);
    if (!valid) {
        CVPixelBufferRelease(padded);
        return NULL;
    }

    NSDictionary* cleanAperture = @{
        (NSString*)kCVImageBufferCleanApertureWidthKey: @(actualWidth),
        (NSString*)kCVImageBufferCleanApertureHeightKey: @(actualHeight),
        (NSString*)kCVImageBufferCleanApertureHorizontalOffsetKey: @0,
        (NSString*)kCVImageBufferCleanApertureVerticalOffsetKey: @0,
    };
    CVBufferSetAttachment(padded, kCVImageBufferCleanApertureKey,
                          (__bridge CFTypeRef)cleanAperture,
                          kCVAttachmentMode_ShouldPropagate);
    return padded;
}
} // namespace

bool OSXRDPConvertAVCCToAnnexB(const uint8_t* avcc, size_t avccSize,
                               size_t nalLengthBytes,
                               std::vector<uint8_t>* annexB) {
    if (avcc == NULL || annexB == NULL || nalLengthBytes < 1 || nalLengthBytes > 4) {
        return false;
    }
    size_t offset = 0;
    while (offset < avccSize) {
        if (avccSize - offset < nalLengthBytes) return false;
        uint32_t nalSize = 0;
        for (size_t i = 0; i < nalLengthBytes; ++i) {
            nalSize = (nalSize << 8) | avcc[offset + i];
        }
        offset += nalLengthBytes;
        if (nalSize == 0 || (size_t)nalSize > avccSize - offset ||
            !AppendNAL(annexB, avcc + offset, nalSize)) {
            return false;
        }
        offset += nalSize;
    }
    return offset == avccSize;
}

H264VideoToolboxEncoder::H264VideoToolboxEncoder() :
    _session(NULL), _activeResult(NULL), _width(0), _height(0), _alignedWidth(0),
    _alignedHeight(0), _framerate(0), _frameNumber(0) {}

H264VideoToolboxEncoder::~H264VideoToolboxEncoder() {
    Invalidate();
}

void H264VideoToolboxEncoder::CompressionOutputCallback(
        void* outputCallbackRefCon, void* sourceFrameRefCon,
        OSStatus status, VTEncodeInfoFlags infoFlags,
        CMSampleBufferRef sampleBuffer) {
    (void)sourceFrameRefCon;
    H264VideoToolboxEncoder* encoder =
        (H264VideoToolboxEncoder*)outputCallbackRefCon;
    EncodeResult* result = encoder == NULL
        ? NULL : (EncodeResult*)encoder->_activeResult;
    if (result == NULL) return;
    result->completed = true;
    result->status = status;
    if (status != noErr || (infoFlags & kVTEncodeInfo_FrameDropped) != 0 ||
        sampleBuffer == NULL || !CMSampleBufferDataIsReady(sampleBuffer)) {
        return;
    }

    result->keyframe = IsKeyframe(sampleBuffer);
    size_t nalLengthBytes = 4;
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (result->keyframe && !AppendParameterSets(format, &result->bytes, &nalLengthBytes)) {
        result->status = kVTVideoEncoderMalfunctionErr;
        return;
    }
    if (!result->keyframe) {
        const uint8_t* ignored = NULL;
        size_t ignoredSize = 0;
        size_t ignoredCount = 0;
        int headerLength = 0;
        if (format == NULL || CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, 0, &ignored, &ignoredSize, &ignoredCount, &headerLength) != noErr ||
            headerLength < 1 || headerLength > 4) {
            result->status = kVTVideoEncoderMalfunctionErr;
            return;
        }
        nalLengthBytes = (size_t)headerLength;
    }

    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t dataLength = block == NULL ? 0 : CMBlockBufferGetDataLength(block);
    if (dataLength == 0) {
        result->status = kVTVideoEncoderMalfunctionErr;
        return;
    }
    std::vector<uint8_t> avcc(dataLength);
    if (CMBlockBufferCopyDataBytes(block, 0, dataLength, avcc.data()) != kCMBlockBufferNoErr ||
        !OSXRDPConvertAVCCToAnnexB(avcc.data(), avcc.size(), nalLengthBytes, &result->bytes)) {
        result->status = kVTVideoEncoderMalfunctionErr;
    }
}

bool H264VideoToolboxEncoder::Initialize(int width, int height, int framerate,
                                         int targetBitrate, int maximumBitrate,
                                         int keyframeIntervalSeconds) {
    Invalidate();
    if (width <= 0 || height <= 0 || framerate <= 0 ||
        targetBitrate <= 0 || maximumBitrate < targetBitrate ||
        keyframeIntervalSeconds <= 0) return false;

    _width = width;
    _height = height;
    _alignedWidth = (_width + 15) & ~15;
    _alignedHeight = (_height + 15) & ~15;
    _framerate = framerate;
    NSDictionary* specification = @{
        (NSString*)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @YES,
    };
    VTCompressionSessionRef session = NULL;
    OSStatus status = VTCompressionSessionCreate(kCFAllocatorDefault,
        _alignedWidth, _alignedHeight, kCMVideoCodecType_H264,
        (__bridge CFDictionaryRef)specification, NULL, NULL,
        CompressionOutputCallback, this, &session);
    if (status != noErr || session == NULL) return false;

    bool configured =
        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue) == noErr &&
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse) == noErr &&
        VTSessionSetProperty(session, kVTCompressionPropertyKey_ProfileLevel,
                             kVTProfileLevel_H264_Baseline_AutoLevel) == noErr &&
        SetSessionInt(session, kVTCompressionPropertyKey_AverageBitRate, targetBitrate) &&
        SetSessionInt(session, kVTCompressionPropertyKey_ExpectedFrameRate, framerate) &&
        SetSessionInt(session, kVTCompressionPropertyKey_MaxKeyFrameInterval,
                      framerate * keyframeIntervalSeconds) &&
        SetSessionInt(session, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                      keyframeIntervalSeconds);
    NSArray* dataRateLimits = @[@(maximumBitrate / 8), @1];
    configured = configured && VTSessionSetProperty(session,
        kVTCompressionPropertyKey_DataRateLimits,
        (__bridge CFArrayRef)dataRateLimits) == noErr;
    if (!configured || VTCompressionSessionPrepareToEncodeFrames(session) != noErr) {
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
        return false;
    }
    _session = session;
    _frameNumber = 0;
    return true;
}

bool H264VideoToolboxEncoder::Encode(CVPixelBufferRef source, bool forceKeyframe,
                                     std::vector<uint8_t>* annexB, bool* isKeyframe) {
    VTCompressionSessionRef session = (VTCompressionSessionRef)_session;
    if (session == NULL || source == NULL || annexB == NULL || isKeyframe == NULL ||
        CVPixelBufferGetWidth(source) != (size_t)_width ||
        CVPixelBufferGetHeight(source) != (size_t)_height) return false;

    CVPixelBufferRef input = CreateAlignedPixelBuffer(source, _width, _height,
                                                       _alignedWidth, _alignedHeight);
    if (input == NULL) return false;
    EncodeResult result = { noErr, false, false, {} };
    if (_activeResult != NULL) {
        CVPixelBufferRelease(input);
        return false;
    }
    _activeResult = &result;
    CFDictionaryRef frameProperties = NULL;
    if (forceKeyframe) {
        frameProperties = (__bridge CFDictionaryRef)@{
            (NSString*)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES
        };
    }
    CMTime pts = CMTimeMake(_frameNumber++, _framerate);
    OSStatus status = VTCompressionSessionEncodeFrame(session, input, pts,
        kCMTimeInvalid, frameProperties, NULL, NULL);
    CVPixelBufferRelease(input);
    OSStatus completeStatus = status == noErr
        ? VTCompressionSessionCompleteFrames(session, pts) : status;
    if (status == noErr &&
        (completeStatus != noErr || !result.completed)) {
        // Keep the stack-backed result valid while invalidation drains any callback
        // accepted by VideoToolbox, including error paths.
        Invalidate();
    }
    _activeResult = NULL;
    if (status != noErr || completeStatus != noErr || !result.completed ||
        result.status != noErr || result.bytes.empty()) {
        return false;
    }
    annexB->swap(result.bytes);
    *isKeyframe = result.keyframe;
    return true;
}

void H264VideoToolboxEncoder::Invalidate() {
    VTCompressionSessionRef session = (VTCompressionSessionRef)_session;
    _session = NULL;
    if (session != NULL) {
        VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
    }
    _frameNumber = 0;
    _framerate = 0;
}
