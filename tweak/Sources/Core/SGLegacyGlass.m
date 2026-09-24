#import "SGLegacyGlass.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - availability

BOOL SGLegacyGlassAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (@available(iOS 26.0, *)) { available = NO; return; }
        Class backdrop = NSClassFromString(@"CABackdropLayer");
        Class mesh = NSClassFromString(@"CAMutableMeshTransform");
        SEL meshSel = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
        available = backdrop != nil && mesh != nil && [mesh respondsToSelector:meshSel];
    });
    return available;
}

#pragma mark - private CAFilter helpers

static CALayer *SGFilterBlur(CGFloat radius) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL sel = NSSelectorFromString(@"filterWithType:");
    if (!filterClass || ![filterClass respondsToSelector:sel]) return nil;
    id (*make)(id, SEL, NSString *) = (id (*)(id, SEL, NSString *))objc_msgSend;
    id filter = make(filterClass, sel, @"gaussianBlur");
    if (!filter) return nil;
    [filter setValue:@(radius) forKey:@"inputRadius"];
    return filter;
}

static CALayer *SGFilterColorMatrix(void) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL sel = NSSelectorFromString(@"filterWithType:");
    if (!filterClass || ![filterClass respondsToSelector:sel]) return nil;
    id (*make)(id, SEL, NSString *) = (id (*)(id, SEL, NSString *))objc_msgSend;
    id filter = make(filterClass, sel, @"colorMatrix");
    if (!filter) return nil;
    // Saturation + contrast boost, matching what Telegram puts under its normal (non-.clear) glass so
    // the backdrop doesn't just look like a flat blur.
    float matrix[20] = {
        2.6705f, -1.1087999f, -0.1117f, 0.0f, 0.049999997f,
        -0.3295f, 1.8914f, -0.111899994f, 0.0f, 0.049999997f,
        -0.3297f, -1.1084f, 2.8881f, 0.0f, 0.049999997f,
        0.0f, 0.0f, 0.0f, 1.0f, 0.0f,
    };
    NSValue *value = [NSValue valueWithBytes:matrix objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
    [filter setValue:value forKey:@"inputColorMatrix"];
    [filter setValue:@YES forKey:@"inputBackdropAware"];
    return filter;
}

#pragma mark - backdrop layer

static CALayer *SGMakeBackdropLayer(void) {
    Class cls = NSClassFromString(@"CABackdropLayer");
    if (!cls) return nil;
    CALayer *layer = [[cls alloc] init];
    SEL setScale = NSSelectorFromString(@"setScale:");
    if ([layer respondsToSelector:setScale]) {
        void (*call)(id, SEL, double) = (void (*)(id, SEL, double))objc_msgSend;
        call(layer, setScale, 1.0);
    }
    layer.rasterizationScale = 1.0;
    return layer;
}

@interface SGBackdropNullActionDelegate : NSObject <CALayerDelegate>
@end
@implementation SGBackdropNullActionDelegate
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event { return (id<CAAction>)[NSNull null]; }
@end

#pragma mark - mesh transform (CAMutableMeshTransform), built via NSInvocation

typedef struct { CGFloat x, y, z; } SGMeshPoint3D;
typedef struct { CGPoint from; SGMeshPoint3D to; } SGMeshVertex;
typedef struct { uint32_t indices[4]; float w[4]; } SGMeshFace;

