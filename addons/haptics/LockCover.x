// Vitrine Addon, the lock screen's Canvas below iOS 26: while Spotify's switch for it is on (SGKeyLockCoverAddon, told
// as kSGRelayLockArtOn / kSGRelayLockArtOff), the song's moving artwork takes the place of the lock screen's own large
// cover. iOS 26 does it itself, so nothing is done there.
//
// Nothing is drawn of the add-on's own unless the system has drawn its own first: a tap on the cover of the lock
// screen's player opens it large over the lock screen (and the player's small copy goes), and only then, and only while
// Spotify has a clip for the song (kSGRelayLockClip), is that large cover hidden and the clip shown full screen in its
// place, the widgets under the clock hidden with it. A clip that comes later takes the cover's place as it comes; with
// none, the system's cover stays as it is. Closed again, everything of the system's comes back.
//
// The system's large cover is not a class this file can name for every iOS (the lock screen is CoverSheet's, its player
// MediaRemoteUI's), so it is looked for on each layout of the cover sheet: a view of an "Artwork" class, shown, at least
// kLargeArtwork across. The widgets are the views of a "Complication" class. What it found is logged once per change
// ("[vitrine-addon]"), to be checked on a phone.
//
// The clip is fitted whole to the screen's width, and the bands above and below it take its first frame's edge colours,
// its own top and bottom fading into them, as a redesigned album's page runs on in its cover's colour with the cover
// dissolving into it: no edge of the clip shows. It plays with no AVPlayer, which in SpringBoard took an audio session
// the system counted as playback and paused Spotify for: its frames are read from the file (AVAssetReader, the video
// track alone) and handed to an AVSampleBufferDisplayLayer on a timebase of its own, looped, held still while the song
// is paused.
//
// Threading: the notifications and MediaRemote's answers come on the main queue; the clip's frames are read on a queue
// of their own.
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <notify.h>
#import "../../tweak/Sources/Shared/Haptics/SGHapticRelay.h"

@interface CSCoverSheetViewController : UIViewController
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

typedef void (*SGMRGetApp)(dispatch_queue_t queue, void (^handler)(CFStringRef bundle));
typedef void (*SGMRIsPlaying)(dispatch_queue_t queue, void (^handler)(Boolean playing));
typedef void (*SGMRRegister)(dispatch_queue_t queue);

static const NSTimeInterval kFade = 0.35;
// The system's large cover is at least this wide; the player's small one is far smaller.
static const CGFloat kLargeArtwork = 180;
// How much of the clip's height, at its top and its bottom, fades into the bands.
static const CGFloat kEdgeFade = 0.12;

static SGMRGetApp sg_getApp;
static SGMRIsPlaying sg_isPlaying;
static BOOL sg_on, sg_playing = YES;
static NSURL *sg_clip;   // a copy of Spotify's clip for the song, nil for none
static __weak UIView *sg_sheet;   // the cover sheet's view
static __weak UIView *sg_large;   // the system's large cover, while it is open
static NSHashTable<UIView *> *sg_hidden;   // what is hidden for the clip, to give back

// The average colour of `image`'s top and bottom rows.
static void edgeColors(CGImageRef image, UIColor **top, UIColor **bottom) {
    *top = *bottom = UIColor.blackColor;
    if (!image) return;
    enum { width = 16, height = 20 };
    uint8_t pixels[width * height * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    for (int edge = 0; edge < 2; edge++) {
        int row = edge == 0 ? 0 : height - 1;
        double r = 0, g = 0, b = 0;
        for (int x = 0; x < width; x++) {
            const uint8_t *p = pixels + (row * width + x) * 4;
            r += p[0]; g += p[1]; b += p[2];
        }
        UIColor *color = [UIColor colorWithRed:r / width / 255 green:g / width / 255 blue:b / width / 255 alpha:1];
        if (edge == 0) *top = color; else *bottom = color;
    }
}

#pragma mark - the clip

@interface SGVLockClip : UIView
- (void)playClip:(NSURL *)clip;
- (void)setPlaying:(BOOL)playing;
@end

@implementation SGVLockClip {
    CAGradientLayer *_bands;
    AVSampleBufferDisplayLayer *_video;
    CAGradientLayer *_mask;
    dispatch_queue_t _feed;
    AVURLAsset *_asset;
    AVAssetTrack *_track;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_output;
    CMTime _offset;
    CGSize _natural;
    NSURL *_playing;
    NSUInteger _run;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    _bands = [CAGradientLayer layer];
    _bands.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor];
    [self.layer addSublayer:_bands];
    _feed = dispatch_queue_create("com.vitrine.addon.lockclip", DISPATCH_QUEUE_SERIAL);
    return self;
}

