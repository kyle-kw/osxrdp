#import "AppConfig.h"

static NSString *const kKeyMacNativeInputMappingEnabled = @"osxrdp.macNativeInputMappingEnabled";
static NSString *const kKeyAutoLandFiles = @"osxrdp.autoLandFiles";
static NSString *const kKeyAutoLandBookmark = @"osxrdp.autoLandFolderBookmark";
static NSString *const kKeyStreamQualityPreset = @"osxrdp.streamQualityPreset";

@implementation AppConfig {
    // Last security-scoped URL we started accessing (balanced on replace/dealloc).
    NSURL *_accessedAutoLandURL;
}

+ (instancetype)shared {
    static AppConfig *sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[AppConfig alloc] init];
    });
    return sInstance;
}

+ (void)registerDefaults {
    NSDictionary *defaults = @{
        kKeyMacNativeInputMappingEnabled: @YES,
        kKeyAutoLandFiles: @NO,
        kKeyStreamQualityPreset: @(OSXRDP_STREAM_QUALITY_DEFAULT),
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [AppConfig registerDefaults];
        _accessedAutoLandURL = nil;
    }
    return self;
}

- (void)dealloc {
    if (_accessedAutoLandURL != nil) {
        [_accessedAutoLandURL stopAccessingSecurityScopedResource];
        _accessedAutoLandURL = nil;
    }
}

- (void)beginAccessingAutoLandURL:(NSURL *)url {
    if (url == nil) {
        return;
    }
    if (_accessedAutoLandURL != nil) {
        if ([_accessedAutoLandURL isEqual:url]) {
            return;
        }
        [_accessedAutoLandURL stopAccessingSecurityScopedResource];
        _accessedAutoLandURL = nil;
    }
    // Returns NO when not security-scoped; still safe to call.
    [url startAccessingSecurityScopedResource];
    _accessedAutoLandURL = url;
}

#pragma mark - Properties

- (BOOL)macNativeInputMappingEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kKeyMacNativeInputMappingEnabled];
}

- (void)setMacNativeInputMappingEnabled:(BOOL)macNativeInputMappingEnabled {
    [[NSUserDefaults standardUserDefaults] setBool:macNativeInputMappingEnabled
                                           forKey:kKeyMacNativeInputMappingEnabled];
}

- (BOOL)autoLandFiles {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kKeyAutoLandFiles];
}

- (void)setAutoLandFiles:(BOOL)autoLandFiles {
    [[NSUserDefaults standardUserDefaults] setBool:autoLandFiles forKey:kKeyAutoLandFiles];
}

- (nullable NSData *)autoLandFolderBookmark {
    return [[NSUserDefaults standardUserDefaults] dataForKey:kKeyAutoLandBookmark];
}

- (void)setAutoLandFolderBookmark:(nullable NSData *)autoLandFolderBookmark {
    [[NSUserDefaults standardUserDefaults] setObject:autoLandFolderBookmark forKey:kKeyAutoLandBookmark];
}

- (osxrdp_stream_quality_preset_t)streamQualityPreset {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kKeyStreamQualityPreset];
    if (![value isKindOfClass:NSNumber.class]) {
        return OSXRDP_STREAM_QUALITY_DEFAULT;
    }
    int preset = [(NSNumber *)value intValue];
    return osxrdp_stream_quality_is_valid(preset)
        ? (osxrdp_stream_quality_preset_t)preset
        : OSXRDP_STREAM_QUALITY_DEFAULT;
}

- (void)setStreamQualityPreset:(osxrdp_stream_quality_preset_t)preset {
    int value = osxrdp_stream_quality_is_valid((int)preset)
        ? (int)preset : OSXRDP_STREAM_QUALITY_DEFAULT;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:kKeyStreamQualityPreset];
}

- (NSURL *)resolvedAutoLandFolderURL {
    NSData *bookmark = self.autoLandFolderBookmark;
    if (bookmark != nil) {
        BOOL stale = NO;
        NSError *error = nil;
        // Prefer security-scoped resolution so sandboxed builds can write auto-land files.
        NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
                                               options:NSURLBookmarkResolutionWithSecurityScope
                                         relativeToURL:nil
                                   bookmarkDataIsStale:&stale
                                                 error:&error];
        if (url == nil) {
            // Legacy bookmarks created without security scope
            error = nil;
            url = [NSURL URLByResolvingBookmarkData:bookmark
                                            options:0
                                      relativeToURL:nil
                                bookmarkDataIsStale:&stale
                                              error:&error];
        }
        if (url != nil && error == nil) {
            if (stale) {
                NSLog(@"[AppConfig] auto-land bookmark is stale; using resolved URL until user re-picks folder");
            }
            [self beginAccessingAutoLandURL:url];
            return url;
        }
        NSLog(@"[AppConfig] bookmark resolution failed: %@", error);
    }
    // Fallback: Downloads directory (system path; no security scope needed)
    NSURL *downloadsURL = [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory
                                                                inDomains:NSUserDomainMask].firstObject;
    return downloadsURL ?: [NSURL fileURLWithPath:NSTemporaryDirectory()];
}

@end