static id SGMakeMeshTransform(SGMeshVertex *vertices, NSUInteger vertexCount, SGMeshFace *faces, NSUInteger faceCount) {
    Class cls = NSClassFromString(@"CAMutableMeshTransform");
    SEL sel = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
    if (!cls || ![cls respondsToSelector:sel]) return nil;
    NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.selector = sel;
    NSUInteger vc = vertexCount, fc = faceCount;
    NSString *depthNormalization = @"none";
    [inv setArgument:&vc atIndex:2];
    [inv setArgument:&vertices atIndex:3];
    [inv setArgument:&fc atIndex:4];
    [inv setArgument:&faces atIndex:5];
    [inv setArgument:&depthNormalization atIndex:6];
    [inv invokeWithTarget:cls];
    __unsafe_unretained id raw = nil;
    [inv getReturnValue:&raw];
    id transform = raw;
    if (transform) {
        SEL stepsSel = NSSelectorFromString(@"setSubdivisionSteps:");
        if ([transform respondsToSelector:stepsSel]) {
            NSInteger steps = 0;
            NSMethodSignature *ssig = [transform methodSignatureForSelector:stepsSel];
            NSInvocation *sinv = [NSInvocation invocationWithMethodSignature:ssig];
            sinv.selector = stepsSel;
            [sinv setArgument:&steps atIndex:2];
            [sinv invokeWithTarget:transform];
        }
    }
    return transform;
}

#pragma mark - mesh geometry (ported from Telegram's GenerateMesh.swift, template/cached path)

// Cubic-bezier easing, De Casteljau-free Newton solve for t(x), same as Telegram's calcBezier/getTForX.
static CGFloat SGBezierA(CGFloat a1, CGFloat a2) { return 1.0 - 3.0 * a2 + 3.0 * a1; }
static CGFloat SGBezierB(CGFloat a1, CGFloat a2) { return 3.0 * a2 - 6.0 * a1; }
static CGFloat SGBezierC(CGFloat a1) { return 3.0 * a1; }
static CGFloat SGBezierCalc(CGFloat t, CGFloat a1, CGFloat a2) { return ((SGBezierA(a1, a2) * t + SGBezierB(a1, a2)) * t + SGBezierC(a1)) * t; }
static CGFloat SGBezierSlope(CGFloat t, CGFloat a1, CGFloat a2) { return 3.0 * SGBezierA(a1, a2) * t * t + 2.0 * SGBezierB(a1, a2) * t + SGBezierC(a1); }

static CGFloat SGBezierTForX(CGFloat x, CGFloat x1, CGFloat x2) {
    CGFloat t = x;
    for (int i = 0; i < 4; i++) {
        CGFloat slope = SGBezierSlope(t, x1, x2);
        if (slope == 0.0) return t;
        CGFloat currentX = SGBezierCalc(t, x1, x2) - x;
        t -= currentX / slope;
    }
    return t;
}

static CGFloat SGBezierPoint(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat x) {
    CGFloat value = SGBezierCalc(SGBezierTForX(x, x1, x2), y1, y2);
    return value >= 0.997 ? 1.0 : value;
}

typedef struct { CGFloat x1, y1, x2, y2; } SGDisplacementBezier;
// Telegram's fixed easing curve for the glass edge displacement.
static const SGDisplacementBezier kSGGlassBezier = {0.816137566137566, 0.20502645502645533, 0.5806878306878306, 0.873015873015873};

static CGFloat SGRoundedRectSDF(CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat cornerRadius) {
    CGFloat px = x - width / 2, py = y - height / 2;
    CGFloat bx = width / 2, by = height / 2;
    CGFloat qx = fabs(px) - bx + cornerRadius, qy = fabs(py) - by + cornerRadius;
    CGFloat outsideDist = hypot(MAX(qx, 0), MAX(qy, 0));
    CGFloat insideDist = MIN(MAX(qx, qy), 0);
    return outsideDist + insideDist - cornerRadius;
}

static void SGRoundedRectGradient(CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat cornerRadius, CGFloat *outNx, CGFloat *outNy) {
    CGFloat px = x - width / 2, py = y - height / 2;
    CGFloat bx = width / 2, by = height / 2;
    CGFloat qx = fabs(px) - bx + cornerRadius, qy = fabs(py) - by + cornerRadius;
    CGFloat nx = 0, ny = 0;
    if (qx > 0 && qy > 0) {
        CGFloat d = hypot(qx, qy);
        if (d > 0) { nx = qx / d; ny = qy / d; }
    } else if (qx > qy) {
        nx = 1; ny = 0;
    } else {
        nx = 0; ny = 1;
    }
    if (px < 0) nx = -nx;
    if (py < 0) ny = -ny;
    *outNx = nx; *outNy = ny;
}

