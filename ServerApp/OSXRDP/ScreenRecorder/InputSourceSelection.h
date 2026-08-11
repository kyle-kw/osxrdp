#ifndef InputSourceSelection_h
#define InputSourceSelection_h

#include <stdbool.h>
#include <stddef.h>

static inline int InputSourceSelectionTargetIndex(const bool *isCJKV,
                                                  size_t count,
                                                  int currentIndex,
                                                  int preferredCJKVIndex) {
    if (isCJKV == NULL || count == 0) {
        return -1;
    }

    bool currentIsCJKV = currentIndex >= 0 &&
                         (size_t)currentIndex < count &&
                         isCJKV[currentIndex];
    bool selectCJKV = !currentIsCJKV;

    if (selectCJKV && preferredCJKVIndex >= 0 &&
        (size_t)preferredCJKVIndex < count &&
        isCJKV[preferredCJKVIndex]) {
        return preferredCJKVIndex;
    }

    for (size_t i = 0; i < count; i++) {
        if (isCJKV[i] == selectCJKV) {
            return (int)i;
        }
    }

    return -1;
}

#endif /* InputSourceSelection_h */
