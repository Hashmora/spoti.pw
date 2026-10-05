// The action row's controls: the Play capsule and the button that stands in for one of Spotify's.
//
// Both are drawn from what Spotify's own button shows, and neither keeps state of its own. The glyph is
// looked for past what is hidden behind it -- a play button's glow ring is a hidden view holding an image
// of its own, and taken for the glyph it put a soft green ring in the capsule (device, 2026-09-17) -- and
// it is watched afterwards, because Spotify swaps play for pause without laying the header out again.
#import "Core/PGCore.h"
#import "PGRActionRow.h"
#import "PGRGlass.h"
#import "PGRRestyle.h"
#import "PGRTokens.h"
#import "PGRAccent.h"
#import "PGRDownload.h"

// The capsule: the glyph is Spotify's own 48pt canvas with the triangle small in the middle of it, so the
// lead is short and the gap to the word comes out of the canvas itself.
static const CGFloat kGlyphSide = 44, kCapsuleLead = 4, kCapsuleTrail = 20;
// The mirrored glyph, the size Spotify draws one inside a 48pt round button.
static const CGFloat kMirrorGlyph = 24;

static char kCapsuleGlassKey, kMirrorGlassKey;

// The glyph Spotify's button draws: an image view of the button's own size that nothing hidden is in the
// way of. `side` is the size to match, 0 for any image view that is showing.
static UIImageView *glyphIn(UIView *button, CGFloat side) {
    __block UIImageView *glyph = nil;
    PGForEachView(button, ^(UIView *v) {
        if (glyph || ![v isKindOfClass:UIImageView.class] || !((UIImageView *)v).image) return;
        if (side > 0 && (fabs(v.bounds.size.width - side) > 2 || fabs(v.bounds.size.height - side) > 2)) return;
        for (UIView *up = v; up && up != button; up = up.superview) {
            if (up.hidden || up.alpha <= 0.01) return;
        }
        glyph = (UIImageView *)v;
    });
    return glyph;
}

static NSString *wordIn(UIView *button) {
    __block NSString *word = nil;
    PGForEachView(button, ^(UIView *v) {
        if (!word && v.accessibilityLabel.length) word = v.accessibilityLabel;
    });
    return word;
}

#pragma mark - the Play capsule