static void SGComputeDisplacement(CGFloat x, CGFloat y, CGFloat width, CGFloat height, CGFloat cornerRadius,
                                   CGFloat edgeDistance, SGDisplacementBezier bezier,
                                   CGFloat *outDx, CGFloat *outDy, CGFloat *outSdf) {
    CGFloat sdf = SGRoundedRectSDF(x, y, width, height, cornerRadius);
    CGFloat nx, ny;
    SGRoundedRectGradient(x, y, width, height, cornerRadius, &nx, &ny);
    CGFloat inwardX = -nx, inwardY = -ny;
    CGFloat distFromEdge = -sdf;
    CGFloat weight = MAX(0, MIN(1, 1.0 - distFromEdge / edgeDistance));
    CGFloat dx = inwardX * weight, dy = inwardY * weight;
    CGFloat mag = hypot(dx, dy);
    if (mag > 0) {
        CGFloat newMag = SGBezierPoint(bezier.x1, bezier.y1, bezier.x2, bezier.y2, mag);
        CGFloat scale = newMag / mag;
        dx *= scale; dy *= scale;
    }
    *outDx = dx; *outDy = dy; *outSdf = sdf;
}

// A vertex in the reference-size template: a size-independent (base, scale) affine position, plus the
// unitless displacement computed once at template-build time. Instantiating at the real size is then
// just an affine remap, so the (expensive) SDF work happens once per corner radius, not once per frame.
typedef struct {
    CGFloat baseX, scaleX, baseY, scaleY;
    CGFloat dispX, dispY, depth;
} SGGlassVertexTemplate;

@interface SGGlassMeshTemplate : NSObject
@property (nonatomic) NSMutableData *vertices; // SGGlassVertexTemplate[]
@property (nonatomic) NSMutableData *faces;    // SGMeshFace[]
@end
@implementation SGGlassMeshTemplate
@end

static NSInteger SGAddVertexTemplate(SGGlassMeshTemplate *t, CGFloat baseX, CGFloat scaleX, CGFloat baseY, CGFloat scaleY,
                                      CGFloat refW, CGFloat refH, CGFloat cornerRadius, CGFloat edgeDistance,
                                      CGFloat outerEdgeDistance, CGFloat depth) {
    CGFloat worldX = baseX + scaleX * refW, worldY = baseY + scaleY * refH;
    CGFloat dx, dy, sdf;
    SGComputeDisplacement(worldX, worldY, refW, refH, cornerRadius, edgeDistance, kSGGlassBezier, &dx, &dy, &sdf);
    CGFloat distToEdge = MAX(0.0, -sdf);
    CGFloat edgeBand = MAX(0.0, outerEdgeDistance);
    CGFloat edgeBoost = 1.0;
    if (edgeBand > 0) {
        CGFloat tt = MAX(0.0, MIN(1.0, (edgeBand - distToEdge) / edgeBand));
        edgeBoost = 1.0 + tt * tt * (3 - 2 * tt) * 0.5;
    }
    SGGlassVertexTemplate v = {baseX, scaleX, baseY, scaleY, dx * edgeBoost, dy * edgeBoost, depth};
    [t.vertices appendBytes:&v length:sizeof(v)];
    return (t.vertices.length / sizeof(SGGlassVertexTemplate)) - 1;
}

static void SGAddQuadFace(SGGlassMeshTemplate *t, uint32_t i0, uint32_t i1, uint32_t i2, uint32_t i3) {
    SGMeshFace f = {{i0, i1, i2, i3}, {0, 0, 0, 0}};
    [t.faces appendBytes:&f length:sizeof(f)];
}

