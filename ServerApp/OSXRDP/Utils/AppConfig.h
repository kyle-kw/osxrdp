#import <Foundation/Foundation.h>
#include "osxrdp/stream_policy.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppConfig : NSObject

@property (class, readonly, strong) AppConfig *shared;

// Map Windows input conventions to their native Mac equivalents.
@property (assign) BOOL macNativeInputMappingEnabled;

// Feature #12: auto-land clipboard files
@property (assign) BOOL autoLandFiles;
// Security-scoped bookmark data (NSURLBookmarkCreationWithSecurityScope) when available.
@property (strong, nullable) NSData *autoLandFolderBookmark;

// Applied to the next RDP connection. Invalid stored values read as High Quality.
@property (assign) osxrdp_stream_quality_preset_t streamQualityPreset;

// Resolve auto-land bookmark (security-scoped when possible), falling back to Downloads.
// Starts security-scoped access on the returned URL when applicable.
- (NSURL *)resolvedAutoLandFolderURL;

+ (void)registerDefaults;

@end

NS_ASSUME_NONNULL_END