@implementation PGRPlayCapsule {
    UIImageView *_glyph;
    UILabel *_title;
    __weak UIImageView *_watchedGlyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];

    _title = [UILabel new];
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(pgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(pgr_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addTarget:self action:@selector(pgr_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (CGFloat)pgr_width {
    [_title sizeToFit];
    return kCapsuleLead + kGlyphSide + ceil(_title.bounds.size.width) + kCapsuleTrail;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (self.fillColor) {
        if (![self.backgroundColor isEqual:self.fillColor]) self.backgroundColor = self.fillColor;
        self.layer.cornerRadius = bounds.size.height / 2;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    } else {
        PGRGlassCapsuleInside(self, &kCapsuleGlassKey, bounds.size, YES);
    }
    // Given more room than the word asks for, the glyph and the word stay together in the middle.
    CGFloat lead = kCapsuleLead + MAX(0, round((bounds.size.width - [self pgr_width]) / 2));
    _glyph.frame = CGRectMake(lead, round((bounds.size.height - kGlyphSide) / 2), kGlyphSide, kGlyphSide);
    // Spotify's glyph comes on a 48pt canvas and is scaled down into the frame; one drawn tight is shown at
    // its own size instead of blown up to fill it.
    CGSize image = _glyph.image.size;
    UIViewContentMode mode = image.width <= kGlyphSide && image.height <= kGlyphSide ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit;
    if (_glyph.contentMode != mode) _glyph.contentMode = mode;
    [_title sizeToFit];
    CGSize text = _title.bounds.size;
    _title.frame = CGRectMake(CGRectGetMaxX(_glyph.frame), round((bounds.size.height - text.height) / 2),
                              MAX(0, bounds.size.width - kCapsuleTrail - CGRectGetMaxX(_glyph.frame)), text.height);
}

- (void)feedFrom:(UIView *)source {
    if (!source) return;
    _source = source;

    NSString *word = wordIn(source);
    // The disc is as tall as the button, not always as wide: Liked Songs' is 80x48 with the 48pt disc at
    // x=16 (trees/continuous/1.txt, 2026-09-18), and matched by width the capsule drew no glyph at all.
    CGSize size = source.bounds.size;
    UIImageView *glyph = glyphIn(source, MIN(size.width, size.height));

    UIFont *font = PGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    if (![_title.font isEqual:font]) _title.font = font;
    UIColor *content = self.contentColor ?: PGRAccent();
    if (![_title.textColor isEqual:content]) _title.textColor = content;
    if (word && ![_title.text isEqualToString:word]) {
        _title.text = word;
        self.accessibilityLabel = word;
        [self setNeedsLayout];
    }
    if (![_glyph.tintColor isEqual:content]) _glyph.tintColor = content;

    if (glyph.image && _glyph.image != glyph.image) {
        _glyph.image = [glyph.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            PGLog(@"redesign kit: play glyph %@ from %@, word \"%@\"", NSStringFromCGSize(glyph.image.size),
                  NSStringFromClass(glyph.class), word);
        });
    }
    // Play becomes pause without the header laying out again. Watched per glyph view rather than once for
    // good, so a glyph Spotify hands to another button reports to the button it is in now.
    if (glyph && glyph != _watchedGlyph) {
        _watchedGlyph = glyph;
        __weak PGRPlayCapsule *weakSelf = self;
        __weak UIView *weakSource = source;
        PGRObserveImage(glyph, ^(UIImageView *view) {
            if (weakSelf && weakSource) [weakSelf feedFrom:weakSource];
        });
    }
}

- (void)pgr_down {
    PGRAnimate(PGRMotionPress, ^{ self.transform = CGAffineTransformMakeScale(0.94, 0.94); }, nil);
}

- (void)pgr_up {
    PGRAnimate(PGRMotionPress, ^{ self.transform = CGAffineTransformIdentity; }, nil);
}

- (void)pgr_tap {
    PGRActivate(self.source);
}

@end

#pragma mark - a button standing in for Spotify's

// Whether a button that marks "on" with a small dot under its glyph (Encore's shuffle, a 4pt round view it
// hides while off) is on. `found` says whether the button has such a dot at all.
static BOOL indicatorOn(UIView *button, BOOL *found) {
    __block UIView *dot = nil;
    PGForEachView(button, ^(UIView *v) {
        if (dot || v == button || [v isKindOfClass:UIImageView.class] || [v isKindOfClass:UILabel.class]) return;
        CGSize size = v.bounds.size;
        if (size.width < 2 || size.width > 8 || size.height < 2 || size.height > 8) return;
        CGColorRef paint = v.layer.backgroundColor;
        if (paint && CGColorGetAlpha(paint) > 0.5) dot = v;
    });
    if (found) *found = dot != nil;
    for (UIView *up = dot; up && up != button; up = up.superview) {
        if (up.hidden || up.alpha <= 0.01) return NO;
    }
    return dot != nil;
}

@implementation PGRMirrorButton {
    UIImageView *_glyph;
    __weak UIImageView *_watchedGlyph;
    // Spotify's own image, as it was taken: what the copy is compared against, since a copy re-rendered as
    // a template is no longer the same object.
    UIImage *_takenGlyph;
    // Standing in for Spotify's download button: its state drawn, and read again while on screen.
    PGRDownloadGlyph *_download;
    NSTimer *_downloadTimer;
    // A two-state glyph drawn for Spotify (add-to, readState): 1 on, 0 off, -1 none drawn.
    NSInteger _stateShown;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];
    _stateShown = -1;

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(pgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(pgr_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addTarget:self action:@selector(pgr_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    // Until its state is known the button draws nothing: a guess would flash the wrong glyph first.
    if (self.readState && _stateShown < 0) {
        ((UIView *)objc_getAssociatedObject(self, &kMirrorGlassKey)).hidden = YES;
        return;
    }
    PGRGlassInside(self, &kMirrorGlassKey, PGRGlassCircleSize);
    _glyph.frame = CGRectMake(round((bounds.size.width - kMirrorGlyph) / 2), round((bounds.size.height - kMirrorGlyph) / 2),
                              kMirrorGlyph, kMirrorGlyph);
    _download.frame = _glyph.frame;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!_download && _stateShown < 0 && !self.readState) return;
    // Read again on the way in -- the state may have moved on while the page was away -- and not at all
    // while out of the window.
    if (self.window && self.source) [self feedFrom:self.source];
    else [self pgr_followDownload:0];
}

- (void)dealloc {
    [_downloadTimer invalidate];
}

// Shows Spotify's download state; YES when `source` is a download button.
- (BOOL)pgr_feedDownloadFrom:(UIView *)source {
    PGRDownloadState state;
    CGFloat progress;
    if (!PGRReadDownload(source, &state, &progress)) {
        if (_download && !_download.hidden) {
            _download.hidden = YES;
            _glyph.hidden = NO;
            [self pgr_followDownload:0];
        }
        return NO;
    }
    if (!_download) {
        _download = [[PGRDownloadGlyph alloc] initWithFrame:_glyph.frame];
        [self addSubview:_download];
    }
    _download.hidden = NO;
    _glyph.hidden = YES;
    [_download showState:state progress:progress animated:YES];

    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    NSString *value = state == PGRDownloadDownloading && progress >= 0
        ? [NSNumberFormatter localizedStringFromNumber:@(progress) numberStyle:NSNumberFormatterPercentStyle] : nil;
    if (![self.accessibilityValue ?: @"" isEqualToString:value ?: @""]) self.accessibilityValue = value;

    // Spotify lays nothing out that the page hears as a download moves on, so the state is read again:
    // twice a second while one runs, for the ring, and now and then otherwise, for one started or removed
    // from elsewhere (the ⋯ sheet). Only while the button is on screen.
    BOOL running = state == PGRDownloadWaiting || state == PGRDownloadDownloading;
    [self pgr_followDownload:self.window ? (running ? 0.5 : 2) : 0];
    return YES;
}

// Draws `offSymbol`, or `onSymbol` in the accent colour, switching between them in place.
- (void)pgr_showOn:(BOOL)on off:(NSString *)offSymbol on:(NSString *)onSymbol source:(UIView *)source {
    if (_stateShown != on) {
        UIImage *image = [UIImage systemImageNamed:on ? onSymbol : offSymbol];
        BOOL animated = _stateShown >= 0 && self.window && !PGRReduceMotion();
        BOOL first = _stateShown < 0;
        _stateShown = on;
        _takenGlyph = nil;
        _glyph.hidden = NO;
        if (@available(iOS 17.0, *)) {
            if (animated) [_glyph setSymbolImage:image withContentTransition:[NSSymbolReplaceContentTransition replaceDownUpTransition]];
            else _glyph.image = image;
        } else {
            _glyph.image = image;
        }
        // On is saved or followed, in the accent colour, as downloaded is.
        _glyph.tintColor = on ? PGRAccent() : PGRPrimary();
        if (first) [self setNeedsLayout];
    }
    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    // Nothing is laid out when it changes from elsewhere (the ⋯ sheet), so it is read again as download is.
    [self pgr_followDownload:self.window ? 2 : 0];
}

// Shows whether Spotify's add-to button has its album or playlist saved; YES when `source` is one.
- (BOOL)pgr_feedAddToFrom:(UIView *)source {
    BOOL added;
    if (!PGRReadAddTo(source, &added)) {
        _stateShown = -1;
        return NO;
    }
    [self pgr_showOn:added off:@"plus" on:@"checkmark" source:source];
    return YES;
}

// Reads the state again every `interval` seconds; 0 stops.
- (void)pgr_followDownload:(NSTimeInterval)interval {
    if (interval <= 0) {
        [_downloadTimer invalidate];
        _downloadTimer = nil;
        return;
    }
    if (_downloadTimer.valid && fabs(_downloadTimer.timeInterval - interval) < 0.01) return;
    [_downloadTimer invalidate];
    __weak PGRMirrorButton *weakSelf = self;
    _downloadTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
        PGRMirrorButton *button = weakSelf;
        if (!button || !button.window || !button.source) {
            [timer invalidate];
            return;
        }
        [button feedFrom:button.source];
    }];
    _downloadTimer.tolerance = interval * 0.2;
}

// The glyph is taken as Spotify drew it, colour and all: the shuffle button turns its own glyph the accent
// colour while shuffle is on, and a copy rendered as a template would lose that.
- (void)feedFrom:(UIView *)source {
    if (!source) return;
    _source = source;

    if (self.readState) {
        BOOL on = NO;
        if (self.readState(&on)) [self pgr_showOn:on off:self.stateOffSymbol on:self.stateOnSymbol source:source];
        else [self pgr_followDownload:self.window ? 2 : 0];
        BOOL known = _stateShown >= 0;
        if (_glyph.hidden == known) _glyph.hidden = !known;
        if (self.userInteractionEnabled != known) {
            self.userInteractionEnabled = known;
            self.isAccessibilityElement = known;
        }
        return;
    }

    if ([self pgr_feedDownloadFrom:source]) return;
    if ([self pgr_feedAddToFrom:source]) return;

    UIImageView *glyph = glyphIn(source, 0);
    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    // A button that says "on" with its dot is drawn in our colours, on and off. One expected to have a dot
    // and found without keeps Spotify's colours, which are then all that tells on from off.
    BOOL hasDot = NO;
    BOOL on = self.onGlyphColor && indicatorOn(source, &hasDot);
    UIColor *ownColor = !self.onGlyphColor ? self.glyphColor
                      : hasDot ? (on ? self.onGlyphColor : self.glyphColor ?: PGRPrimary()) : nil;
    if (glyph.image && (_takenGlyph != glyph.image || (ownColor != nil) != (_glyph.image.renderingMode == UIImageRenderingModeAlwaysTemplate))) {
        _takenGlyph = glyph.image;
        _glyph.image = ownColor ? [glyph.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : glyph.image;
    }
    if (!glyph && self.fallbackGlyph && _glyph.image != self.fallbackGlyph) {
        _takenGlyph = nil;
        _glyph.image = self.fallbackGlyph;
    }
    UIColor *tint = ownColor ?: (glyph ? glyph.tintColor : PGRPrimary());
    if (tint && ![_glyph.tintColor isEqual:tint]) {
        // Turning on or off is a moment of its own: the colour fades across rather than jumping.
        BOOL fade = self.window && _glyph.tintColor && hasDot;
        if (fade) {
            [UIView transitionWithView:_glyph duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self->_glyph.tintColor = tint; } completion:nil];
        } else {
            _glyph.tintColor = tint;
        }
    }

    // As the capsule does: watched per glyph view, so a reused one reports where it is now.
    if (glyph && glyph != _watchedGlyph) {
        _watchedGlyph = glyph;
        __weak PGRMirrorButton *weakSelf = self;
        __weak UIView *weakSource = source;
        PGRObserveImage(glyph, ^(UIImageView *view) {
            if (weakSelf && weakSource) [weakSelf feedFrom:weakSource];
        });
    }
}

- (void)pgr_down {
    PGRAnimate(PGRMotionPress, ^{ self.transform = CGAffineTransformMakeScale(0.92, 0.92); }, nil);
}

- (void)pgr_up {
    PGRAnimate(PGRMotionPress, ^{ self.transform = CGAffineTransformIdentity; }, nil);
}

- (void)pgr_tap {
    PGRActivate(self.source);
    // The word is watched where Spotify writes it, but a button that rebuilds its content on the state it
    // just took writes the new word into a label the watch has never seen. So a tap, and only a tap, asks
    // the button again a moment later, which also moves the watch onto whatever label it ended up with. The
    // same goes for shuffle's dot and a download's state, which change with no image or word to watch.
    __weak PGRMirrorButton *weakSelf = self;
    for (NSNumber *delay in @[@0.3, @1.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PGRMirrorButton *button = weakSelf;
            if (button.source) [button feedFrom:button.source];
        });
    }
}

