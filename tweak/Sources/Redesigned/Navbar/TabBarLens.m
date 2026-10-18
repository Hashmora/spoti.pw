#import "TabBarLens.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"

static char kLensPaneKey, kLensFilmKey;

// The held bubble is this much wider than the pill (and taller by 2 * heldOutset, so it stands out of the capsule's
// rim, as the system's does), and may be dragged this far past the first and the last tab.
static const CGFloat kLensGrow = 12, kLensOverscroll = 14;
// Past this speed of the bubble's middle (pt/s) it is stretched on top of what the two edges' lag gives.
static const CGFloat kLensStretchSpeed = 3200, kLensMaxSpeedStretch = 0.28;

typedef struct { CGFloat k, c; } SGRSpring;   // unit mass
typedef struct { CGFloat mass, k, c; } SGRMassSpring;

static SGRSpring spring(CGFloat stiffness, CGFloat ratio) {
    return (SGRSpring){stiffness, 2 * ratio * sqrt(stiffness)};
}

static void stepEdge(CGFloat *x, CGFloat *v, CGFloat target, SGRSpring s, CGFloat dt) {
    CGFloat a = -s.k * (*x - target) - s.c * (*v);
    *v += a * dt;
    *x += *v * dt;
}

// The lift is the press' own spring in SGGlassTouch.m: quick and firm going up, loose going down.
static const SGRMassSpring kLiftOn = {1.36, 568.0, 39.7};
static const SGRMassSpring kLiftOff = {2.0, 460.0, 21.8};

static CGFloat rubber(CGFloat x, CGFloat lo, CGFloat hi) {
    if (hi < lo) return x;
    if (x < lo) return lo - MIN(kLensOverscroll, (lo - x) * 0.3);
    if (x > hi) return hi + MIN(kLensOverscroll, (x - hi) * 0.3);
    return x;
}

// CADisplayLink keeps its target, so the lens is held weakly by this and can go away.
@class SGRLegacyLens;
@interface SGRLensLink : NSObject
@property (nonatomic, weak) SGRLegacyLens *lens;
@end

@interface SGRLegacyLens ()
- (void)tick:(CADisplayLink *)link;
@end

@implementation SGRLensLink
- (void)tick:(CADisplayLink *)link {
    SGRLegacyLens *lens = self.lens;
    if (lens) [lens tick:link]; else [link invalidate];
}
@end

typedef struct { CGFloat L, R, vL, vR, lift, vLift; } SGLensSample;
static const CGFloat kPlayStep = 1.0 / 120;

@implementation SGRLegacyLens {
    UIView *_rest;
    UIView *_pane;
    UIView *_film;
    CADisplayLink *_link;
    // The two edges: where they are, how fast they go and where they are going.
    CGFloat _L, _R, _vL, _vR, _tL, _tR;
    CGFloat _lift, _vLift, _liftTarget;
    CGFloat _minCenter, _maxCenter;
    BOOL _glassOn;
    // A bubble nobody holds is not run frame by frame on the main thread, which a tab loading under it would stall
    // (the glass froze for as long as the page took). Its whole run is worked out at once and handed to Core
    // Animation as keyframes: the same springs, played where the main thread cannot hold them up.
    NSData *_playback;            // SGLensSample[]
    CFTimeInterval _playStart;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _heldOutset = 6;
    _rest = [UIView new];
    _rest.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _rest.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_rest];
    _pane = SGGlassFor(self, &kLensPaneKey);
    _pane.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [UIView performWithoutAnimation:^{ SGRShowGlass(self->_pane, NO); }];
    _film = SGRGlassFilm(self, &kLensFilmKey, _pane, 0);
    _film.alpha = 0;
    // The bubble has to read against the bar it sits in, which is the same glass under the same film: its own film is
    // brighter and it has a rim, so held, it stands out of the capsule instead of melting into it.
    _film.backgroundColor = [UIColor colorWithWhite:1 alpha:0.30];
    _film.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _film.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
    return self;
}

- (void)dealloc {
    [_link invalidate];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat radius = bounds.size.height / 2;
    _rest.frame = bounds;
    _rest.layer.cornerRadius = radius;
    if (!CGRectEqualToRect(_pane.frame, bounds)) _pane.frame = bounds;
    SGShapeGlass(_pane, radius, YES);
    SGRGlassFilm(self, &kLensFilmKey, _pane, radius);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stop];
        [self dropPlayback];
        _touching = NO;
        _lift = _vLift = _liftTarget = 0;
        [self showGlass:NO animated:NO];
        [self snapToRest];
    }
}

#pragma mark - what the bar tells it

