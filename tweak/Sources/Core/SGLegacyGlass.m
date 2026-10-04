#import "SGLegacyGlass.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - availability

BOOL SGLegacyGlassAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (@available(iOS 26.0, *)) return;
        Class mesh = NSClassFromString(@"CAMutableMeshTransform");
        SEL meshSel = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
        available = NSClassFromString(@"CABackdropLayer") && [mesh respondsToSelector:meshSel];
    });
    return available;
}

#pragma mark - backdrop layer and its filters

static id SGMakeFilter(NSString *type) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL sel = NSSelectorFromString(@"filterWithType:");
    if (![filterClass respondsToSelector:sel]) return nil;
    return ((id (*)(Class, SEL, NSString *))objc_msgSend)(filterClass, sel, type);
}

// Saturation and contrast boost under the blur, as Telegram does, so the backdrop is not just a flat blur.
static id SGSaturationFilter(void) {
    static const float matrix[20] = {
        2.6705f, -1.1087999f, -0.1117f, 0.0f, 0.049999997f,
        -0.3295f, 1.8914f, -0.111899994f, 0.0f, 0.049999997f,
        -0.3297f, -1.1084f, 2.8881f, 0.0f, 0.049999997f,
        0.0f, 0.0f, 0.0f, 1.0f, 0.0f,
    };
    id filter = SGMakeFilter(@"colorMatrix");
    [filter setValue:[NSValue valueWithBytes:matrix objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];
    [filter setValue:@YES forKey:@"inputBackdropAware"];
    return filter;
}

static id SGBlurFilter(CGFloat radius) {
    id filter = SGMakeFilter(@"gaussianBlur");
    [filter setValue:@(radius) forKey:@"inputRadius"];
    return filter;
}

// Layer actions off, so the backdrop follows its view's resizes without implicit animation.
@interface SGNoActionsDelegate : NSObject <CALayerDelegate>
@end
@implementation SGNoActionsDelegate
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event { return (id<CAAction>)[NSNull null]; }
@end

static NSArray *SGBackdropFilters(CGFloat blur) {
    NSMutableArray *filters = [NSMutableArray array];
    for (id filter in @[SGSaturationFilter() ?: NSNull.null, SGBlurFilter(blur) ?: NSNull.null]) {
        if (filter != NSNull.null) [filters addObject:filter];
    }
    return filters;
}

static CALayer *SGMakeBackdropLayer(id<CALayerDelegate> delegate) {
    CALayer *layer = [[NSClassFromString(@"CABackdropLayer") alloc] init];
    if (!layer) return nil;
    SEL setScale = NSSelectorFromString(@"setScale:");
    if ([layer respondsToSelector:setScale]) ((void (*)(id, SEL, double))objc_msgSend)(layer, setScale, 1.0);
    layer.rasterizationScale = 1.0;
    layer.delegate = delegate;
    NSArray *filters = SGBackdropFilters(2.0);
    if (filters.count) layer.filters = filters;
    return layer;
}

#pragma mark - mesh transform (CAMutableMeshTransform)

typedef struct { CGFloat x, y, z; } SGMeshPoint3D;
typedef struct { CGPoint from; SGMeshPoint3D to; } SGMeshVertex;
typedef struct { uint32_t indices[4]; float w[4]; } SGMeshFace;

// The class method takes C arrays, which only NSInvocation can pass without a header for it.
static id SGMakeMeshTransform(SGMeshVertex *vertices, NSUInteger vertexCount, SGMeshFace *faces, NSUInteger faceCount) {
    Class cls = NSClassFromString(@"CAMutableMeshTransform");
    SEL sel = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
    NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.selector = sel;
    NSString *depthNormalization = @"none";
    [inv setArgument:&vertexCount atIndex:2];
    [inv setArgument:&vertices atIndex:3];
    [inv setArgument:&faceCount atIndex:4];
    [inv setArgument:&faces atIndex:5];
    [inv setArgument:&depthNormalization atIndex:6];
    [inv invokeWithTarget:cls];
    __unsafe_unretained id raw = nil;
    [inv getReturnValue:&raw];
    id transform = raw;
    if ([transform respondsToSelector:NSSelectorFromString(@"setSubdivisionSteps:")]) [transform setValue:@0 forKey:@"subdivisionSteps"];
    return transform;
}

#pragma mark - displacement field (ported from Telegram's GenerateMesh.swift)

// Telegram's fixed easing curve for the displacement towards the edge.
static const CGFloat kBezierX1 = 0.816137566137566, kBezierY1 = 0.20502645502645533;
static const CGFloat kBezierX2 = 0.5806878306878306, kBezierY2 = 0.873015873015873;

static CGFloat SGBezier(CGFloat t, CGFloat a1, CGFloat a2) {
    return (((1.0 - 3.0 * a2 + 3.0 * a1) * t + (3.0 * a2 - 6.0 * a1)) * t + 3.0 * a1) * t;
}

static CGFloat SGBezierSlope(CGFloat t, CGFloat a1, CGFloat a2) {
    return 3.0 * (1.0 - 3.0 * a2 + 3.0 * a1) * t * t + 2.0 * (3.0 * a2 - 6.0 * a1) * t + 3.0 * a1;
}

// The curve's y at x: Newton's method for the t that gives x, then y at that t.
static CGFloat SGEase(CGFloat x) {
    CGFloat t = x;
    for (int i = 0; i < 4; i++) {
        CGFloat slope = SGBezierSlope(t, kBezierX1, kBezierX2);
        if (slope == 0.0) break;
        t -= (SGBezier(t, kBezierX1, kBezierX2) - x) / slope;
    }
    CGFloat y = SGBezier(t, kBezierY1, kBezierY2);
    return y >= 0.997 ? 1.0 : y;
}

// Signed distance from (x, y) to a width x height rounded rect at the origin (negative inside), and the
// outward unit normal there.
static CGFloat SGRoundedRectSDF(CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat radius, CGFloat *nx, CGFloat *ny) {
    CGFloat px = x - width / 2, py = y - height / 2;
    CGFloat qx = fabs(px) - width / 2 + radius, qy = fabs(py) - height / 2 + radius;
    CGFloat gx = 0, gy = 0;
    if (qx > 0 && qy > 0) {
        CGFloat d = hypot(qx, qy);
        if (d > 0) { gx = qx / d; gy = qy / d; }
    } else if (qx > qy) {
        gx = 1;
    } else {
        gy = 1;
    }
    *nx = px < 0 ? -gx : gx;
    *ny = py < 0 ? -gy : gy;
    return hypot(MAX(qx, 0), MAX(qy, 0)) + MIN(MAX(qx, qy), 0) - radius;
}

// What a vertex samples from, relative to where it sits: inwards, strongest at the edge, eased.
static void SGDisplacement(CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat radius, CGFloat edgeDistance,
                           CGFloat *outDx, CGFloat *outDy, CGFloat *outSdf) {
    CGFloat nx, ny;
    CGFloat sdf = SGRoundedRectSDF(x, y, width, height, radius, &nx, &ny);
    CGFloat weight = MAX(0, MIN(1, 1.0 + sdf / edgeDistance));
    CGFloat dx = -nx * weight, dy = -ny * weight;
    CGFloat mag = hypot(dx, dy);
    if (mag > 0) {
        CGFloat scale = SGEase(mag) / mag;
        dx *= scale; dy *= scale;
    }
    *outDx = dx; *outDy = dy; *outSdf = sdf;
}

#pragma mark - mesh template

// The mesh is built once per corner radius at a reference size, as vertices of a size-independent
// (base + scale * size) position plus their unitless displacement. Fitting it to a real size is then one
// affine remap per vertex, with no distance-field work per layout pass.
typedef struct { CGFloat radius, refW, refH, edgeDistance, outerEdgeDistance; } SGMeshSpec;
typedef struct { CGFloat baseX, scaleX, baseY, scaleY, dispX, dispY, depth; } SGTemplateVertex;

static const NSInteger kCornerResolution = 12;
static const CGFloat kOuterEdgeDistance = 2.0;   // width of the strip at the rim that is refracted harder
static const CGFloat kDisplacementPoints = 20.0; // how far, at most, a vertex samples from its own position
static const CGFloat kInsetPoints = -1.0;        // the mesh reaches this far past the view, so its rim is never bare

@interface SGMeshTemplate : NSObject
@property (nonatomic, readonly) NSMutableData *vertices;   // SGTemplateVertex[]
@property (nonatomic, readonly) NSMutableData *faces;      // SGMeshFace[]
@end
@implementation SGMeshTemplate
- (instancetype)init {
    if ((self = [super init])) { _vertices = [NSMutableData data]; _faces = [NSMutableData data]; }
    return self;
}
@end

static uint32_t SGAddVertex(SGMeshTemplate *t, SGMeshSpec spec, CGFloat baseX, CGFloat scaleX, CGFloat baseY, CGFloat scaleY, CGFloat depth) {
    CGFloat dx, dy, sdf;
    SGDisplacement(baseX + scaleX * spec.refW, baseY + scaleY * spec.refH, spec.refW, spec.refH, spec.radius, spec.edgeDistance, &dx, &dy, &sdf);
    // A smoothstep boost within the outer strip.
    CGFloat boost = 1.0;
    if (spec.outerEdgeDistance > 0) {
        CGFloat s = MAX(0.0, MIN(1.0, (spec.outerEdgeDistance + sdf) / spec.outerEdgeDistance));
        boost += s * s * (3 - 2 * s) * 0.5;
    }
    SGTemplateVertex v = {baseX, scaleX, baseY, scaleY, dx * boost, dy * boost, depth};
    [t.vertices appendBytes:&v length:sizeof(v)];
    return (uint32_t)(t.vertices.length / sizeof(v)) - 1;
}

static void SGAddQuad(SGMeshTemplate *t, uint32_t i0, uint32_t i1, uint32_t i2, uint32_t i3) {
    SGMeshFace face = {{i0, i1, i2, i3}, {0, 0, 0, 0}};
    [t.faces appendBytes:&face length:sizeof(face)];
}

// A grid over the given (base, scale) axes, quadded up. `axis` entries are CGPoint(base, scale).
static void SGAddGrid(SGMeshTemplate *t, SGMeshSpec spec, NSArray<NSValue *> *xAxis, NSArray<NSValue *> *yAxis) {
    NSUInteger cols = xAxis.count, rows = yAxis.count;
    uint32_t *grid = malloc(sizeof(uint32_t) * rows * cols);
    for (NSUInteger r = 0; r < rows; r++) {
        for (NSUInteger c = 0; c < cols; c++) {
            CGPoint x = xAxis[c].CGPointValue, y = yAxis[r].CGPointValue;
            grid[r * cols + c] = SGAddVertex(t, spec, x.x, x.y, y.x, y.y, 0);
        }
    }
    for (NSUInteger r = 0; r + 1 < rows; r++) {
        for (NSUInteger c = 0; c + 1 < cols; c++) {
            SGAddQuad(t, grid[r * cols + c], grid[r * cols + c + 1], grid[(r + 1) * cols + c + 1], grid[(r + 1) * cols + c]);
        }
    }
    free(grid);
}

// A quarter circle around (centerBase + centerScale * size): rings from the rim inwards, fanned into the
// centre. `rings` are radii as fractions of the corner radius, outermost first, `angles` fractions of the
// arc from startAngle to endAngle.
static void SGAddCorner(SGMeshTemplate *t, SGMeshSpec spec, CGPoint centerX, CGPoint centerY, CGFloat startAngle, CGFloat endAngle,
                        NSArray<NSNumber *> *rings, NSArray<NSNumber *> *angles) {
    NSUInteger ringCount = rings.count, angleCount = angles.count;
    uint32_t *grid = malloc(sizeof(uint32_t) * ringCount * angleCount);
    for (NSUInteger r = 0; r < ringCount; r++) {
        CGFloat radius = spec.radius * rings[r].doubleValue;
        for (NSUInteger a = 0; a < angleCount; a++) {
            CGFloat angle = startAngle + (endAngle - startAngle) * angles[a].doubleValue;
            grid[r * angleCount + a] = SGAddVertex(t, spec, centerX.x + radius * cos(angle), centerX.y, centerY.x + radius * sin(angle), centerY.y, 0);
        }
    }
    for (NSUInteger r = 0; r + 1 < ringCount; r++) {
        for (NSUInteger a = 0; a + 1 < angleCount; a++) {
            SGAddQuad(t, grid[r * angleCount + a], grid[r * angleCount + a + 1], grid[(r + 1) * angleCount + a + 1], grid[(r + 1) * angleCount + a]);
        }
    }

    // The innermost ring is fanned into the centre, two segments to a quad.
    const uint32_t *inner = grid + (ringCount - 1) * angleCount;
    NSInteger segments = (NSInteger)angleCount - 1;
    if (segments >= 2) {
        uint32_t center = SGAddVertex(t, spec, centerX.x, centerX.y, centerY.x, centerY.y, -0.02);
        NSInteger i = 0;
        for (; i + 2 <= segments; i += 2) SGAddQuad(t, center, inner[i], inner[i + 1], inner[i + 2]);
        if (i < segments) SGAddQuad(t, center, inner[segments - 1], inner[segments], inner[segments]);
    }
    free(grid);
}

static NSValue *SGAxisPoint(CGFloat base, CGFloat scale) {
    return [NSValue valueWithCGPoint:CGPointMake(base, scale)];
}

static SGMeshTemplate *SGBuildTemplate(CGFloat radius) {
    SGMeshSpec spec = {radius, MAX(4 * radius, 100), MAX(4 * radius, 100), MIN(12.0, radius), kOuterEdgeDistance};
    SGMeshTemplate *t = [SGMeshTemplate new];
    CGFloat R = radius;

    NSInteger angularSteps = MAX(3, kCornerResolution);
    if (angularSteps % 2) angularSteps++;
    NSInteger radialSteps = MAX(2, kCornerResolution);
    NSInteger edgeSegments = MAX(2, kCornerResolution / 2 + 1);

    // Ring radii: evenly spaced up to (1 - rim strip), then the strip's edge, then the rim itself.
    NSMutableArray<NSNumber *> *depths = [NSMutableArray array];
    CGFloat innerMax = MAX(0, 1 - MAX(0, MIN(1, kOuterEdgeDistance / R)));
    NSInteger innerSegments = MAX(1, radialSteps - 1);
    for (NSInteger i = 0; i <= innerSegments; i++) [depths addObject:@(innerMax * i / (CGFloat)innerSegments)];
    if (fabs(depths.lastObject.doubleValue - innerMax) >= 1e-4) [depths addObject:@(innerMax)];
    if (fabs(depths.lastObject.doubleValue - 1.0) >= 1e-4) [depths addObject:@1.0];
    NSArray<NSNumber *> *outerToInner = depths.reverseObjectEnumerator.allObjects;
    NSMutableArray<NSNumber *> *rings = [NSMutableArray array];   // the same without the centre, which the fan covers
    for (NSNumber *d in outerToInner) if (d.doubleValue > 0) [rings addObject:d];

    NSMutableArray<NSNumber *> *angles = [NSMutableArray array];
    for (NSInteger i = 0; i <= angularSteps; i++) [angles addObject:@(i / (CGFloat)angularSteps)];

    // Axes of the straight parts: `span` runs from one corner's centre to the other's, `leading` and
    // `trailing` are the corner bands at each end, thickened towards the rim.
    NSMutableArray<NSValue *> *span = [NSMutableArray array], *leading = [NSMutableArray array], *trailing = [NSMutableArray array];
    for (NSInteger i = 0; i <= edgeSegments; i++) {
        CGFloat u = i / (CGFloat)edgeSegments;
        [span addObject:SGAxisPoint(R * (1 - 2 * u), u)];
    }
    for (NSNumber *d in outerToInner) [leading addObject:SGAxisPoint(R * (1 - d.doubleValue), 0)];
    for (NSNumber *d in depths) [trailing addObject:SGAxisPoint(-R * (1 - d.doubleValue), 1)];

    SGAddGrid(t, spec, span, leading);     // top band
    SGAddGrid(t, spec, span, trailing);    // bottom band
    SGAddGrid(t, spec, leading, span);     // left band
    SGAddGrid(t, spec, trailing, span);    // right band
    SGAddGrid(t, spec, span, span);        // middle

    CGPoint near = CGPointMake(R, 0), far = CGPointMake(-R, 1);   // (base, scale) of a corner centre on each axis
    SGAddCorner(t, spec, near, near, M_PI, 1.5 * M_PI, rings, angles);
    SGAddCorner(t, spec, far, near, 1.5 * M_PI, 2 * M_PI, rings, angles);
    SGAddCorner(t, spec, far, far, M_PI_2, 0, rings, angles);
    SGAddCorner(t, spec, near, far, M_PI, M_PI_2, rings, angles);
    return t;
}

// The mesh for `size`, from the cached template of its corner radius.
static id SGMakeGlassMesh(CGSize size, CGFloat radius) {
    radius = MIN(radius, MIN(size.width, size.height) / 2);
    if (radius <= 0 || size.width < 1 || size.height < 1) return nil;

    static NSCache<NSNumber *, SGMeshTemplate *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 24; });
    NSNumber *key = @(round(radius * 10));
    SGMeshTemplate *tmpl = [cache objectForKey:key];
    if (!tmpl) {
        tmpl = SGBuildTemplate(radius);
        [cache setObject:tmpl forKey:key];
    }

    CGFloat W = size.width, H = size.height;
    CGFloat insetU = kInsetPoints / W, insetV = kInsetPoints / H;
    CGFloat usableU = 1 - 2 * insetU, usableV = 1 - 2 * insetV;
    CGFloat dU = kDisplacementPoints / W, dV = kDisplacementPoints / H;

    NSUInteger vertexCount = tmpl.vertices.length / sizeof(SGTemplateVertex);
    const SGTemplateVertex *templates = tmpl.vertices.bytes;
    SGMeshVertex *vertices = malloc(sizeof(SGMeshVertex) * vertexCount);
    for (NSUInteger i = 0; i < vertexCount; i++) {
        SGTemplateVertex v = templates[i];
        CGFloat u = insetU + (v.baseX + v.scaleX * W) / W * usableU;
        CGFloat w = insetV + (v.baseY + v.scaleY * H) / H * usableV;
        CGPoint from = CGPointMake(MAX(0.0, MIN(1.0, u + v.dispX * dU)), MAX(0.0, MIN(1.0, w + v.dispY * dV)));
        vertices[i] = (SGMeshVertex){from, {u, w, v.depth}};
    }
    id transform = SGMakeMeshTransform(vertices, vertexCount, (SGMeshFace *)tmpl.faces.bytes, tmpl.faces.length / sizeof(SGMeshFace));
    free(vertices);
    return transform;
}