@end

#pragma mark - the page's pinned ⋯

// A mirror of the back button, which UIKit draws as a 44pt glass circle at the top of the safe area, 16pt
// in from the leading edge (trees/continuous/1.txt:2554: the navigation bar's own glass at {16, 0} 44x44,
// the bar itself at the safe area's top). ⋯ takes the same size and the same insets on the other side, so
// the two read as one row on every page (issue #57).
static const CGFloat kCornerSide = 16;

// The page whose pinned ⋯ was last tapped, and when: what tells the sheet that opens a moment later which
// page's menu it is. The same trick Shared/Player/SpeedPitchMenu.x plays on the player's more button, but
// from this side of it, since this button is the redesign's own and knows its own page.
//
// Recorded on touch down rather than on touch up: the button's own -pgr_tap is registered first and fires
// Spotify's ⋯ from the same event, so a sheet Spotify puts up in that same turn would ask which page it
// belonged to before a target added after -pgr_tap had answered.
static __weak UIView *pg_morePage;
static NSTimeInterval pg_moreTappedAt;
static char kRecorderKey;

UIView *PGRPinnedMoreRecentPage(void) {
    if (!pg_morePage || CACurrentMediaTime() - pg_moreTappedAt > PGRPinnedMoreWindow) return nil;
    return pg_morePage;
}