- (void)setRestFrame:(CGRect)frame animated:(BOOL)animated {
    BOOL first = CGRectIsEmpty(_restFrame);
    BOOL resized = !CGSizeEqualToSize(_restFrame.size, frame.size);
    _restFrame = frame;
    if (resized) {
        [UIView performWithoutAnimation:^{
            self.bounds = (CGRect){CGPointZero, frame.size};
            [self setNeedsLayout];
        }];
    }
    // A finger has the bubble; where it goes on release is read from the rest frame then.
    if (_touching && !resized) return;
    CGFloat left = CGRectGetMinX(frame), right = CGRectGetMaxX(frame);
    if (first || resized || !animated || SGRReduceMotion() || !self.window) {
        [self snapToRest];
        return;
    }
    [self takeOverPlayback];
    _tL = left;
    _tR = right;
    [self playToTargets];
}

- (void)beginTouchAtX:(CGFloat)x minCenter:(CGFloat)minCenter maxCenter:(CGFloat)maxCenter {
    // Reduce Motion: the pill stays a pill and moves with the selection, as it did.
    if (CGRectIsEmpty(_restFrame) || self.hidden || SGRReduceMotion()) return;
    [self takeOverPlayback];
    _touching = YES;
    _liftTarget = 1;
    _minCenter = minCenter;
    _maxCenter = maxCenter;
    [self showGlass:YES animated:YES];
    [self moveTouchToX:x];
}

- (void)moveTouchToX:(CGFloat)x {
    if (!_touching) return;
    CGFloat center = rubber(x, _minCenter, _maxCenter);
    CGFloat width = _restFrame.size.width + kLensGrow;
    _tL = center - width / 2;
    _tR = center + width / 2;
    [self start];
}

- (void)endTouch {
    if (!_touching) return;
    _touching = NO;
    _liftTarget = 0;
    _tL = CGRectGetMinX(_restFrame);
    _tR = CGRectGetMaxX(_restFrame);
    // The glass goes back to the pill while the bubble is still on its way to the tab.
    [self showGlass:NO animated:YES];
    [self playToTargets];
}

- (void)flush {
    if (_playback) [CATransaction flush];
}

#pragma mark - look

// The bubble's glass and the pill trade places by effect and by alpha, never by an alpha over the glass
// (SGRShowGlass).
- (void)showGlass:(BOOL)on animated:(BOOL)animated {
    if (_glassOn == on) return;
    _glassOn = on;
    void (^change)(void) = ^{
        SGRShowGlass(self->_pane, on);
        self->_film.alpha = on ? 1 : 0;
        self->_rest.alpha = on ? 0 : 1;
    };
    if (animated) SGRAnimate(on ? SGRMotionRespond : SGRMotionFade, change, nil);
    else [UIView performWithoutAnimation:change];
}

// Where the bubble is for the state it is in: the middle, and how wide and how tall it looks. Its size is fixed (the
// pill's); the look is a transform, so no frame of glass is laid out again while it moves.
- (void)getPose:(SGLensSample)st center:(CGPoint *)center sx:(CGFloat *)sx sy:(CGFloat *)sy {
    CGFloat baseWidth = MAX(1, self.bounds.size.width), baseHeight = MAX(1, self.bounds.size.height);
    CGFloat width = MAX(baseHeight * 0.8, st.R - st.L);
    CGFloat nominal = _restFrame.size.width + kLensGrow * st.lift;
    CGFloat lag = MAX(0, width / MAX(1, nominal) - 1);
    CGFloat speed = fabs(st.vL + st.vR) / 2;
    CGFloat extra = MIN(kLensMaxSpeedStretch, speed / kLensStretchSpeed) * st.lift;
    // Longer is thinner, so the bubble keeps its volume while it runs.
    CGFloat held = 1 + 2 * _heldOutset / baseHeight * st.lift;
    *sx = width * (1 + extra) / baseWidth;
    *sy = MAX(0.7, held / (1 + 0.55 * (lag + extra)));
    *center = CGPointMake((st.L + st.R) / 2, CGRectGetMidY(_restFrame));
}

- (SGLensSample)state {
    return (SGLensSample){_L, _R, _vL, _vR, _lift, _vLift};
}

- (void)applyPose {
    if (CGRectIsEmpty(_restFrame)) return;
    CGPoint center;
    CGFloat sx, sy;
    [self getPose:[self state] center:&center sx:&sx sy:&sy];
    [UIView performWithoutAnimation:^{
        self.center = center;
        self.transform = CGAffineTransformMakeScale(sx, sy);
    }];
}

- (void)snapToRest {
    [self stop];
    [self dropPlayback];
    if (CGRectIsEmpty(_restFrame)) return;
    _L = _tL = CGRectGetMinX(_restFrame);
    _R = _tR = CGRectGetMaxX(_restFrame);
    _vL = _vR = 0;
    if (!_touching) _lift = _vLift = _liftTarget = 0;
    [self applyPose];
}

#pragma mark - springs

