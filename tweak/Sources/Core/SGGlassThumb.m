#import "SGGlassThumb.h"
#import "SGGlass.h"
#import <objc/runtime.h>

static char kThumbKey, kImageKey, kSizeKey, kWatchKey, kPaneKey;

// How much the held glass is bigger than the capsule at rest, the way iOS 26's thumb swells under a finger.
static const CGFloat kLiftWidth = 1.5, kLiftHeight = 1.35;
// Past an end of the track the thumb follows the finger by this share of the overshoot, up to kMaxPull, and is
// stretched along the pull and thinned across it by its share of kPullStretch.
static const CGFloat kPullShare = 0.3, kMaxPull = 14, kPullStretch = 0.25;

#pragma mark - the capsule

@interface SGGlassThumbView : UIView
// How much bigger the held glass is, across and down (the slider's 1.5 and 1.35 unless set).
@property (nonatomic) CGFloat liftX, liftY;
- (void)setLifted:(BOOL)lifted;
- (void)setPull:(CGFloat)pull;
// No shadow under the capsule at rest: iOS 26's switch thumb is flat. Held, its glass wears the switch's bright rim.
- (void)setFlat;
@end

@implementation SGGlassThumbView {
    UIView *_pill;
    UIView *_pane;
    UIView *_rim;
    CAShapeLayer *_ring;
    BOOL _lifted;
    CGFloat _pull;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _liftX = kLiftWidth;
    _liftY = kLiftHeight;
    _pane = SGGlassFor(self, &kPaneKey);
    _pane.alpha = 0;
    // The held lens is the system's clear glass (adaptive_liquid_glass's clearDark): what is under it keeps its own
    // colour, barely blurred, under a white fill of 16% (#FDFAFB), and its edge bends more than a pane's (lens size
    // reference 28.7 against the regular glass's 38.8). On the boosted pane glass a switch's green showed through as a
    // solid neon blob (the phone, 2026-10-23).
    if ([_pane isKindOfClass:SGLegacyGlassView.class]) {
        SGLegacyGlassView *glass = (SGLegacyGlassView *)_pane;
        glass.clear = YES;
        glass.lensScale = 1.35;
    }
    _ring = [CAShapeLayer layer];
    _ring.fillColor = [UIColor colorWithRed:0xFD / 255.0 green:0xFA / 255.0 blue:0xFB / 255.0 alpha:0.16].CGColor;
    _ring.strokeColor = UIColor.clearColor.CGColor;
    _rim = [UIView new];
    _rim.userInteractionEnabled = NO;
    _rim.alpha = _pane.alpha;
    [_rim.layer addSublayer:_ring];
    [self addSubview:_rim];
    _pill = [UIView new];
    _pill.backgroundColor = UIColor.whiteColor;
    _pill.userInteractionEnabled = NO;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.layer.shadowColor = UIColor.blackColor.CGColor;
    _pill.layer.shadowOpacity = 0.18;
    _pill.layer.shadowRadius = 3;
    _pill.layer.shadowOffset = CGSizeMake(0, 1);
    [self addSubview:_pill];
    return self;
}

- (void)setFlat {
    _pill.layer.shadowOpacity = 0;
    // iOS 26's held switch thumb has a light rim and a soft glow round it; the 0.85 white of 2 pt read as a white
    // outline drawn on, not the glass's own edge.
    _ring.strokeColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
    _ring.lineWidth = 1.5;
    _ring.shadowColor = UIColor.whiteColor.CGColor;
    _ring.shadowOpacity = 0.25;
    _ring.shadowRadius = 4;
    _ring.shadowOffset = CGSizeZero;
    [self setNeedsLayout];
}