@interface PGRPinnedMoreRecorder : NSObject
@end
@implementation PGRPinnedMoreRecorder
- (void)pgr_moreTapped:(PGRMirrorButton *)button {
    pg_morePage = button.superview;
    pg_moreTappedAt = CACurrentMediaTime();
}
@end

// Over the page's list and its header both, and put back on top whenever Spotify adds to the page.
static void keepOnTop(UIView *page, UIView *button) {
    if (button.superview != page) [page addSubview:button];
    else if (page.subviews.lastObject != button) [page bringSubviewToFront:button];
}

// Level with the window's safe area at the top, kCornerSide in from the leading or trailing edge of the
// page. The height is measured in the window and converted back, never from the page's own safe area: a
// page under a navigation bar counts the bar into its inset, so the playlist's read 116 where the window's
// reads 62 and the button sat a bar's height below the back button. The inset from the side is taken from
// the page's own bounds and not converted from the window: the swipe back slides the page across the
// window, and a frame converted from the window's x would hold the button still while the page left under
// it, over the screen below, until the page was gone and took it along.
static void placeInCorner(UIView *page, UIView *button, BOOL leading) {
    UIWindow *window = page.window;
    UIView *space = window ?: page;
    CGFloat side = PGRGlassCircleSize;
    CGFloat x = leading ? kCornerSide : page.bounds.size.width - kCornerSide - side;
    CGFloat y = space.safeAreaInsets.top;
    if (window) y = [page convertPoint:CGPointMake(0, y) fromView:nil].y;
    CGRect frame = CGRectMake(x, y, side, side);
    if (!CGRectIsEmpty(frame) && !CGRectEqualToRect(button.frame, frame)) button.frame = frame;
}

