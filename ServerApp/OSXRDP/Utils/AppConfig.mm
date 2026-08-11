#import "AppConfig.h"

static NSString *const kKeyMacNativeInputMappingEnabled = @"osxrdp.macNativeInputMappingEnabled";
static NSString *const kKeyAutoLandFiles = @"osxrdp.autoLandFiles";
static NSString *const kKeyAutoLandBookmark = @"osxrdp.autoLandFolderBookmark";
static NSString *const kKeyMaxFramerate = @"osxrdp.maxFramerate";
static NSString *const kKeyPreferredCodec = @"osxrdp.preferredCodec";

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
        kKeyMaxFramerate: @0,
        kKeyPreferredCodec: @"",
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

- (int)maxFramerate {
    return (int)[[NSUserDefaults standardUserDefaults] integerForKey:kKeyMaxFramerate];
}

- (void)setMaxFramerate:(int)maxFramerate {
    [[NSUserDefaults standardUserDefaults] setInteger:maxFramerate forKey:kKeyMaxFramerate];
}

- (NSString *)preferredCodec {
    NSString *codec = [[NSUserDefaults standardUserDefaults] stringForKey:kKeyPreferredCodec];
    return codec ?: @"";
}

- (void)setPreferredCodec:(NSString *)preferredCodec {
    [[NSUserDefaults standardUserDefaults] setObject:preferredCodec ?: @"" forKey:kKeyPreferredCodec];
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
