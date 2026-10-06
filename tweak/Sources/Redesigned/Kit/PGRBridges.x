// The Kit's bridge into Spotify: the now playing artwork. The player's state, its open and close and
// links are Shared's (Shared/Player/PlayerState.h, Shared/Player/PlayerEvents.h,
// Shared/Navigation/Links.h). PGRBridges.h names the hook and why it is the one.
#import "Core/PGCore.h"
#import "Shared/Player/PlayerEvents.h"
#import "PGRBridges.h"
#import "PGRRestyle.h"

#pragma mark - now playing artwork

NSNotificationName const PGRNowPlayingArtworkDidChangeNotification = @"pureglass.redesign.nowPlayingArtworkDidChange";

// The picture published, the track it was published for, the picture it is (its key) and how it was had.
static UIImage *pg_artwork;
static NSString *pg_artworkURI, *pg_artworkKey;
static PGRArtworkQuality pg_artworkQuality;
static NSUInteger pg_artworkSerial;
// The playing track and the picture its metadata names.
static NSString *pg_wantedURI, *pg_wantedKey;
// Every picture published, held weakly, with the key it was published as. A view still showing one of
// these while another picture is wanted is showing the last track's.
static NSMapTable<UIImage *, NSString *> *pg_published;
static NSURLSessionDataTask *pg_fetch;

// Retries of a fetch that failed, and how long before each.
static const NSTimeInterval kFetchRetry = 2;
static const NSUInteger kFetchAttempts = 2;

static void artworkLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void artworkLog(NSString *format, ...) {
    static NSUInteger logged;
    if (logged++ >= 40) return;
    va_list args;
    va_start(args, format);
    PGLog(@"redesign kit: artwork %@", [[NSString alloc] initWithFormat:format arguments:args]);
    va_end(args);
}

// The image id in a metadata value: spotify:image:<id>, or an https URL ending in it.
static NSString *imageIDIn(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
    NSString *string = value;
    if ([string hasPrefix:@"spotify:image:"]) return [string substringFromIndex:@"spotify:image:".length];
    if ([string hasPrefix:@"https://"]) return string.lastPathComponent;
    return nil;
}

// The picture a track names, largest first, and where it can be fetched from.
static NSString *pictureOf(SPTPlayerTrack *track, NSURL **url) {
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (![metadata isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
        NSString *value = metadata[field], *identifier = imageIDIn(value);
        if (!identifier) continue;
        if (url) *url = [value hasPrefix:@"https://"] ? [NSURL URLWithString:value]
                                                     : [NSURL URLWithString:[@"https://i.scdn.co/image/" stringByAppendingString:identifier]];
        // Every size of one picture shares its last 24 digits; the first 16 are the size.
        return identifier.length == 40 ? [identifier substringFromIndex:16] : identifier;
    }
    return nil;
}

static void publish(UIImage *image, NSString *key, PGRArtworkQuality quality) {
    pg_artwork = image;
    pg_artworkURI = pg_wantedURI;
    pg_artworkKey = key;
    pg_artworkQuality = quality;
    pg_artworkSerial++;
    [pg_published setObject:key forKey:image];
    [NSNotificationCenter.defaultCenter postNotificationName:PGRNowPlayingArtworkDidChangeNotification object:nil userInfo:@{
        @"image": image,
        @"trackURI": pg_wantedURI ?: @"",
        @"quality": @(quality),
    }];
}

static NSURLSession *artworkSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
        // An image id is the picture's own digest, so a stored answer never goes stale.
        NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        configuration.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:0 diskCapacity:24 * 1024 * 1024
                                                               directoryURL:[caches URLByAppendingPathComponent:@"pureglass-artwork"]];
        configuration.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        configuration.timeoutIntervalForRequest = 20;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

static void fetchPicture(NSString *key, NSURL *url, NSUInteger attempt) {
    CFTimeInterval started = CACurrentMediaTime();
    pg_fetch = [artworkSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        UIImage *image = data.length && status == 200 ? [UIImage imageWithData:data] : nil;
        // Decoded here, off the main thread, rather than on the first frame that draws it.
        image = image.imageByPreparingForDisplay ?: image;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error.code == NSURLErrorCancelled) return;
            // A newer track asked for another picture meanwhile: this one would put the old one back.
            if (![key isEqualToString:pg_wantedKey]) {
                artworkLog(@"%@ came after the track moved on to %@, dropped", key, pg_wantedKey);
                return;
            }
            if (!image) {
                artworkLog(@"%@ not fetched (%ld, %@), attempt %lu", key, (long)status, error.localizedDescription, (unsigned long)attempt + 1);
                if (attempt + 1 >= kFetchAttempts) return;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFetchRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if ([key isEqualToString:pg_wantedKey] && !([pg_artworkKey isEqualToString:key] && pg_artworkQuality == PGRArtworkQualityExact)) {
                        fetchPicture(key, url, attempt + 1);
                    }
                });
                return;
            }
            artworkLog(@"%@ fetched %.0fx%.0f in %.0f ms", key, image.size.width, image.size.height, (CACurrentMediaTime() - started) * 1000);
            publish(image, key, PGRArtworkQualityExact);
        });
    }];
    [pg_fetch resume];
}