// The held glass is laid out at its held size and shrunk by a transform at rest, never grown from the capsule's: grown,
// it magnified the bit of track under the capsule, so the lens was the track's colour through and through (device,
// 2026-10-23) and showed nothing of what is round the track.
- (CGSize)heldSize {
    return CGSizeMake(self.bounds.size.width * _liftX, self.bounds.size.height * _liftY);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat radius = bounds.size.height / 2;
    CGPoint middle = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _pill.bounds = bounds;
    _pill.center = middle;
    _pill.layer.cornerRadius = radius;
    _pill.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius].CGPath;
    CGRect held = (CGRect){CGPointZero, [self heldSize]};
    if (!CGRectEqualToRect(_pane.bounds, held)) _pane.bounds = held;
    _pane.center = middle;
    SGShapeGlass(_pane, held.size.height / 2, YES);
    if (_rim) {
        _rim.bounds = held;
        _rim.center = middle;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CGRect inner = CGRectInset(held, 1, 1);
        _ring.frame = held;
        _ring.path = [UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:inner.size.height / 2].CGPath;
        [CATransaction commit];
    }
    [self applyLift];
}

- (void)applyLift {
    CGAffineTransform rest = CGAffineTransformMakeScale(1 / _liftX, 1 / _liftY);
    _pill.transform = _lifted ? CGAffineTransformMakeScale(_liftX, _liftY) : CGAffineTransformIdentity;
    _pane.transform = _lifted ? CGAffineTransformIdentity : rest;
    _rim.transform = _pane.transform;
}

// The pull is the whole thumb's transform; the swell is its parts' (applyLift), so either can change without the other
// jumping.
- (CGAffineTransform)pose {
    CGFloat stretch = fabs(_pull) / kMaxPull * kPullStretch;
    return CGAffineTransformScale(CGAffineTransformMakeTranslation(_pull, 0), 1 + stretch, 1 - stretch * 0.5);
}

- (void)setLifted:(BOOL)lifted {
    if (_lifted == lifted) return;
    _lifted = lifted;
    BOOL still = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:still ? 0.2 : (lifted ? 0.35 : 0.45) delay:0 usingSpringWithDamping:still ? 1 : (lifted ? 0.7 : 0.8)
          initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (!still) [self applyLift];
        self->_pill.alpha = lifted ? 0 : 1;
        self->_pane.alpha = lifted ? 1 : 0;
        self->_rim.alpha = self->_pane.alpha;
    } completion:nil];
}

- (void)setPull:(CGFloat)pull {
    if (UIAccessibilityIsReduceMotionEnabled()) pull = 0;
    if (_pull == pull) return;
    BOOL back = pull == 0;
    _pull = pull;
    if (!back) {
        self.transform = [self pose];
        return;
    }
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.transform = [self pose]; } completion:nil];
}

@end

#pragma mark - the finger

// Watches the slider's touches without taking any: the slider tracks them as it always does.
@interface SGGlassThumbWatch : UIGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, weak) SGGlassThumbView *thumb;
@end

@implementation SGGlassThumbWatch {
    UITouch *_touch;
    BOOL _atEnd;
    UIImpactFeedbackGenerator *_tap;
}

- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:NULL])) return nil;
    self.delegate = self;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO;
    self.delaysTouchesEnded = NO;
    return self;
}

- (BOOL)canPrevent:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePrevented:(UIGestureRecognizer *)other { return NO; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

// The thumb's middle at the two ends of its travel, in the slider.
static void travelOf(UISlider *slider, CGFloat *lo, CGFloat *hi) {
    CGRect bounds = slider.bounds, track = [slider trackRectForBounds:bounds];
    *lo = CGRectGetMidX([slider thumbRectForBounds:bounds trackRect:track value:slider.minimumValue]);
    *hi = CGRectGetMidX([slider thumbRectForBounds:bounds trackRect:track value:slider.maximumValue]);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UISlider *slider = (UISlider *)self.view;
    UIView *host = self.thumb.superview;
    if (_touch || !slider.enabled || !host) return;
    // UIKit tracks a touch that lands on the thumb (with some room round it); one elsewhere moves nothing.
    UITouch *touch = touches.anyObject;
    CGRect thumb = [slider convertRect:host.bounds fromView:host];
    if (!CGRectContainsPoint(CGRectInset(thumb, -20, -20), [touch locationInView:slider])) return;
    _touch = touch;
    _atEnd = NO;
    if (!_tap) _tap = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [_tap prepare];
    [self.thumb setLifted:YES];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UISlider *slider = (UISlider *)self.view;
    if (!_touch || ![touches containsObject:_touch]) return;
    CGFloat x = [_touch locationInView:slider].x, lo, hi;
    travelOf(slider, &lo, &hi);
    CGFloat over = x < lo ? x - lo : x > hi ? x - hi : 0;
    BOOL atEnd = over != 0;
    if (atEnd && !_atEnd) {
        [_tap impactOccurred];
        [_tap prepare];
    }
    _atEnd = atEnd;
    CGFloat pull = over * kPullShare;
    [self.thumb setPull:MAX(-kMaxPull, MIN(kMaxPull, pull))];
}

- (void)finish {
    if (!_touch) return;
    _touch = nil;
    _atEnd = NO;
    [self.thumb setPull:0];
    [self.thumb setLifted:NO];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self finish];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self finish];
}