// Where the clip is drawn: its whole width the screen's, in the middle of the height.
- (CGRect)fitted {
    CGRect bounds = self.bounds;
    if (_natural.width < 1 || _natural.height < 1) return bounds;
    CGFloat height = bounds.size.width * _natural.height / _natural.width;
    return CGRectMake(0, CGRectGetMidY(bounds) - height / 2, bounds.size.width, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bands.frame = self.bounds;
    _video.frame = [self fitted];
    _mask.frame = _video.bounds;
    [CATransaction commit];
}

- (void)paintBands:(CGImageRef)image {
    if (!image) return;
    UIColor *top, *bottom;
    edgeColors(image, &top, &bottom);
    CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:@"colors"];
    ease.fromValue = (_bands.presentationLayer ?: _bands).colors;
    ease.duration = kFade;
    [_bands addAnimation:ease forKey:@"colors"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bands.colors = @[(id)top.CGColor, (id)bottom.CGColor];
    [CATransaction commit];
}

- (void)playClip:(NSURL *)clip {
    if ((clip == nil && _playing == nil) || [clip isEqual:_playing]) return;
    _playing = clip;
    _run++;
    [_video stopRequestingMediaData];
    [_video flush];
    [_video removeFromSuperlayer];
    [_reader cancelReading];
    _video = nil;
    _reader = nil;
    _output = nil;
    if (!clip) return;
    _asset = [AVURLAsset URLAssetWithURL:clip options:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    _track = [_asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
#pragma clang diagnostic pop
    if (!_track) return;
    CGSize size = CGSizeApplyAffineTransform(_track.naturalSize, _track.preferredTransform);
    _natural = CGSizeMake(fabs(size.width), fabs(size.height));
    _video = [AVSampleBufferDisplayLayer layer];
    _video.videoGravity = AVLayerVideoGravityResizeAspect;
    // Its own top and bottom fade into the bands, so no edge of it shows.
    _mask = [CAGradientLayer layer];
    _mask.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    _mask.locations = @[@0, @(kEdgeFade), @(1 - kEdgeFade), @1];
    _video.mask = _mask;
    CMTimebaseRef timebase = NULL;
    CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &timebase);
    CMTimebaseSetTime(timebase, kCMTimeZero);
    CMTimebaseSetRate(timebase, sg_playing ? 1 : 0);
    _video.controlTimebase = timebase;
    if (timebase) CFRelease(timebase);
    [self.layer addSublayer:_video];
    [self setNeedsLayout];
    _offset = kCMTimeZero;

    AVAssetImageGenerator *frames = [AVAssetImageGenerator assetImageGeneratorWithAsset:_asset];
    frames.appliesPreferredTrackTransform = YES;
    frames.maximumSize = CGSizeMake(64, 64);
    __weak SGVLockClip *weakSelf = self;
    NSUInteger asked = _run;
    [frames generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:kCMTimeZero]]
                                 completionHandler:^(CMTime requested, CGImageRef image, CMTime actual, AVAssetImageGeneratorResult result, NSError *error) {
        if (result != AVAssetImageGeneratorSucceeded || !image) return;
        CGImageRetain(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            SGVLockClip *view = weakSelf;
            if (view && view->_run == asked) [view paintBands:image];
            CGImageRelease(image);
        });
    }];

    NSUInteger run = _run;
    AVSampleBufferDisplayLayer *video = _video;
    dispatch_async(_feed, ^{
        if (run != self->_run || ![self startReader]) return;
        [video requestMediaDataWhenReadyOnQueue:self->_feed usingBlock:^{ [self feed:video run:run]; }];
    });
}

- (void)setPlaying:(BOOL)playing {
    if (_video.controlTimebase) CMTimebaseSetRate(_video.controlTimebase, playing ? 1 : 0);
}

- (BOOL)startReader {
    NSError *error = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:_asset error:&error];
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:_track outputSettings:nil];
    if (!reader || ![reader canAddOutput:output]) return NO;
    [reader addOutput:output];
    if (![reader startReading]) return NO;
    _reader = reader;
    _output = output;
    return YES;
}

