#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppConfig : NSObject

@property (class, readonly, strong) AppConfig *shared;

// Map Windows input conventions to their native Mac equivalents.
@property (assign) BOOL macNativeInputMappingEnabled;

// Feature #12: auto-land clipboard files
@property (assign) BOOL autoLandFiles;
// Security-scoped bookmark data (NSURLBookmarkCreationWithSecurityScope) when available.
@property (strong, nullable) NSData *autoLandFolderBookmark;

// Future codec tuning hooks (Phase 1: stored but not yet wired to module)
@property (assign) int maxFramerate;            // 0 = client/codec-driven
@property (copy) NSString *preferredCodec;       // "" = client-driven; "h264"/"rfx"/"bitmap"

// Resolve auto-land bookmark (security-scoped when possible), falling back to Downloads.
// Starts security-scoped access on the returned URL when applicable.
- (NSURL *)resolvedAutoLandFolderURL;

+ (void)registerDefaults;

@end

NS_ASSUME_NONNULL_END
