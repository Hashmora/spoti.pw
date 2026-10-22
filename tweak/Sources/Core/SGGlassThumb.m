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
- (void)setLifted:(BOOL)lifted;
- (void)setPull:(CGFloat)pull;
@end

@implementation SGGlassThumbView {
    UIView *_pill;
    UIView *_pane;
    BOOL _lifted;
    CGFloat _pull;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _pane = SGGlassFor(self, &kPaneKey);
    _pane.alpha = 0;
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

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat radius = bounds.size.height / 2;
    _pill.frame = bounds;
    _pill.layer.cornerRadius = radius;
    _pill.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius].CGPath;
    if (!CGRectEqualToRect(_pane.frame, bounds)) _pane.frame = bounds;
    SGShapeGlass(_pane, radius, YES);
}

// The swell and the pull are one transform, so either can change without the other jumping.
- (CGAffineTransform)pose {
    CGFloat lift = _lifted ? 1 : 0;
    CGFloat stretch = fabs(_pull) / kMaxPull * kPullStretch;
    CGFloat sx = (1 + (kLiftWidth - 1) * lift) * (1 + stretch), sy = (1 + (kLiftHeight - 1) * lift) * (1 - stretch * 0.5);
    return CGAffineTransformScale(CGAffineTransformMakeTranslation(_pull, 0), sx, sy);
}

- (void)setLifted:(BOOL)lifted {
    if (_lifted == lifted) return;
    _lifted = lifted;
    BOOL still = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:still ? 0.2 : (lifted ? 0.35 : 0.45) delay:0 usingSpringWithDamping:still ? 1 : (lifted ? 0.7 : 0.8)
          initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (!still) self.transform = [self pose];
        self->_pill.alpha = lifted ? 0 : 1;
        self->_pane.alpha = lifted ? 1 : 0;
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