- (void)feed:(AVSampleBufferDisplayLayer *)video run:(NSUInteger)run {
    while (video.isReadyForMoreMediaData && run == _run) {
        CMSampleBufferRef sample = [_output copyNextSampleBuffer];
        if (!sample) {
            if (_reader.status != AVAssetReaderStatusCompleted) {
                [video stopRequestingMediaData];
                return;
            }
            _offset = CMTimeAdd(_offset, _asset.duration);
            if (![self startReader]) {
                [video stopRequestingMediaData];
                return;
            }
            continue;
        }
        CMItemCount count = 0;
        CMSampleBufferGetSampleTimingInfoArray(sample, 0, NULL, &count);
        CMSampleTimingInfo stack[8];
        CMSampleTimingInfo *timing = count <= 8 ? stack : malloc(sizeof(CMSampleTimingInfo) * count);
        CMSampleBufferGetSampleTimingInfoArray(sample, count, timing, &count);
        for (CMItemCount i = 0; i < count; i++) {
            if (CMTIME_IS_VALID(timing[i].presentationTimeStamp)) timing[i].presentationTimeStamp = CMTimeAdd(timing[i].presentationTimeStamp, _offset);
            if (CMTIME_IS_VALID(timing[i].decodeTimeStamp)) timing[i].decodeTimeStamp = CMTimeAdd(timing[i].decodeTimeStamp, _offset);
        }
        CMSampleBufferRef moved = NULL;
        CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sample, count, timing, &moved);
        if (timing != stack) free(timing);
        CFRelease(sample);
        if (!moved) continue;
        [video enqueueSampleBuffer:moved];
        CFRelease(moved);
    }
}

@end

#pragma mark - the lock screen

static char kClipKey;

static BOOL shown(UIView *view) {
    return view.window && !view.hidden && view.alpha > 0.01;
}

// The system's large cover, if it is open: a view of an "Artwork" class, shown (or hidden by the add-on), wide; and
// the widgets under the clock.
static void findParts(UIView *root, UIView **large, NSMutableArray<UIView *> *widgets, NSMutableString *seen, int depth) {
    if (depth > 30) return;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:SGVLockClip.class]) continue;
        NSString *name = NSStringFromClass(sub.class);
        if ([name containsString:@"Artwork"]) {
            [seen appendFormat:@"%@ %.0fx%.0f%@; ", name, sub.bounds.size.width, sub.bounds.size.height, shown(sub) ? @"" : @" (hidden)"];
            if (!*large && (shown(sub) || [sg_hidden containsObject:sub]) && sub.bounds.size.width >= kLargeArtwork) *large = sub;
        }
        if ([name containsString:@"Complication"] && ![name containsString:@"Complications"]) {
            [widgets addObject:sub];
            continue;
        }
        findParts(sub, large, widgets, seen, depth + 1);
    }
}

static void hide(UIView *view, BOOL away) {
    if (!view) return;
    if (!sg_hidden) sg_hidden = [NSHashTable weakObjectsHashTable];
    if (away) [sg_hidden addObject:view];
    else [sg_hidden removeObject:view];
    [UIView animateWithDuration:kFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ view.alpha = away ? 0 : 1; } completion:nil];
}

// The clip in the large cover's place while both are there, and everything of the system's given back otherwise.
static void update(void) {
    UIView *sheet = sg_sheet;
    if (!sheet) return;
    UIView *large = nil;
    NSMutableArray<UIView *> *widgets = [NSMutableArray array];
    NSMutableString *seen = [NSMutableString string];
    findParts(sheet, &large, widgets, seen, 0);
    static NSString *logged;
    NSString *said = [NSString stringWithFormat:@"artwork views: %@| large %@, %lu widgets, clip %@", seen.length ? seen : @"none ",
                      large ? NSStringFromClass(large.class) : @"none", (unsigned long)widgets.count, sg_clip ? @"ready" : @"none"];
    if (![said isEqualToString:logged]) {
        logged = said;
        NSLog(@"[vitrine-addon] %@", said);
    }
    sg_large = large;
    BOOL on = sg_on && large && sg_clip;

    SGVLockClip *clip = objc_getAssociatedObject(sheet, &kClipKey);
    if (!clip && on) {
        clip = [[SGVLockClip alloc] initWithFrame:sheet.bounds];
        clip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        clip.alpha = 0;
        objc_setAssociatedObject(sheet, &kClipKey, clip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (clip) {
        if (clip.superview != sheet) [sheet insertSubview:clip atIndex:0];
        else if (sheet.subviews.firstObject != clip) [sheet sendSubviewToBack:clip];
        if (!CGRectEqualToRect(clip.frame, sheet.bounds)) clip.frame = sheet.bounds;
    }
    // Whatever is hidden for the clip that is not to be any more comes back; what is to be goes.
    NSMutableSet<UIView *> *wanted = [NSMutableSet set];
    if (on) {
        [wanted addObject:large];
        [wanted addObjectsFromArray:widgets];
    }
    for (UIView *view in sg_hidden.allObjects) if (![wanted containsObject:view]) hide(view, NO);
    for (UIView *view in wanted) if (![sg_hidden containsObject:view]) hide(view, YES);
    if (!clip) return;
    if (on) {
        [clip playClip:sg_clip];
        [clip setPlaying:sg_playing];
        [UIView animateWithDuration:kFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ clip.alpha = 1; } completion:nil];
    } else {
        // Faded as it is, playing, and stopped only once it is out of sight.
        [UIView animateWithDuration:kFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ clip.alpha = 0; }
                         completion:^(BOOL finished) { if (!(sg_on && sg_large && sg_clip)) [clip playClip:nil]; }];
    }
}