- (void)reset { [self finish]; }

@end

#pragma mark - the one entry

static UIImage *clearImage(CGSize size) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
}

// The view UIKit draws the thumb with: the image view in the slider that shows our clear image.
static UIImageView *thumbViewOf(UISlider *slider, UIImage *image) {
    __block UIImageView *found = nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:slider];
    while (queue.count && !found) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image == image) found = (UIImageView *)view;
        [queue addObjectsFromArray:view.subviews];
    }
    return found;
}

void SGGlassThumbAttach(UISlider *slider, CGSize size) {
    if (!slider || !SGUseLegacyGlass() || size.width < 1 || size.height < 1) return;
    UIImage *image = objc_getAssociatedObject(slider, &kImageKey);
    NSValue *was = objc_getAssociatedObject(slider, &kSizeKey);
    if (!image || !CGSizeEqualToSize(was.CGSizeValue, size)) {
        image = clearImage(size);
        objc_setAssociatedObject(slider, &kImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, &kSizeKey, [NSValue valueWithCGSize:size], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The owner may set its own thumb again (Spotify as the track changes, the volume view as the route does).
    if ([slider thumbImageForState:UIControlStateNormal] != image) {
        [slider setThumbImage:image forState:UIControlStateNormal];
        [slider setThumbImage:image forState:UIControlStateHighlighted];
        [slider layoutIfNeeded];
    }
    UIImageView *host = thumbViewOf(slider, image);
    if (!host) return;
    if (host.clipsToBounds) host.clipsToBounds = NO;
    SGGlassThumbView *thumb = objc_getAssociatedObject(slider, &kThumbKey);
    if (!thumb) {
        thumb = [SGGlassThumbView new];
        objc_setAssociatedObject(slider, &kThumbKey, thumb, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (thumb.superview != host) [host addSubview:thumb];
    // By bounds and center: the swell is a transform.
    if (!CGSizeEqualToSize(thumb.bounds.size, size)) thumb.bounds = (CGRect){CGPointZero, size};
    CGPoint middle = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
    if (!CGPointEqualToPoint(thumb.center, middle)) thumb.center = middle;
    SGGlassThumbWatch *watch = objc_getAssociatedObject(slider, &kWatchKey);
    if (!watch) {
        watch = [SGGlassThumbWatch new];
        objc_setAssociatedObject(slider, &kWatchKey, watch, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [slider addGestureRecognizer:watch];
    }
    watch.thumb = thumb;
}

#pragma mark - a switch

// iOS 26's switch, as adaptive_liquid_glass measured it from SwiftUI on iOS 26.4 (github.com/AymanOmara/
// adaptive_liquid_glass, MIT: lib/src/controls/control_metrics.dart, glass_colors.dart): a 63 x 28 track, a flat white
// 37 x 24 capsule 2 pt in from its ends, which grows into a clear glass lens 1.35 times across and 1.55 times down while
// a finger holds it, on a spring of response 0.381 and damping 0.752, and moves to a new value on one of 0.3 and 0.78.
// The track is #464649 while off in the dark and the switch's on tint while on, blended as the thumb crosses.
//
// UIKit's switch stays the control: its value, its touches and its accessibility are its own, and only what it draws is
// replaced, by this view inside it, its own drawing kept at alpha 0. The track is wider than UIKit's 51 pt, so it lines
// up with the switch's trailing edge and reaches past its leading one.
static const CGSize kSwitchTrack = {63, 28}, kSwitchThumb = {37, 24};
static const CGFloat kSwitchInset = 2, kSwitchLiftX = 1.35, kSwitchLiftY = 1.55;

@interface SGGlassSwitchView : UIView
@property (nonatomic, weak) UISwitch *toggle;
@property (nonatomic, readonly) SGGlassThumbView *thumb;
@property (nonatomic) CGFloat position;   // 0 off, 1 on
- (void)showPosition:(CGFloat)position animated:(BOOL)animated;
@end

@implementation SGGlassSwitchView {
    UIView *_track;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _track = [UIView new];
    _track.userInteractionEnabled = NO;
    _track.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_track];
    _thumb = [SGGlassThumbView new];
    _thumb.liftX = kSwitchLiftX;
    _thumb.liftY = kSwitchLiftY;
    [_thumb setFlat];
    [self addSubview:_thumb];
    return self;
}

static UIColor *trackColor(UISwitch *toggle, CGFloat position) {
    UIColor *off = [UIColor colorWithRed:0x46 / 255.0 green:0x46 / 255.0 blue:0x49 / 255.0 alpha:1];
    UIColor *on = toggle.onTintColor ?: UIColor.systemGreenColor;
    CGFloat r0, g0, b0, a0, r1, g1, b1, a1;
    if (![off getRed:&r0 green:&g0 blue:&b0 alpha:&a0] || ![on getRed:&r1 green:&g1 blue:&b1 alpha:&a1]) return position > 0.5 ? on : off;
    CGFloat t = MAX(0, MIN(1, position));
    return [UIColor colorWithRed:r0 + (r1 - r0) * t green:g0 + (g1 - g0) * t blue:b0 + (b1 - b0) * t alpha:a0 + (a1 - a0) * t];
}

// The thumb's centre for `position`, in this view.
- (CGPoint)thumbCenterAt:(CGFloat)position {
    CGFloat travel = kSwitchTrack.width - kSwitchThumb.width - 2 * kSwitchInset;
    CGFloat p = MAX(0, MIN(1, position));
    return CGPointMake(kSwitchInset + kSwitchThumb.width / 2 + travel * p, kSwitchTrack.height / 2);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _track.frame = (CGRect){CGPointZero, kSwitchTrack};
    _track.layer.cornerRadius = kSwitchTrack.height / 2;
    // By bounds and centre: the lift is a transform.
    if (!CGSizeEqualToSize(_thumb.bounds.size, kSwitchThumb)) _thumb.bounds = (CGRect){CGPointZero, kSwitchThumb};
}

- (void)showPosition:(CGFloat)position animated:(BOOL)animated {
    _position = position;
    [self layoutIfNeeded];
    void (^apply)(void) = ^{
        self.thumb.center = [self thumbCenterAt:position];
        self->_track.backgroundColor = trackColor(self.toggle, position);
    };
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:apply];
        return;
    }
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:apply completion:nil];
}

@end

// Watches the switch's touches without taking any, as the slider's watch does: the thumb lifts at the touch, follows a
// drag along the track, and at the touch's end the switch turns (a tap) or goes to the side the thumb was let go on (a
// drag). UIKit's own drawing, which took the switch's touches, is kept unseen and out of hit-testing (hideOwnDrawing),
// so the turn is made here; it is made only if UIKit has not turned the switch itself, so it never turns twice.
@interface SGGlassSwitchWatch : UIGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, weak) SGGlassSwitchView *face;
@end