// Builds an evenly-spaced grid over the given (base, scale) coefficient axes and quads it up. Mirrors
// buildGridTemplate in GenerateMesh.swift.
static void SGBuildGridTemplate(SGGlassMeshTemplate *t, NSArray<NSValue *> *xCoeffs, NSArray<NSValue *> *yCoeffs,
                                 CGFloat refW, CGFloat refH, CGFloat cornerRadius, CGFloat edgeDistance, CGFloat outerEdgeDistance) {
    NSUInteger rows = yCoeffs.count, cols = xCoeffs.count;
    NSInteger *grid = malloc(sizeof(NSInteger) * rows * cols);
    for (NSUInteger r = 0; r < rows; r++) {
        CGPoint yc; [yCoeffs[r] getValue:&yc];
        for (NSUInteger c = 0; c < cols; c++) {
            CGPoint xc; [xCoeffs[c] getValue:&xc];
            grid[r * cols + c] = SGAddVertexTemplate(t, xc.x, xc.y, yc.x, yc.y, refW, refH, cornerRadius, edgeDistance, outerEdgeDistance, 0);
        }
    }
    for (NSUInteger r = 0; r + 1 < rows; r++) {
        for (NSUInteger c = 0; c + 1 < cols; c++) {
            SGAddQuadFace(t, (uint32_t)grid[r * cols + c], (uint32_t)grid[r * cols + c + 1],
                          (uint32_t)grid[(r + 1) * cols + c + 1], (uint32_t)grid[(r + 1) * cols + c]);
        }
    }
    free(grid);
}

static void SGBuildCornerTemplate(SGGlassMeshTemplate *t, CGFloat centerBaseX, CGFloat centerScaleX, CGFloat centerBaseY, CGFloat centerScaleY,
                                   CGFloat startAngle, CGFloat endAngle, NSArray<NSNumber *> *outerToInner, NSArray<NSNumber *> *angularFactors,
                                   CGFloat R, CGFloat refW, CGFloat refH, CGFloat cornerRadius, CGFloat edgeDistance, CGFloat outerEdgeDistance) {
    NSMutableArray<NSNumber *> *ringRadials = [NSMutableArray array];
    for (NSNumber *f in outerToInner) if (f.doubleValue > 0) [ringRadials addObject:f];
    if (ringRadials.count == 0) return;

    NSUInteger ringCount = ringRadials.count, angCount = angularFactors.count;
    NSInteger *grid = malloc(sizeof(NSInteger) * ringCount * angCount);
    for (NSUInteger ri = 0; ri < ringCount; ri++) {
        CGFloat r = R * ringRadials[ri].doubleValue;
        for (NSUInteger ai = 0; ai < angCount; ai++) {
            CGFloat angle = startAngle + (endAngle - startAngle) * angularFactors[ai].doubleValue;
            CGFloat offsetX = r * cos(angle), offsetY = r * sin(angle);
            grid[ri * angCount + ai] = SGAddVertexTemplate(t, centerBaseX + offsetX, centerScaleX, centerBaseY + offsetY, centerScaleY,
                                                            refW, refH, cornerRadius, edgeDistance, outerEdgeDistance, 0);
        }
    }
    for (NSUInteger ri = 0; ri + 1 < ringCount; ri++) {
        for (NSUInteger ai = 0; ai + 1 < angCount; ai++) {
            SGAddQuadFace(t, (uint32_t)grid[ri * angCount + ai], (uint32_t)grid[ri * angCount + ai + 1],
                          (uint32_t)grid[(ri + 1) * angCount + ai + 1], (uint32_t)grid[(ri + 1) * angCount + ai]);
        }
    }
    NSInteger *innermost = grid + (ringCount - 1) * angCount;
    NSInteger segments = (NSInteger)angCount - 1;
    if (segments >= 2) {
        NSInteger center = SGAddVertexTemplate(t, centerBaseX, centerScaleX, centerBaseY, centerScaleY,
                                                refW, refH, cornerRadius, edgeDistance, outerEdgeDistance, -0.02);
        NSInteger i = 0;
        while (i + 2 <= segments) {
            SGAddQuadFace(t, (uint32_t)center, (uint32_t)innermost[i], (uint32_t)innermost[i + 1], (uint32_t)innermost[i + 2]);
            i += 2;
        }
        if (i < segments) {
            SGAddQuadFace(t, (uint32_t)center, (uint32_t)innermost[segments - 1], (uint32_t)innermost[segments], (uint32_t)innermost[segments]);
        }
    }
    free(grid);
}