// Spotify's clip for the song, from the data container of the now playing app, copied so the player takes a new file.
static void readClip(void) {
    if (!sg_getApp) return;
    sg_getApp(dispatch_get_main_queue(), ^(CFStringRef bundle) {
        NSString *identifier = (__bridge NSString *)bundle;
        Class proxies = NSClassFromString(@"LSApplicationProxy");
        NSURL *container = identifier.length && proxies ? [[proxies applicationProxyForIdentifier:identifier] dataContainerURL] : nil;
        NSURL *clip = [container URLByAppendingPathComponent:@"Library/Caches/" kSGLockClipName];
        if (sg_clip.isFileURL) [NSFileManager.defaultManager removeItemAtURL:sg_clip error:nil];
        sg_clip = nil;
        if (clip && [NSFileManager.defaultManager fileExistsAtPath:clip.path]) {
            NSURL *copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vitrine-lockclip-%u.mp4", arc4random()]]];
            if ([NSFileManager.defaultManager copyItemAtURL:clip toURL:copy error:nil]) sg_clip = copy;
        }
        update();
    });
}

static void readPlaying(void) {
    if (!sg_isPlaying) return;
    sg_isPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
        sg_playing = playing;
        SGVLockClip *clip = sg_sheet ? objc_getAssociatedObject(sg_sheet, &kClipKey) : nil;
        [clip setPlaying:playing];
    });
}

%hook CSCoverSheetViewController
- (void)viewDidLoad {
    %orig;
    sg_sheet = ((UIViewController *)self).view;
}

- (void)viewDidLayoutSubviews {
    %orig;
    sg_sheet = ((UIViewController *)self).view;
    if (sg_on || sg_hidden.count) update();
}
%end

// The large cover opening and closing lays itself out without always laying out the sheet around it.
%hook UIView
- (void)layoutSubviews {
    %orig;
    if (!sg_on || !sg_sheet) return;
    static Class artwork;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ artwork = NSClassFromString(@"MRUArtworkView"); });
    if (!artwork || ![self isKindOfClass:artwork]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ update(); });
}
%end

static void listenArt(const char *name, BOOL on) {
    int token;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) {
        sg_on = on;
        update();
    });
}

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (@available(iOS 26.0, *)) return;
    void *remote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    sg_getApp = remote ? (SGMRGetApp)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationDisplayID") : NULL;
    sg_isPlaying = remote ? (SGMRIsPlaying)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    SGMRRegister registerFor = remote ? (SGMRRegister)dlsym(remote, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    %init;
    if (registerFor) registerFor(dispatch_get_main_queue());
    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ readPlaying(); });
    }];
    readPlaying();
    listenArt(kSGRelayLockArtOn, YES);
    listenArt(kSGRelayLockArtOff, NO);
    int clipToken, noneToken;
    notify_register_dispatch(kSGRelayLockClip, &clipToken, dispatch_get_main_queue(), ^(int t) { readClip(); });
    notify_register_dispatch(kSGRelayLockClipNone, &noneToken, dispatch_get_main_queue(), ^(int t) {
        if (sg_clip.isFileURL) [NSFileManager.defaultManager removeItemAtURL:sg_clip error:nil];
        sg_clip = nil;
        update();
    });
}
