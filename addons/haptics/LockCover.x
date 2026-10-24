// Vitrine Addon, the lock screen's full-screen cover below iOS 26: while Spotify's switch for it is on
// (SGKeyLockCoverAddon, told as kSGRelayLockArtOn / kSGRelayLockArtOff), the now playing cover fills the lock screen
// behind its clock and its player, as iOS 26 fills it with an app's artwork. iOS 26 does it itself, so nothing is done
// there.
//
// The cover is read from MediaRemote, as the lock screen's own player reads it, and follows its now playing info as it
// changes. A cover all of one grey (the skeleton Spotify names for a moment before the cover is in, after a seek) is
// left out. Over it the track's moving artwork plays, looping, when Spotify has one (kSGRelayLockClip): a file in
// Spotify's caches, found through the data container of the now playing app. The cover and the clip are fitted whole to
// the screen's width rather than filling it (a square cover or a 9:16 Canvas filled a 9:19.5 screen cut off at both
// sides, far too large), and the bands above and below them take the colour of the picture's own top and bottom edges,
// as a redesigned playlist's page runs on in its cover's colour below it (Redesigned/Kit/SGRPalette.h); for a clip, its
// first frame's.
//
// The clip is not played by an AVPlayer: one in SpringBoard took an audio session, which the system counted as playback
// and paused Spotify for, and once Spotify played again the player was the one paused, left on a still frame (the phone,
// 2026-10-24). Its frames are read from the file (AVAssetReader, the video track alone, as they are compressed) and
// handed to an AVSampleBufferDisplayLayer on a timebase of its own, looped by starting the reader over with the times
// moved on: no audio session, no now playing, nothing of Spotify's to interrupt. It is a view of the add-on's at the back of the cover sheet's view (CSCoverSheetViewController), over the
// wallpaper and under everything the lock screen draws, the cover filling the screen and a shade over its lower part so
// the player and the notifications stay legible. With no now playing info it goes, and while the song is paused, so the
// lock screen has its wallpaper back until it plays again, unless Spotify's Hide while paused is off.
//
// Threading: MediaRemote's answers come on the main queue; the view is the main thread's.
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <notify.h>
#import "../../tweak/Sources/Shared/Haptics/SGHapticRelay.h"

@interface CSCoverSheetViewController : UIViewController
@end

typedef void (*SGMRGetInfo)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));
typedef void (*SGMRRegister)(dispatch_queue_t queue);
typedef void (*SGMRGetApp)(dispatch_queue_t queue, void (^handler)(CFStringRef bundle));
typedef void (*SGMRIsPlaying)(dispatch_queue_t queue, void (^handler)(Boolean playing));

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

static const NSTimeInterval kCoverFade = 0.35;
// The shade over the cover's lower part, as dark as it gets at the bottom.
static const CGFloat kShadeBottom = 0.55;

static SGMRGetInfo sg_getInfo;
static SGMRGetApp sg_getApp;
static SGMRIsPlaying sg_isPlaying;
// Whether the now playing app is playing: paused, the artwork goes, the cover and the clip alike, and comes back as it
// plays again (the phone, 2026-10-24: the still cover stayed over a paused song).
static BOOL sg_playing;
// Spotify's switch for it, on until switched off: off, the artwork stays over a paused song, as it did at first.
static BOOL sg_hidePaused = YES;
static NSURL *sg_clip;   // the clip to play, nil for the still cover
static BOOL sg_on;
// The still cover where there is no clip (Spotify's switch, on until switched off): off, the cover shows only with a clip.
static BOOL sg_still = YES;
static UIImage *sg_cover;
static NSData *sg_coverData;
static __weak UIView *sg_holder;

@interface SGVLockCover : UIView
@property (nonatomic, readonly) UIImageView *picture;
@end

// The average colour of `image`'s top and bottom strips, a twentieth of its height each.
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
    // The bitmap's first row is the picture's top.
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

@implementation SGVLockCover {
    CAGradientLayer *_shade;
    CAGradientLayer *_bands;
    AVSampleBufferDisplayLayer *_video;
    dispatch_queue_t _feed;
    AVURLAsset *_asset;
    AVAssetTrack *_track;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_output;
    CMTime _offset;
    NSURL *_playing;
    NSUInteger _run;
}