// Builds the reference-size template once per (cornerRadius, edgeDistance, cornerResolution,
// outerEdgeDistance) combination — same shape families as Telegram's generateGlassMeshTemplate.
static SGGlassMeshTemplate *SGBuildGlassMeshTemplate(CGFloat cornerRadius, CGFloat edgeDistance, NSInteger cornerResolution, CGFloat outerEdgeDistance) {
    SGGlassMeshTemplate *t = [SGGlassMeshTemplate new];
    t.vertices = [NSMutableData data];
    t.faces = [NSMutableData data];

    CGFloat R = cornerRadius;
    CGFloat refW = MAX(4 * R, 100), refH = MAX(4 * R, 100);

    NSInteger angularStepsBase = MAX(3, cornerResolution);
    NSInteger angularSteps = (angularStepsBase % 2 == 0) ? angularStepsBase : angularStepsBase + 1;
    NSInteger radialSteps = MAX(2, cornerResolution);
    NSInteger horizontalSegments = MAX(2, cornerResolution / 2 + 1);
    NSInteger verticalSegments = MAX(2, cornerResolution / 2 + 1);

    // depthFactorsWithOuterBand: evenly spaced inner rings up to (1 - band), then the outer strip edge, then 1.
    NSMutableArray<NSNumber *> *depthFactors = [NSMutableArray array];
    {
        CGFloat bandNorm = R > 0 ? MAX(0, MIN(1, outerEdgeDistance / R)) : 0;
        NSInteger innerSegments = MAX(1, radialSteps - 1);
        CGFloat innerMax = MAX(0, 1 - bandNorm);
        for (NSInteger i = 0; i <= innerSegments; i++) [depthFactors addObject:@(innerMax * i / (CGFloat)innerSegments)];
        CGFloat last = depthFactors.lastObject.doubleValue;
        if (fabs(last - innerMax) >= 1e-4) [depthFactors addObject:@(innerMax)];
        last = depthFactors.lastObject.doubleValue;
        if (fabs(last - 1.0) >= 1e-4) [depthFactors addObject:@1.0];
    }
    NSArray<NSNumber *> *outerToInner = [[depthFactors reverseObjectEnumerator] allObjects];
    NSMutableArray<NSNumber *> *angularFactors = [NSMutableArray array];
    for (NSInteger i = 0; i <= angularSteps; i++) [angularFactors addObject:@(i / (CGFloat)angularSteps)];

    NSMutableArray<NSValue *> *topXCoeffs = [NSMutableArray array];
    for (NSInteger i = 0; i <= horizontalSegments; i++) {
        CGFloat tt = i / (CGFloat)horizontalSegments;
        [topXCoeffs addObject:[NSValue valueWithCGPoint:CGPointMake(R * (1 - 2 * tt), tt)]];
    }
    NSMutableArray<NSValue *> *sideYCoeffs = [NSMutableArray array];
    for (NSInteger j = 0; j <= verticalSegments; j++) {
        CGFloat tt = j / (CGFloat)verticalSegments;
        [sideYCoeffs addObject:[NSValue valueWithCGPoint:CGPointMake(R * (1 - 2 * tt), tt)]];
    }
    NSMutableArray<NSValue *> *topYCoeffs = [NSMutableArray array];
    for (NSNumber *f in outerToInner) [topYCoeffs addObject:[NSValue valueWithCGPoint:CGPointMake(R * (1 - f.doubleValue), 0)]];
    NSMutableArray<NSValue *> *bottomYCoeffs = [NSMutableArray array];
    for (NSNumber *f in depthFactors) [bottomYCoeffs addObject:[NSValue valueWithCGPoint:CGPointMake(-R * (1 - f.doubleValue), 1)]];
    NSMutableArray<NSValue *> *leftXCoeffs = [NSMutableArray array];
    for (NSNumber *f in outerToInner) [leftXCoeffs addObject:[NSValue valueWithCGPoint:CGPointMake(R * (1 - f.doubleValue), 0)]];
    NSMutableArray<NSValue *> *rightXCoeffs = [NSMutableArray array];
    for (NSNumber *f in depthFactors) [rightXCoeffs addObject:[NSValue valueWithCGPoint:CGPointMake(-R * (1 - f.doubleValue), 1)]];

    SGBuildGridTemplate(t, topXCoeffs, topYCoeffs, refW, refH, R, edgeDistance, outerEdgeDistance);
    SGBuildGridTemplate(t, topXCoeffs, bottomYCoeffs, refW, refH, R, edgeDistance, outerEdgeDistance);
    SGBuildGridTemplate(t, leftXCoeffs, sideYCoeffs, refW, refH, R, edgeDistance, outerEdgeDistance);
    SGBuildGridTemplate(t, rightXCoeffs, sideYCoeffs, refW, refH, R, edgeDistance, outerEdgeDistance);
    SGBuildGridTemplate(t, topXCoeffs, sideYCoeffs, refW, refH, R, edgeDistance, outerEdgeDistance);

    SGBuildCornerTemplate(t, R, 0, R, 0, M_PI, 1.5 * M_PI, outerToInner, angularFactors, R, refW, refH, R, edgeDistance, outerEdgeDistance);
    SGBuildCornerTemplate(t, -R, 1, R, 0, 1.5 * M_PI, 2 * M_PI, outerToInner, angularFactors, R, refW, refH, R, edgeDistance, outerEdgeDistance);
    SGBuildCornerTemplate(t, -R, 1, -R, 1, M_PI_2, 0, outerToInner, angularFactors, R, refW, refH, R, edgeDistance, outerEdgeDistance);
    SGBuildCornerTemplate(t, R, 0, -R, 1, M_PI, M_PI_2, outerToInner, angularFactors, R, refW, refH, R, edgeDistance, outerEdgeDistance);

    return t;
}