// Brings the playing track's picture up to date with the player's state, and fetches a picture newly
// wanted. Called on every state report and before any view read is believed, whichever comes first.
static void followPlayer(void) {
    SPTPlayerTrack *track = PGPlayerState().track;
    NSString *uri = PGURIString(track.URI);
    if (!uri) return;
    // The same track is looked at again only while its metadata has named no picture yet.
    if ([uri isEqualToString:pg_wantedURI] && ![pg_wantedKey hasPrefix:@"track:"]) return;
    pg_wantedURI = uri;
    NSURL *url = nil;
    // A track whose metadata names no picture is its own key: only the screens can show it then.
    NSString *key = pictureOf(track, &url) ?: [@"track:" stringByAppendingString:uri];
    if ([key isEqualToString:pg_wantedKey]) return;
    pg_wantedKey = key;
    [pg_fetch cancel];
    pg_fetch = nil;
    if ([key isEqualToString:pg_artworkKey] && pg_artworkQuality == PGRArtworkQualityExact) return;
    if (url) fetchPicture(key, url, 0);
}

void PGRSetNowPlayingArtwork(UIImage *image, NSString *trackURI, PGRArtworkQuality quality) {
    if (!image || !trackURI) return;
    followPlayer();
    // Read for a track that is no longer playing.
    if (![trackURI isEqualToString:pg_wantedURI]) return;
    NSString *key = pg_wantedKey;
    NSString *publishedAs = [pg_published objectForKey:image];
    // The screen still shows a picture published for another one.
    if (publishedAs && ![publishedAs isEqualToString:key]) {
        artworkLog(@"%@ still on screen while %@ is wanted, not believed", publishedAs, key);
        return;
    }
    if ([key isEqualToString:pg_artworkKey] && (image == pg_artwork || quality < pg_artworkQuality)) return;
    publish(image, key, MIN(quality, PGRArtworkQualityHigh));
}

UIImage *PGRNowPlayingArtwork(NSString **trackURI, NSString **identity) {
    if (trackURI) *trackURI = pg_artworkURI;
    // A fetched picture is known for what it is; one read off a screen is only what it looked like then,
    // so each of those is a picture of its own and a field redraws it.
    if (identity) {
        *identity = !pg_artwork ? nil : pg_artworkQuality == PGRArtworkQualityExact
            ? [pg_artworkKey stringByAppendingString:@"#exact"]
            : [NSString stringWithFormat:@"%@#%lu", pg_artworkKey, (unsigned long)pg_artworkSerial];
    }
    return pg_artwork;
}

// The player's reports, in the order they come.
@interface PGRArtworkFollower : NSObject <PGPlayerStateObserver>
@end

@implementation PGRArtworkFollower
- (void)playerStateDidChange:(SPTPlayerState *)state {
    followPlayer();
}
@end

static PGRArtworkFollower *pg_follower;

static char kBarCardKey, kBarImageKey;
static __weak UIView *pg_barView;

static void publishBarArtwork(void) {
    UIView *card = PGRFindByIdentifier(pg_barView, @"SPTNowPlayingBar", &kBarCardKey);
    UIView *holder = PGRFindByIdentifier(card, @"Encore.ImageView", &kBarImageKey);
    UIImageView *cover = nil;
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) cover = (UIImageView *)sub;
    }
    UIImage *image = cover.image;
    NSString *uri = PGURIString(PGPlayerState().track.URI);
    if (!image || !uri) return;
    PGRSetNowPlayingArtwork(image, uri, PGRArtworkQualityLow);
}

// The bar sets its picture when the image has loaded, which lays nothing out, so a track change looks
// again a few times while the picture comes in. One that loads later still is the fetch's to bring.
@interface PGRBarArtworkWatcher : NSObject <PGPlayerStateObserver>
@end

@implementation PGRBarArtworkWatcher {
    NSString *_track;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = PGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    for (NSNumber *delay in @[@0, @0.3, @1, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ publishBarArtwork(); });
    }
}

@end

static PGRBarArtworkWatcher *pg_barWatcher;

%group PGRBarArtworkHooks
%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    pg_barView = ((UIViewController *)self).viewIfLoaded;
    publishBarArtwork();
}
%end
%end

#pragma mark - the player's open and close

BOOL PGRPlayerIsTransitioning(void) {
    return PGPlayerTransitionEnds() > 0;
}

@interface PGRTransitionObservation : NSObject
@property (nonatomic, strong) NSArray *tokens;
@end

@implementation PGRTransitionObservation
- (void)dealloc {
    for (id token in self.tokens) [NSNotificationCenter.defaultCenter removeObserver:token];
}
@end

static char kTransitionKey;

void PGRObservePlayerTransition(id owner, void (^began)(id owner), void (^ended)(id owner)) {
    if (!owner) return;
    __weak id weakOwner = owner;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSMutableArray *tokens = [NSMutableArray array];
    if (began) {
        [tokens addObject:[center addObserverForName:PGPlayerTransitionNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            id strongOwner = weakOwner;
            if (strongOwner) began(strongOwner);
        }]];
    }
    if (ended) {
        [tokens addObject:[center addObserverForName:PGPlayerTransitionEndedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            id strongOwner = weakOwner;
            if (strongOwner) ended(strongOwner);
        }]];
    }
    PGRTransitionObservation *observation = [PGRTransitionObservation new];
    observation.tokens = tokens;
    NSMutableArray *kept = objc_getAssociatedObject(owner, &kTransitionKey);
    if (!kept) {
        kept = [NSMutableArray array];
        objc_setAssociatedObject(owner, &kTransitionKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [kept addObject:observation];
}

%ctor {
    if (!PGRedesignedUI()) return;
    // By pointer: two images of one picture are still two reads.
    pg_published = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                             valueOptions:NSPointerFunctionsStrongMemory capacity:16];
    // Ahead of the watchers, so the picture a track wants is known before any screen is read for it.
    pg_follower = [PGRArtworkFollower new];
    PGAddPlayerStateObserver(pg_follower);
    pg_barWatcher = [PGRBarArtworkWatcher new];
    PGAddPlayerStateObserver(pg_barWatcher);
    %init(PGRBarArtworkHooks);
    PGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