@implementation SGGlassSwitchWatch {
    UITouch *_touch;
    CGFloat _startX, _startPosition;
    BOOL _dragging, _startOn;
    NSUInteger _press;
}

- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:NULL])) return nil;
    self.delegate = self;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO;
    self.delaysTouchesEnded = NO;
    return self;
}

- (BOOL)canPrevent:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePrevented:(UIGestureRecognizer *)other { return NO; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UISwitch *toggle = (UISwitch *)self.view;
    if (_touch || !toggle.enabled) return;
    _touch = touches.anyObject;
    _startX = [_touch locationInView:toggle].x;
    _startPosition = self.face.position;
    _startOn = toggle.isOn;
    _dragging = NO;
    _press++;
    [self.face.thumb setLifted:YES];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touch || ![touches containsObject:_touch]) return;
    CGFloat dx = [_touch locationInView:self.view].x - _startX;
    if (!_dragging && fabs(dx) < 3) return;
    _dragging = YES;
    CGFloat travel = kSwitchTrack.width - kSwitchThumb.width - 2 * kSwitchInset;
    [self.face showPosition:MAX(0, MIN(1, _startPosition + dx / travel)) animated:NO];
}

- (void)finishTurning:(BOOL)turn {
    if (!_touch) return;
    _touch = nil;
    NSUInteger press = _press;
    BOOL startOn = _startOn;
    BOOL want = !_dragging ? !startOn : self.face.position >= 0.5;
    // Whatever UIKit does with the touch, it does as the touch ends, after this: the switch is read a turn later.
    dispatch_async(dispatch_get_main_queue(), ^{
        UISwitch *toggle = (UISwitch *)self.view;
        if (press != self->_press || !toggle) return;
        if (turn && toggle.enabled && toggle.isOn == startOn && want != startOn) {
            [toggle setOn:want animated:YES];
            [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        }
        [self.face showPosition:toggle.isOn ? 1 : 0 animated:YES];
        [self.face.thumb setLifted:NO];
    });
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touch || ![touches containsObject:_touch]) return;
    // A tap that slid off the switch is no tap, as UIKit's own buttons have it.
    UIView *view = self.view;
    BOOL inside = _dragging || CGRectContainsPoint(CGRectInset(view.bounds, -16, -16), [_touch locationInView:view]);
    [self finishTurning:inside];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self finishTurning:NO];
}