static NSCache<NSString *, SGGlassMeshTemplate *> *SGGlassTemplateCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 24; });
    return cache;
}

// Instantiates the template at the real pixel size (cheap: an affine remap per vertex, no SDF work)
// and hands the result to the private mesh-transform API. Mirrors instantiateGlassMesh in Swift.
static id SGMakeGlassMesh(CGSize size, CGFloat cornerRadius) {
    cornerRadius = MIN(cornerRadius, MIN(size.width, size.height) / 2);
    if (cornerRadius <= 0 || size.width < 1 || size.height < 1) return nil;

    CGFloat edgeDistance = MIN(12.0, cornerRadius);
    NSInteger cornerResolution = 12;
    CGFloat outerEdgeDistance = 2.0;
    CGFloat displacementPoints = 20.0;

    NSString *key = [NSString stringWithFormat:@"%.1f-%.1f-%ld-%.1f", cornerRadius, edgeDistance, (long)cornerResolution, outerEdgeDistance];
    SGGlassMeshTemplate *tmpl = [SGGlassTemplateCache() objectForKey:key];
    if (!tmpl) {
        tmpl = SGBuildGlassMeshTemplate(cornerRadius, edgeDistance, cornerResolution, outerEdgeDistance);
        [SGGlassTemplateCache() setObject:tmpl forKey:key];
    }

    CGFloat W = size.width, H = size.height;
    CGFloat insetPoints = -1.0;
    CGFloat insetU = insetPoints / W, insetV = insetPoints / H;
    CGFloat usableU = (W - insetPoints * 2) / W, usableV = (H - insetPoints * 2) / H;
    CGFloat dU = displacementPoints / W, dV = displacementPoints / H;

    NSUInteger vertexCount = tmpl.vertices.length / sizeof(SGGlassVertexTemplate);
    NSUInteger faceCount = tmpl.faces.length / sizeof(SGMeshFace);
    const SGGlassVertexTemplate *templates = tmpl.vertices.bytes;
    SGMeshVertex *vertices = malloc(sizeof(SGMeshVertex) * vertexCount);
    for (NSUInteger i = 0; i < vertexCount; i++) {
        SGGlassVertexTemplate v = templates[i];
        CGFloat worldX = v.baseX + v.scaleX * W, worldY = v.baseY + v.scaleY * H;
        CGFloat u = worldX / W, vv = worldY / H;
        CGFloat mappedU = insetU + u * usableU, mappedV = insetV + vv * usableV;
        CGFloat fromX = MAX(0.0, MIN(1.0, mappedU + v.dispX * dU));
        CGFloat fromY = MAX(0.0, MIN(1.0, mappedV + v.dispY * dV));
        vertices[i] = (SGMeshVertex){CGPointMake(fromX, fromY), {mappedU, mappedV, v.depth}};
    }
    id transform = SGMakeMeshTransform(vertices, vertexCount, (SGMeshFace *)tmpl.faces.bytes, faceCount);
    free(vertices);
    return transform;
}