- (void)start {
    if (_link || !self.window) {
        if (!self.window) [self snapToRest];
        return;
    }
    SGRLensLink *proxy = [SGRLensLink new];
    proxy.lens = self;
    _link = [CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    // A link capped at 60 Hz would pull the player's 120 Hz transitions down with it (AGENTS.md).
    _link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [_link invalidate];
    _link = nil;
}

// One step of the springs towards the targets. The edge in front of the move is the stiff one, the one behind it the
// loose one; standing still they are alike.
- (void)advance:(CGFloat)h {
    CGFloat dir = (_tL + _tR) / 2 - (_L + _R) / 2;
    BOOL moving = fabs(dir) > 0.75;
    SGRSpring front = spring(1800, 0.82), back = spring(700, 0.66), even = spring(1100, 0.74);
    SGRSpring forL = !moving ? even : (dir < 0 ? front : back);
    SGRSpring forR = !moving ? even : (dir > 0 ? front : back);
    SGRMassSpring lift = _liftTarget > 0.5 ? kLiftOn : kLiftOff;
    stepEdge(&_L, &_vL, _tL, forL, h);
    stepEdge(&_R, &_vR, _tR, forR, h);
    CGFloat a = (-lift.k * (_lift - _liftTarget) - lift.c * _vLift) / lift.mass;
    _vLift += a * h;
    _lift += _vLift * h;
}

- (BOOL)settled {
    return fabs(_L - _tL) < 0.1 && fabs(_R - _tR) < 0.1 && fabs(_vL) < 5 && fabs(_vR) < 5
        && fabs(_lift - _liftTarget) < 0.003 && fabs(_vLift) < 0.05;
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval dt = MIN(MAX(link.targetTimestamp - link.timestamp, 1.0 / 240), 1.0 / 30);
    int steps = dt > 1.0 / 90 ? 2 : 1;
    for (int i = 0; i < steps; i++) [self advance:dt / steps];
    [self applyPose];
    if ([self settled]) {
        _L = _tL;
        _R = _tR;
        _vL = _vR = _vLift = 0;
        _lift = _liftTarget;
        [self applyPose];
        [self stop];
    }
}

#pragma mark - playback

- (void)dropPlayback {
    if (!_playback) return;
    _playback = nil;
    [self.layer removeAnimationForKey:@"lens.x"];
    [self.layer removeAnimationForKey:@"lens.sx"];
    [self.layer removeAnimationForKey:@"lens.sy"];
}

// A finger down, or a new place to go, while a run is playing: the springs carry on from where the run is now.
- (void)takeOverPlayback {
    if (!_playback) return;
    NSUInteger count = _playback.length / sizeof(SGLensSample);
    NSUInteger index = MIN(count - 1, (NSUInteger)MAX(0, (CACurrentMediaTime() - _playStart) / kPlayStep));
    SGLensSample st = ((const SGLensSample *)_playback.bytes)[index];
    [self dropPlayback];
    _L = st.L; _R = st.R; _vL = st.vL; _vR = st.vR; _lift = st.lift; _vLift = st.vLift;
    [self applyPose];
}

// Runs the springs from where they are to their targets without a display link, and plays the run on the layer.
- (void)playToTargets {
    [self stop];
    if (CGRectIsEmpty(_restFrame)) return;
    if (!self.window) {
        [self snapToRest];
        return;
    }
    NSMutableData *samples = [NSMutableData data];
    SGLensSample first = [self state];
    [samples appendBytes:&first length:sizeof(first)];
    // Settles well inside a second; the bound is for a spring that never would.
    for (int i = 0; i < 180 && ![self settled]; i++) {
        [self advance:kPlayStep];
        SGLensSample st = [self state];
        [samples appendBytes:&st length:sizeof(st)];
    }
    _L = _tL;
    _R = _tR;
    _vL = _vR = _vLift = 0;
    _lift = _liftTarget;
    SGLensSample last = [self state];
    [samples appendBytes:&last length:sizeof(last)];

    NSUInteger count = samples.length / sizeof(SGLensSample);
    const SGLensSample *all = samples.bytes;
    NSMutableArray<NSNumber *> *xs = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *sxs = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber *> *sys = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        CGPoint center;
        CGFloat sx, sy;
        [self getPose:all[i] center:&center sx:&sx sy:&sy];
        [xs addObject:@(center.x)];
        [sxs addObject:@(sx)];
        [sys addObject:@(sy)];
    }
    [self dropPlayback];
    // The model goes to where the run ends, so nothing jumps when the animations are done.
    [self applyPose];
    CFTimeInterval duration = (count - 1) * kPlayStep;
    void (^add)(NSString *, NSString *, NSArray *) = ^(NSString *key, NSString *path, NSArray *values) {
        CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:path];
        a.values = values;
        a.duration = duration;
        a.calculationMode = kCAAnimationLinear;
        [self.layer addAnimation:a forKey:key];
    };
    add(@"lens.x", @"position.x", xs);
    add(@"lens.sx", @"transform.scale.x", sxs);
    add(@"lens.sy", @"transform.scale.y", sys);
    _playback = samples;
    _playStart = CACurrentMediaTime();
}

@end