#pragma mark - SGLegacyGlassView

@implementation SGLegacyGlassView {
    CALayer *_backdropLayer;
    SGNoActionsDelegate *_backdropDelegate;
    CGSize _meshSize;
    CGFloat _meshRadius;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.layer.cornerCurve = kCACornerCurveCircular;
    self.clipsToBounds = YES;

    _blurRadius = 2.0;
    _backdropDelegate = [SGNoActionsDelegate new];
    _backdropLayer = SGMakeBackdropLayer(_backdropDelegate);
    if (_backdropLayer) [self.layer addSublayer:_backdropLayer];

    _contentView = [[UIView alloc] initWithFrame:self.bounds];
    _contentView.backgroundColor = UIColor.clearColor;
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_contentView];
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    if (_cornerRadius == cornerRadius) return;
    _cornerRadius = cornerRadius;
    [self setNeedsLayout];
}

- (void)setBlurRadius:(CGFloat)blurRadius {
    if (_blurRadius == blurRadius) return;
    _blurRadius = blurRadius;
    NSArray *filters = SGBackdropFilters(blurRadius);
    if (filters.count) _backdropLayer.filters = filters;
}

- (void)setCapsule:(BOOL)capsule {
    if (_capsule == capsule) return;
    _capsule = capsule;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat radius = _capsule ? MIN(size.width, size.height) / 2 : _cornerRadius;
    if (CGSizeEqualToSize(size, _meshSize) && radius == _meshRadius) return;
    _meshSize = size;
    _meshRadius = radius;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.cornerRadius = radius;
    _backdropLayer.frame = self.bounds;
    id mesh = SGMakeGlassMesh(size, radius);
    if (mesh) [_backdropLayer setValue:mesh forKey:@"meshTransform"];
    [CATransaction commit];
}

@end