// The clip over the cover, looping, or none: the blurred cover shows round it, and alone until its first frame.
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
    if (!clip) {
        [self paintBands:_picture.image.CGImage];
        return;
    }
    _asset = [AVURLAsset URLAssetWithURL:clip options:nil];
    // The bands in the clip's colours, from its first frame, once it is made.
    AVAssetImageGenerator *frames = [AVAssetImageGenerator assetImageGeneratorWithAsset:_asset];
    frames.appliesPreferredTrackTransform = YES;
    frames.maximumSize = CGSizeMake(64, 64);
    __weak SGVLockCover *weakSelf = self;
    NSUInteger asked = _run;
    [frames generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:kCMTimeZero]]
                                 completionHandler:^(CMTime requested, CGImageRef image, CMTime actual, AVAssetImageGeneratorResult result, NSError *error) {
        if (result != AVAssetImageGeneratorSucceeded || !image) return;
        CGImageRetain(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            SGVLockCover *cover = weakSelf;
            if (cover && cover->_run == asked) [cover paintBands:image];
            CGImageRelease(image);
        });
    }];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    _track = [_asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
#pragma clang diagnostic pop
    if (!_track) return;
    if (!_feed) _feed = dispatch_queue_create("com.vitrine.addon.lockclip", DISPATCH_QUEUE_SERIAL);
    _video = [AVSampleBufferDisplayLayer layer];
    _video.videoGravity = AVLayerVideoGravityResizeAspect;
    _video.frame = self.bounds;
    CMTimebaseRef timebase = NULL;
    CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &timebase);
    CMTimebaseSetTime(timebase, kCMTimeZero);
    CMTimebaseSetRate(timebase, 1);
    _video.controlTimebase = timebase;
    if (timebase) CFRelease(timebase);
    [self.layer insertSublayer:_video below:_shade];
    _offset = kCMTimeZero;
    NSUInteger run = _run;
    AVSampleBufferDisplayLayer *video = _video;
    dispatch_async(_feed, ^{
        if (run != self->_run || ![self startReader]) return;
        [video requestMediaDataWhenReadyOnQueue:self->_feed usingBlock:^{ [self feed:video run:run]; }];
    });
}

// The bands above and below the picture in its top and bottom edges' colours, the top's at the top running into the
// bottom's at the bottom, eased across as the picture changes.
- (void)paintBands:(CGImageRef)image {
    if (!image) return;
    UIColor *top, *bottom;
    edgeColors(image, &top, &bottom);
    NSArray *colors = @[(id)top.CGColor, (id)bottom.CGColor];
    CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:@"colors"];
    ease.fromValue = (_bands.presentationLayer ?: _bands).colors;
    ease.duration = kCoverFade;
    [_bands addAnimation:ease forKey:@"colors"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _bands.colors = colors;
    [CATransaction commit];
}

// The clip read once more from its start: the video track alone, its samples as they are in the file.
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
            // The end of the clip: on from its start, every time moved on by its length.
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

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    _bands = [CAGradientLayer layer];
    _bands.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor];
    [self.layer addSublayer:_bands];
    _picture = [UIImageView new];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_picture];
    _shade = [CAGradientLayer layer];
    _shade.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:kShadeBottom].CGColor];
    _shade.locations = @[@0.35, @1];
    [self.layer addSublayer:_shade];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _picture.frame = self.bounds;
    [CATransaction begin];
    _bands.frame = self.bounds;
    [CATransaction setDisableActions:YES];
    _shade.frame = self.bounds;
    _video.frame = self.bounds;
    [CATransaction commit];
}

@end

static char kCoverKey;

// The cover view as it should be now: shown with the cover while the switch is on and something plays, else gone.
static void showCover(void) {
    UIView *holder = sg_holder;
    if (!holder) return;
    SGVLockCover *cover = objc_getAssociatedObject(holder, &kCoverKey);
    BOOL shown = sg_on && (sg_playing || !sg_hidePaused) && sg_cover && (sg_clip || sg_still);
    if (!cover && !shown) return;
    if (!cover) {
        cover = [[SGVLockCover alloc] initWithFrame:holder.bounds];
        cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cover.alpha = 0;
        objc_setAssociatedObject(holder, &kCoverKey, cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (cover.superview != holder) [holder insertSubview:cover atIndex:0];
    else if (holder.subviews.firstObject != cover) [holder sendSubviewToBack:cover];
    if (!CGRectEqualToRect(cover.frame, holder.bounds)) cover.frame = holder.bounds;
    if (shown && cover.picture.image != sg_cover) {
        [UIView transitionWithView:cover.picture duration:kCoverFade options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ cover.picture.image = sg_cover; } completion:nil];
        if (!sg_clip) [cover paintBands:sg_cover.CGImage];
    }
    if (shown) {
        [cover playClip:sg_clip];
        [UIView animateWithDuration:kCoverFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ cover.alpha = 1; } completion:nil];
        return;
    }
    // Going: the whole of it fades as it is, the clip still playing under the fade, and the clip stops only once it is
    // out of sight. Stopped first, the cover came up under the clip for a moment before it faded too (the phone,
    // 2026-10-24: a Canvas paused).
    [UIView animateWithDuration:kCoverFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ cover.alpha = 0; }
                     completion:^(BOOL finished) {
        BOOL still = sg_on && (sg_playing || !sg_hidePaused) && sg_cover && (sg_clip || sg_still);
        if (!still) [cover playClip:nil];
    }];
}

