// Vitrine Haptics, the lock screen's full-screen cover below iOS 26: while Spotify's switch for it is on
// (SGKeyLockCoverAddon, told as kSGRelayLockArtOn / kSGRelayLockArtOff), the now playing cover fills the lock screen
// behind its clock and its player, as iOS 26 fills it with an app's artwork. iOS 26 does it itself, so nothing is done
// there.
//
// The cover is read from MediaRemote, as the lock screen's own player reads it, and follows its now playing info as it
// changes. It is a view of the add-on's at the back of the cover sheet's view (CSCoverSheetViewController), over the
// wallpaper and under everything the lock screen draws, the cover filling the screen and a shade over its lower part so
// the player and the notifications stay legible. With no now playing info it goes.
//
// Threading: MediaRemote's answers come on the main queue; the view is the main thread's.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <notify.h>
#import "../../tweak/Sources/Shared/Haptics/SGHapticRelay.h"

@interface CSCoverSheetViewController : UIViewController
@end

typedef void (*SGMRGetInfo)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));
typedef void (*SGMRRegister)(dispatch_queue_t queue);

static const NSTimeInterval kCoverFade = 0.35;
// The shade over the cover's lower part, as dark as it gets at the bottom.
static const CGFloat kShadeBottom = 0.55;

static SGMRGetInfo sg_getInfo;
static BOOL sg_on;
static UIImage *sg_cover;
static NSData *sg_coverData;
static __weak UIView *sg_holder;

@interface SGVLockCover : UIView
@property (nonatomic, readonly) UIImageView *picture;
@end

@implementation SGVLockCover {
    CAGradientLayer *_shade;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.backgroundColor = UIColor.blackColor;
    _picture = [UIImageView new];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
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
    [CATransaction setDisableActions:YES];
    _shade.frame = self.bounds;
    [CATransaction commit];
}

@end

static char kCoverKey;

// The cover view as it should be now: shown with the cover while the switch is on and something plays, else gone.
static void showCover(void) {
    UIView *holder = sg_holder;
    if (!holder) return;
    SGVLockCover *cover = objc_getAssociatedObject(holder, &kCoverKey);
    BOOL shown = sg_on && sg_cover;
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
    }
    [UIView animateWithDuration:kCoverFade animations:^{ cover.alpha = shown ? 1 : 0; }];
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
        if (!image) return;
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
    SGMRRegister registerFor = remote ? (SGMRRegister)dlsym(remote, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    if (!sg_getInfo || !registerFor) return;
    %init;
    registerFor(dispatch_get_main_queue());
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (sg_on) readCover(); });
        }];
    }
    listenArt(kSGRelayLockArtOn, YES);
    listenArt(kSGRelayLockArtOff, NO);
}