- (void)reset { [self finishTurning:NO]; }

@end

static char kSwitchFaceKey;

// UIKit's own drawing of the switch, kept unseen: everything in it but the face. It took the switch's touches, but a
// view at alpha 0 is not hit-tested (and alpha is its layer's opacity, so hiding it by the layer changed nothing: the
// switch still never turned, device, 2026-10-23). It is taken out of hit-testing outright, so the touches land on the
// switch, where SGGlassSwitchWatch turns it.
static void hideOwnDrawing(UISwitch *toggle, UIView *face) {
    for (UIView *sub in toggle.subviews) {
        if (sub == face) continue;
        if (sub.alpha > 0) sub.alpha = 0;
        if (sub.userInteractionEnabled) sub.userInteractionEnabled = NO;
    }
}

static void placeFace(UISwitch *toggle, SGGlassSwitchView *face) {
    CGSize size = toggle.bounds.size;
    CGRect frame = CGRectMake(size.width - kSwitchTrack.width, round((size.height - kSwitchTrack.height) / 2),
                              kSwitchTrack.width, kSwitchTrack.height);
    if (!CGRectEqualToRect(face.frame, frame)) face.frame = frame;
    CGFloat alpha = toggle.enabled ? 1 : 0.5;
    if (face.alpha != alpha) face.alpha = alpha;
}

void SGGlassSwitchAttach(UISwitch *toggle) {
    if (!toggle || !SGUseLegacyGlass() || objc_getAssociatedObject(toggle, &kSwitchFaceKey)) return;
    SGGlassSwitchView *face = [SGGlassSwitchView new];
    face.toggle = toggle;
    objc_setAssociatedObject(toggle, &kSwitchFaceKey, face, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    toggle.clipsToBounds = NO;
    [toggle addSubview:face];
    placeFace(toggle, face);
    hideOwnDrawing(toggle, face);
    [face showPosition:toggle.isOn ? 1 : 0 animated:NO];
    SGGlassSwitchWatch *watch = [SGGlassSwitchWatch new];
    watch.face = face;
    [toggle addGestureRecognizer:watch];
}

void SGGlassSwitchSync(UISwitch *toggle, BOOL animated) {
    SGGlassSwitchView *face = toggle ? objc_getAssociatedObject(toggle, &kSwitchFaceKey) : nil;
    if (!face) return;
    [toggle bringSubviewToFront:face];
    placeFace(toggle, face);
    hideOwnDrawing(toggle, face);
    CGFloat position = toggle.isOn ? 1 : 0;
    if (face.position != position) [face showPosition:position animated:animated && face.window];
}
