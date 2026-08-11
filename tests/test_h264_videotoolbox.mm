#include "harness.h"
#include "../ServerApp/OSXRDP/ScreenRecorder/H264VideoToolboxEncoder.h"

#include <CoreVideo/CoreVideo.h>
#include <string.h>

static bool contains_nal_type(const std::vector<uint8_t>& bytes, uint8_t type) {
    for (size_t i = 0; i + 4 < bytes.size(); ++i) {
        if (bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 &&
            (bytes[i + 4] & 0x1f) == type) return true;
    }
    return false;
}

static int sps_profile_idc(const std::vector<uint8_t>& bytes) {
    for (size_t i = 0; i + 5 < bytes.size(); ++i) {
        if (bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 &&
            bytes[i + 3] == 1 && (bytes[i + 4] & 0x1f) == 7) {
            return bytes[i + 5];
        }
    }
    return -1;
}

TEST_CASE(avcc_conversion_rejects_malformed_nals) {
    std::vector<uint8_t> output;
    const uint8_t truncatedLength[] = {0, 0, 0};
    EXPECT_TRUE(!OSXRDPConvertAVCCToAnnexB(truncatedLength, sizeof(truncatedLength), 4, &output));
    const uint8_t oversized[] = {0, 0, 0, 5, 0x65, 0x01};
    EXPECT_TRUE(!OSXRDPConvertAVCCToAnnexB(oversized, sizeof(oversized), 4, &output));
    const uint8_t zeroNal[] = {0, 0, 0, 0};
    EXPECT_TRUE(!OSXRDPConvertAVCCToAnnexB(zeroNal, sizeof(zeroNal), 4, &output));
    EXPECT_TRUE(!OSXRDPConvertAVCCToAnnexB(oversized, sizeof(oversized), 0, &output));
}

TEST_CASE(avcc_conversion_preserves_nal_order) {
    const uint8_t avcc[] = {0, 0, 0, 2, 0x65, 0xaa, 0, 0, 0, 2, 0x41, 0xbb};
    std::vector<uint8_t> output;
    EXPECT_TRUE(OSXRDPConvertAVCCToAnnexB(avcc, sizeof(avcc), 4, &output));
    const uint8_t expected[] = {0, 0, 0, 1, 0x65, 0xaa, 0, 0, 0, 1, 0x41, 0xbb};
    EXPECT_EQ_INT(output.size(), sizeof(expected));
    EXPECT_TRUE(memcmp(output.data(), expected, sizeof(expected)) == 0);
}

TEST_CASE(videotoolbox_encodes_ordered_annexb_baseline_stream) {
    CVPixelBufferRef pixel = NULL;
    CVReturn createResult = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        NULL, &pixel);
    if (createResult != kCVReturnSuccess || pixel == NULL) {
        SKIP_TEST("CVPixelBuffer allocation unavailable in sandbox");
    }

    H264VideoToolboxEncoder encoder;
    if (!encoder.Initialize(64, 64, 15, 300000, 500000, 5)) {
        CVPixelBufferRelease(pixel);
        SKIP_TEST("VideoToolbox H.264 encoder unavailable");
    }
    for (int frame = 0; frame < 6; ++frame) {
        CVPixelBufferLockBaseAddress(pixel, 0);
        memset(CVPixelBufferGetBaseAddressOfPlane(pixel, 0), 16 + frame * 8,
               CVPixelBufferGetBytesPerRowOfPlane(pixel, 0) * 64);
        memset(CVPixelBufferGetBaseAddressOfPlane(pixel, 1), 128,
               CVPixelBufferGetBytesPerRowOfPlane(pixel, 1) * 32);
        std::vector<uint8_t> output;
        bool keyframe = false;
        bool encoded = encoder.Encode(pixel, frame == 0, &output, &keyframe);
        CVPixelBufferUnlockBaseAddress(pixel, 0);
        EXPECT_TRUE(encoded);
        if (!encoded) break;
        EXPECT_TRUE(output.size() > 4);
        EXPECT_TRUE(output[0] == 0 && output[1] == 0 && output[2] == 0 && output[3] == 1);
        if (frame == 0) {
            EXPECT_TRUE(keyframe);
            EXPECT_TRUE(contains_nal_type(output, 7));
            EXPECT_TRUE(contains_nal_type(output, 8));
            EXPECT_TRUE(contains_nal_type(output, 5));
            EXPECT_EQ_INT(sps_profile_idc(output), 66);
        }
    }
    encoder.Invalidate();
    CVPixelBufferRelease(pixel);
}

int main(void) {
    RUN_TEST(avcc_conversion_rejects_malformed_nals);
    RUN_TEST(avcc_conversion_preserves_nal_order);
    RUN_TEST(videotoolbox_encodes_ordered_annexb_baseline_stream);
    return test_main_finish("test_h264_videotoolbox");
}
