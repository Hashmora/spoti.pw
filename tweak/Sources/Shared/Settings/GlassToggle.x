// The switch for this tweak: a Glass UI row at the top of Spotify's own Settings page. It belongs to this
// tweak alone and asks nothing of any other: no other tweak's settings page is hooked, so it is there
// whatever else is injected beside it. The row stores PGKeyLegacyGlass (Core/PGUIMode.h) itself and the
// glass reads it at launch, so a change waits for the restart, which the row offers.
//
// Spotify's Settings page is found at run time, not by one class name: the first view controller of a
// navigation stack whose class name has "Settings" in it (the pages pushed from it are not the page), and
// the row goes into the largest scroll view on it, in a strip of contentInset above the first section.
// Every page that is taken for Settings is logged, so a miss can be read from `make log`.
// Nothing happens from iOS 26, where there is no glass of ours to switch.
#import "Core/PGCore.h"

static const CGFloat kRowHeight = 76;
static const CGFloat kRowGap = 12;
static const CGFloat kSideMargin = 16;

static char kRowKey;

static UIViewController *topController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) window = candidate;
    }
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Spotify"
        message:on ? @"Glass UI takes over when Spotify starts again. Spotify closes now; open it again to see it."
                   : @"Glass UI is switched off when Spotify starts again. Spotify closes now; open it again to see it."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { PGRestartSpotify(); }]];
    [topController() presentViewController:alert animated:YES completion:nil];
}

@interface PGGlassToggleRow : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UISwitch *toggle;
- (void)syncFromStore;
@end

@implementation PGGlassToggleRow

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;   // Spotify is dark whatever the system is
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.09];
    self.layer.cornerRadius = 16;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    _titleLabel = [UILabel new];
    _titleLabel.text = @"Glass UI";
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self addSubview:_titleLabel];

    _infoLabel = [UILabel new];
    _infoLabel.text = @"Liquid Glass for iOS below 26. Takes effect after Spotify restarts.";
    _infoLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _infoLabel.font = [UIFont systemFontOfSize:12];
    _infoLabel.numberOfLines = 2;
    [self addSubview:_infoLabel];

    _toggle = [UISwitch new];
    _toggle.onTintColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    [_toggle addTarget:self action:@selector(flipped) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_toggle];
    [self syncFromStore];
    return self;
}

- (void)syncFromStore {
    self.toggle.on = PGFlag(PGKeyLegacyGlass, NO);
}

- (void)flipped {
    PGSetEnabled(PGKeyLegacyGlass, self.toggle.isOn);
    PGLog(@"settings: Glass UI switched %@", self.toggle.isOn ? @"on" : @"off");
    offerRestart(self.toggle.isOn);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize sw = self.toggle.intrinsicContentSize;
    self.toggle.frame = CGRectMake(CGRectGetWidth(self.bounds) - 16 - sw.width, (CGRectGetHeight(self.bounds) - sw.height) / 2, sw.width, sw.height);
    CGFloat textWidth = CGRectGetMinX(self.toggle.frame) - 12 - 16;
    CGSize info = [self.infoLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)];
    CGFloat titleHeight = ceil(self.titleLabel.font.lineHeight);
    CGFloat block = titleHeight + 3 + info.height;
    CGFloat top = (CGRectGetHeight(self.bounds) - block) / 2;
    self.titleLabel.frame = CGRectMake(16, top, textWidth, titleHeight);
    self.infoLabel.frame = CGRectMake(16, top + titleHeight + 3, textWidth, info.height);
}

@end

static BOOL hasSettingsName(UIViewController *vc) {
    return [NSStringFromClass(vc.class) rangeOfString:@"Settings" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// The Settings page itself: not a container, not a part of another Settings page, and not one pushed
// from it.
static BOOL isMainSettingsPage(UIViewController *vc) {
    if (!hasSettingsName(vc)) return NO;
    if ([vc isKindOfClass:UINavigationController.class] || [vc isKindOfClass:UITabBarController.class]) return NO;
    UIViewController *parent = vc.parentViewController;
    if (parent && ![parent isKindOfClass:UINavigationController.class] && hasSettingsName(parent)) return NO;
    NSArray<UIViewController *> *stack = vc.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObject:vc];
    if (index == NSNotFound) return YES;
    for (NSUInteger i = 0; i < index; i++) if (hasSettingsName(stack[i])) return NO;
    return YES;
}

static UIScrollView *largestScrollView(UIView *root) {
    UIScrollView *best = nil;
    CGFloat bestArea = 0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UIScrollView.class] && CGRectGetWidth(view.bounds) >= CGRectGetWidth(root.bounds) * 0.8) {
            CGFloat area = CGRectGetWidth(view.bounds) * CGRectGetHeight(view.bounds);
            if (area > bestArea) { best = (UIScrollView *)view; bestArea = area; }
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return best;
}

static void placeRow(UIViewController *vc) {
    UIScrollView *scroll = largestScrollView(vc.view);
    if (!scroll) {
        PGLog(@"settings: %@ is taken for Settings but has no scroll view, no Glass UI row", NSStringFromClass(vc.class));
        return;
    }
    PGGlassToggleRow *row = objc_getAssociatedObject(scroll, &kRowKey);
    if (!row) {
        row = [PGGlassToggleRow new];
        objc_setAssociatedObject(scroll, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PGLog(@"settings: Glass UI row put on %@ (%@)", NSStringFromClass(vc.class), NSStringFromClass(scroll.class));
    }
    if (row.superview != scroll) [scroll addSubview:row];
    [row syncFromStore];

    // A strip of inset above the first section is where the row lives; Spotify may set the inset again,
    // so a missing strip is put back.
    CGFloat strip = kRowHeight + kRowGap;
    if (scroll.contentInset.top < strip - 0.5) {
        UIEdgeInsets inset = scroll.contentInset;
        BOOL atTop = scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1;
        inset.top += strip;
        scroll.contentInset = inset;
        if (atTop) scroll.contentOffset = CGPointMake(scroll.contentOffset.x, -scroll.adjustedContentInset.top);
    }
    row.frame = CGRectMake(kSideMargin, -strip, CGRectGetWidth(scroll.bounds) - 2 * kSideMargin, kRowHeight);
    [scroll bringSubviewToFront:row];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!PGRedesignAvailable() || !isMainSettingsPage(self)) return;
    placeRow(self);
    // Spotify fills the page in after it appears and may reset the inset as it does.
    __weak UIViewController *weakSelf = self;
    for (NSNumber *delay in @[@0.4, @1.2]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *vc = weakSelf;
            if (vc.viewIfLoaded.window) placeRow(vc);
        });
    }
}
%end

%ctor {
    %init;
}