#pragma mark - SGLegacyGlassView

@interface SGLegacyGlassView () {
    CALayer *_backdropLayer;
    SGBackdropNullActionDelegate *_backdropDelegate;
    CGSize _lastSize;
    CGFloat _lastRadius;
    BOOL _lastClear;
}
@end

@implementation SGLegacyGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.layer.cornerCurve = kCACornerCurveCircular;
    self.clipsToBounds = YES;

    _backdropDelegate = [SGBackdropNullActionDelegate new];
    _backdropLayer = SGMakeBackdropLayer();
    if (_backdropLayer) {
        [self.layer addSublayer:_backdropLayer];
        _backdropLayer.delegate = _backdropDelegate;
    }

    _contentView = [[UIView alloc] initWithFrame:self.bounds];
    _contentView.backgroundColor = UIColor.clearColor;
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_contentView];

    _lastRadius = -1;
    return self;
}

- (void)updateWithSize:(CGSize)size cornerRadius:(CGFloat)cornerRadius capsule:(BOOL)capsule clear:(BOOL)clear {
    CGFloat radius = capsule ? MIN(size.width, size.height) / 2 : cornerRadius;
    BOOL sizeChanged = !CGSizeEqualToSize(size, _lastSize);
    BOOL radiusChanged = radius != _lastRadius;
    BOOL clearChanged = clear != _lastClear;
    if (!sizeChanged && !radiusChanged && !clearChanged) return;
    _lastSize = size; _lastRadius = radius; _lastClear = clear;

    if (!_backdropLayer) return;

    if (clearChanged || !_backdropLayer.filters) {
        CALayer *blur = SGFilterBlur(clear ? 6.0 : 2.0);
        CALayer *colorMatrix = SGFilterColorMatrix();
        if (blur) {
            if (clear) {
                _backdropLayer.filters = colorMatrix ? @[colorMatrix, blur] : @[blur];
            } else {
                _backdropLayer.filters = colorMatrix ? @[colorMatrix, blur] : @[blur];
            }
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.cornerRadius = radius;
    _backdropLayer.frame = CGRectMake(0, 0, size.width, size.height);
    id mesh = SGMakeGlassMesh(size, radius);
    if (mesh) [_backdropLayer setValue:mesh forKey:@"meshTransform"];
    [CATransaction commit];
}

@end