PGRMirrorButton *PGRPinnedMore(UIView *page, const void *key, UIView *source) {
    if (!page) return nil;
    PGRMirrorButton *button = objc_getAssociatedObject(page, key);
    if (!button) {
        button = [[PGRMirrorButton alloc] initWithFrame:CGRectZero];
        button.fallbackGlyph = [UIImage systemImageNamed:@"ellipsis"];
        // ⋯ sits in an Encore Tertiary button in Spotify's own row, which draws it grey; in the corner of
        // the page it is the one control there and reads white, like the back button opposite it.
        button.glyphColor = PGRPrimary();
        // Held by the button, which is held by the page, so the recorder lives exactly as long as both.
        PGRPinnedMoreRecorder *recorder = [PGRPinnedMoreRecorder new];
        objc_setAssociatedObject(button, &kRecorderKey, recorder, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addTarget:recorder action:@selector(pgr_moreTapped:) forControlEvents:UIControlEventTouchDown];
        objc_setAssociatedObject(page, key, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    keepOnTop(page, button);
    if (source) [button feedFrom:source];
    if (button.hidden != (source == nil)) button.hidden = source == nil;
    placeInCorner(page, button, NO);
    return button;
}

#pragma mark - the page's pinned back button

// Hides Spotify's own back button once it is mirrored: a mask survives Spotify showing it again, which
// -[UIView setHidden:] does not, and with no interaction and no accessibility only the mirror is seen or
// fired.
static void concealBack(UIView *source) {
    if (!source) return;
    if (!source.layer.hidden) source.layer.hidden = YES;
    if (!source.layer.mask) source.layer.mask = [CALayer layer];
    if (source.userInteractionEnabled) source.userInteractionEnabled = NO;
    source.accessibilityElementsHidden = YES;
}

PGRMirrorButton *PGRPinnedBack(UIView *page, UIView *searchRoot) {
    static char kSourceKey, kButtonKey;
    if (!page) return nil;
    UIView *source = PGRFindByIdentifier(searchRoot, @"Components.Header.UI.BackButton", &kSourceKey);
    PGRMirrorButton *button = objc_getAssociatedObject(page, &kButtonKey);
    if (!button) {
        button = [[PGRMirrorButton alloc] initWithFrame:CGRectZero];
        button.fallbackGlyph = [UIImage systemImageNamed:@"chevron.left"];
        button.glyphColor = PGRPrimary();
        button.accessibilityLabel = source.accessibilityLabel ?: @"Back";
        objc_setAssociatedObject(page, &kButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    keepOnTop(page, button);
    concealBack(source);
    if (source) [button feedFrom:source];
    if (button.hidden != (source == nil)) button.hidden = source == nil;
    placeInCorner(page, button, YES);
    return button;
}