// A picture all of one colour, near enough: the grey skeleton Spotify names as the cover for a moment.
static BOOL isSkeleton(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) return YES;
    enum { side = 8 };
    uint8_t pixels[side * side * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return NO;
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), cg);
    CGContextRelease(context);
    int lo = 255, hi = 0;
    for (int i = 0; i < side * side; i++) {
        int luma = (pixels[i * 4] * 3 + pixels[i * 4 + 1] * 6 + pixels[i * 4 + 2]) / 10;
        lo = MIN(lo, luma);
        hi = MAX(hi, luma);
    }
    return hi - lo < 12;
}

// Spotify's clip for the playing track, in the data container of the now playing app.
static void readClip(void) {
    if (!sg_getApp) return;
    sg_getApp(dispatch_get_main_queue(), ^(CFStringRef bundle) {
        NSString *identifier = (__bridge NSString *)bundle;
        Class proxies = NSClassFromString(@"LSApplicationProxy");
        NSURL *container = identifier.length && proxies ? [[proxies applicationProxyForIdentifier:identifier] dataContainerURL] : nil;
        NSURL *clip = [container URLByAppendingPathComponent:@"Library/Caches/" kSGLockClipName];
        // A new path each time, so the player takes the new file rather than the one it has.
        if (clip && [NSFileManager.defaultManager fileExistsAtPath:clip.path]) {
            NSURL *copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vitrine-lockclip-%u.mp4", arc4random()]]];
            if (sg_clip.isFileURL) [NSFileManager.defaultManager removeItemAtURL:sg_clip error:nil];
            sg_clip = [NSFileManager.defaultManager copyItemAtURL:clip toURL:copy error:nil] ? copy : nil;
        } else {
            sg_clip = nil;
        }
        showCover();
    });
}

// The now playing cover, read again: MediaRemote's info carries it as image data.
static void readCover(void) {
    if (!sg_getInfo) return;
    sg_getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        NSDictionary *now = (__bridge NSDictionary *)info;
        NSData *data = now[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if (![data isKindOfClass:NSData.class] || !data.length) {
            // A change with no artwork in it (the position, the rate) leaves the cover; no info at all takes it away.
            if (!now.count) {
                sg_cover = nil;
                sg_coverData = nil;
                showCover();
            }
            return;
        }
        if ([data isEqualToData:sg_coverData]) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image || isSkeleton(image)) return;
        sg_coverData = data;
        sg_cover = image;
        showCover();
    });
}

%hook CSCoverSheetViewController
- (void)viewDidLoad {
    %orig;
    sg_holder = ((UIViewController *)self).view;
    showCover();
}

- (void)viewWillLayoutSubviews {
    %orig;
    sg_holder = ((UIViewController *)self).view;
    if (sg_on) showCover();
}
%end

// Playing or paused, as MediaRemote has it now.
static void readPlaying(void) {
    if (!sg_isPlaying) return;
    sg_isPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
        if (sg_playing == (BOOL)playing) return;
        sg_playing = playing;
        showCover();
    });
}

static void listenArt(const char *name, BOOL on) {
    int token;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) {
        sg_on = on;
        if (on) readCover();
        showCover();
    });
}

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (@available(iOS 26.0, *)) return;
    void *remote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    sg_getInfo = remote ? (SGMRGetInfo)dlsym(remote, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    sg_getApp = remote ? (SGMRGetApp)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationDisplayID") : NULL;
    sg_isPlaying = remote ? (SGMRIsPlaying)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    SGMRRegister registerFor = remote ? (SGMRRegister)dlsym(remote, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    if (!sg_getInfo || !registerFor) return;
    %init;
    registerFor(dispatch_get_main_queue());
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (sg_on) readCover(); });
        }];
    }
    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ readPlaying(); });
    }];
    readPlaying();
    listenArt(kSGRelayLockArtOn, YES);
    listenArt(kSGRelayLockArtOff, NO);
    int pauseHidesToken, pauseStaysToken;
    notify_register_dispatch(kSGRelayLockPauseHides, &pauseHidesToken, dispatch_get_main_queue(), ^(int t) { sg_hidePaused = YES; showCover(); });
    notify_register_dispatch(kSGRelayLockPauseStays, &pauseStaysToken, dispatch_get_main_queue(), ^(int t) { sg_hidePaused = NO; showCover(); });
    int stillOnToken, stillOffToken;
    notify_register_dispatch(kSGRelayLockStillOn, &stillOnToken, dispatch_get_main_queue(), ^(int t) { sg_still = YES; showCover(); });
    notify_register_dispatch(kSGRelayLockStillOff, &stillOffToken, dispatch_get_main_queue(), ^(int t) { sg_still = NO; showCover(); });
    int clipToken, noneToken;
    notify_register_dispatch(kSGRelayLockClip, &clipToken, dispatch_get_main_queue(), ^(int t) { readClip(); });
    notify_register_dispatch(kSGRelayLockClipNone, &noneToken, dispatch_get_main_queue(), ^(int t) {
        if (sg_clip.isFileURL) [NSFileManager.defaultManager removeItemAtURL:sg_clip error:nil];
        sg_clip = nil;
        showCover();
    });
}
