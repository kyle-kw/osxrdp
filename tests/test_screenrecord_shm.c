#include "harness.h"
#include "osxrdp/screenrecordshm.h"

#include <stdlib.h>

static screenrecord_shm_t* create_compatible_mapping(size_t slotSize,
                                                      size_t* mappedSize) {
    size_t headerSize = offsetof(screenrecord_shm_t, screenrecord_datas);
    *mappedSize = headerSize + slotSize * FRAME_SLOTS;
    screenrecord_shm_t* shm = (screenrecord_shm_t*)calloc(1, *mappedSize);
    if (shm == NULL) return NULL;
    shm->layoutMagic = OSXRDP_SCREENRECORD_SHM_MAGIC;
    shm->layoutVersion = OSXRDP_SCREENRECORD_SHM_LAYOUT_VERSION;
    shm->headerSize = (uint32_t)headerSize;
    shm->frameSize = (uint32_t)sizeof(screenrecord_frame_t);
    shm->screenrecord_data_size = slotSize;
    return shm;
}

TEST_CASE(compatible_layout_and_mapping_size_are_accepted) {
    size_t mappedSize = 0;
    screenrecord_shm_t* shm = create_compatible_mapping(256, &mappedSize);
    EXPECT_NOT_NULL(shm);
    if (shm == NULL) return;
    EXPECT_TRUE(osxrdp_screenrecord_shm_is_compatible(shm, mappedSize));
    free(shm);
}

TEST_CASE(stale_layout_version_is_rejected) {
    size_t mappedSize = 0;
    screenrecord_shm_t* shm = create_compatible_mapping(256, &mappedSize);
    EXPECT_NOT_NULL(shm);
    if (shm == NULL) return;
    shm->layoutVersion--;
    EXPECT_TRUE(!osxrdp_screenrecord_shm_is_compatible(shm, mappedSize));
    free(shm);
}

TEST_CASE(truncated_slot_storage_is_rejected) {
    size_t mappedSize = 0;
    screenrecord_shm_t* shm = create_compatible_mapping(256, &mappedSize);
    EXPECT_NOT_NULL(shm);
    if (shm == NULL) return;
    EXPECT_TRUE(!osxrdp_screenrecord_shm_is_compatible(shm, mappedSize - 1));
    free(shm);
}

int main(void) {
    RUN_TEST(compatible_layout_and_mapping_size_are_accepted);
    RUN_TEST(stale_layout_version_is_rejected);
    RUN_TEST(truncated_slot_storage_is_rejected);
    return test_main_finish("test_screenrecord_shm");
}
