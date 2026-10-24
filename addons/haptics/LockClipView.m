#import "LockClipView.h"
#import <AVFoundation/AVFoundation.h>

static const NSTimeInterval kFade = 0.35;
// How much of the clip's height, at its top and its bottom, fades into the bands.
static const CGFloat kEdgeFade = 0.12;

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
    BOOL _startsPlaying;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    _bands = [CAGradientLayer layer];
    _bands.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor];
    [self.layer addSublayer:_bands];
    _feed = dispatch_queue_create("com.vitrine.addon.lockclip", DISPATCH_QUEUE_SERIAL);
    _startsPlaying = YES;
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
    CMTimebaseSetRate(timebase, _startsPlaying ? 1 : 0);
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
    _startsPlaying = playing;
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

