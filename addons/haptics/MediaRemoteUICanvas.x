// Vitrine Addon in MediaRemoteUI, the lock screen's Canvas below iOS 26: MediaRemoteUI draws the lock screen's player
// and, when its cover is tapped, the large cover over the lock screen, in a window of its own
// (MediaRemoteUI.SecureWindow, full screen) holding MediaRemoteUI.CoverSheetBackgroundView: an MTKView for the coloured
// field and the large MRUArtworkView, 352pt on a 414pt phone (the phone's tree, 2026-10-24). The player's own small
// cover is in its other window, and the system takes it away as the large one opens.
//
// While the large cover is open, Spotify's switch is on (kSGRelayLockArtOn) and SpringBoard has shared the song's clip
// (kSGRelayLockClipShared, SGLockSharedClipPath), the large cover is hidden and the clip shown full screen in its place,
// over the field (LockClipView.h), and SpringBoard is told (kSGRelayLockShowing) to hide the widgets under the clock.
// A clip that comes later takes the cover's place as it comes; with none the system's cover stays as it is, and closed,
// everything of the system's comes back. The clip holds still while the song is paused.
//
// Only the large cover's view is hooked, as it lays out and as it comes and goes.
//
// Threading: main thread.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <notify.h>
#import "LockClipView.h"
#import "../../tweak/Sources/Shared/Haptics/SGHapticRelay.h"

typedef void (*SGMRIsPlaying)(dispatch_queue_t queue, void (^handler)(Boolean playing));
typedef void (*SGMRRegister)(dispatch_queue_t queue);

static const NSTimeInterval kFade = 0.35;

static SGMRIsPlaying sg_isPlaying;
static BOOL sg_on, sg_playing = YES, sg_showing;
static NSURL *sg_clip;   // this process's own copy of the shared clip, nil for none
static __weak UIView *sg_field;   // the large cover's CoverSheetBackgroundView, while it is open
static char kClipKey;

// The large cover in the field: the field's MRUArtworkView.
static UIView *artworkIn(UIView *field) {
    Class artwork = NSClassFromString(@"MRUArtworkView");
    for (UIView *sub in field.subviews) if (artwork && [sub isKindOfClass:artwork]) return sub;
    return nil;
}

static void tellShowing(BOOL showing) {
    if (sg_showing == showing) return;
    sg_showing = showing;
    notify_post(showing ? kSGRelayLockShowing : kSGRelayLockNotShowing);
}

static void apply(void) {
    UIView *field = sg_field;
    if (!field.window) {
        tellShowing(NO);
        return;
    }
    UIView *artwork = artworkIn(field);
    BOOL on = sg_on && sg_clip && artwork;
    SGVLockClip *clip = objc_getAssociatedObject(field, &kClipKey);
    if (!clip && on) {
        clip = [[SGVLockClip alloc] initWithFrame:field.bounds];
        clip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        clip.alpha = 0;
        objc_setAssociatedObject(field, &kClipKey, clip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (clip) {
        // Over the field (its MTKView), under the large cover.
        if (clip.superview != field) {
            if (artwork) [field insertSubview:clip belowSubview:artwork];
            else [field addSubview:clip];
        }
        if (!CGRectEqualToRect(clip.frame, field.bounds)) clip.frame = field.bounds;
    }
    tellShowing(on);
    [UIView animateWithDuration:kFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        artwork.alpha = on ? 0 : 1;
        clip.alpha = on ? 1 : 0;
    } completion:^(BOOL finished) {
        if (!(sg_on && sg_clip && artworkIn(field))) [clip playClip:nil];
    }];
    if (on) {
        [clip playClip:sg_clip];
        [clip setPlaying:sg_playing];
    }
}

// The shared clip copied into this process's own temporary folder under a new name, so the clip view takes a new file.
static void readShared(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    if (sg_clip) [files removeItemAtURL:sg_clip error:nil];
    sg_clip = nil;
    NSString *shared = SGLockSharedClipPath();
    NSURL *copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vitrine-lockclip-%u.mp4", arc4random()]]];
    NSError *error = nil;
    if ([files copyItemAtURL:[NSURL fileURLWithPath:shared] toURL:copy error:&error]) sg_clip = copy;
    else NSLog(@"[vitrine-addon] MediaRemoteUI cannot read the shared clip: %@", error.localizedDescription);
    apply();
}

static void readPlaying(void) {
    if (!sg_isPlaying) return;
    sg_isPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
        sg_playing = playing;
        SGVLockClip *clip = sg_field ? objc_getAssociatedObject(sg_field, &kClipKey) : nil;
        [clip setPlaying:playing];
    });
}

%hook _TtC13MediaRemoteUI24CoverSheetBackgroundView
- (void)didMoveToWindow {
    %orig;
    UIView *field = (UIView *)self;
    if (field.window) sg_field = field;
    apply();
}

- (void)layoutSubviews {
    %orig;
    sg_field = (UIView *)self;
    if (sg_on || sg_showing) apply();
}
%end

static void listen(const char *name, void (^handler)(void)) {
    int token;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) { handler(); });
}

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MediaRemoteUI"]) return;
    if (@available(iOS 26.0, *)) return;
    if (!objc_getClass("_TtC13MediaRemoteUI24CoverSheetBackgroundView")) {
        NSLog(@"[vitrine-addon] MediaRemoteUI has no CoverSheetBackgroundView, the lock screen's Canvas is off");
        return;
    }
    void *remote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    sg_isPlaying = remote ? (SGMRIsPlaying)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    SGMRRegister registerFor = remote ? (SGMRRegister)dlsym(remote, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    %init;
    if (registerFor) registerFor(dispatch_get_main_queue());
    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ readPlaying(); });
    }];
    readPlaying();
    listen(kSGRelayLockArtOn, ^{ sg_on = YES; apply(); });
    listen(kSGRelayLockArtOff, ^{ sg_on = NO; apply(); });
    listen(kSGRelayLockClipShared, ^{ readShared(); });
    listen(kSGRelayLockClipNone, ^{
        if (sg_clip) [NSFileManager.defaultManager removeItemAtURL:sg_clip error:nil];
        sg_clip = nil;
        apply();
    });
    // The switch and the clip as they are now: Spotify answers SpringBoard's pong to this ping with the switch, and a
    // clip already shared is in the shared caches.
    notify_post(kSGRelayPing);
    if ([NSFileManager.defaultManager fileExistsAtPath:SGLockSharedClipPath()]) readShared();
    NSLog(@"[vitrine-addon] MediaRemoteUI ready for the lock screen's Canvas");
}
