// The switch for this tweak: a Glass UI row with its own UISwitch at the top of Spotify's side drawer (the
// avatar menu), under the profile header. It belongs to this tweak alone and asks nothing of any other: no
// other tweak's settings page is hooked, so it is there whatever else is injected beside it. The row stores
// PGKeyLegacyGlass (Core/PGUIMode.h) itself and the glass reads it at launch, so a change waits for the
// restart, which the row offers.
//
// The drawer is SideDrawer_ECMKit.SideDrawerContainer holding SideDrawer_ListPageImpl.ListViewController,
// whose list is a SideDrawer_ListPageImpl SideDrawerListCollectionView. The row goes into that list in a strip of
// contentInset above the first item, where the Mod Settings row of spoti.pw sits as well: the row stacks above
// any other row it finds there rather than taking the same place.
// Nothing happens from iOS 26, where there is no glass of ours to switch.
#import "Core/PGCore.h"

static const CGFloat kRowHeight = 56;

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

@interface PGGlassToggleRow : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISwitch *toggle;
- (void)syncFromStore;
@end

@implementation PGGlassToggleRow

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;   // Spotify is dark whatever the system is
    self.backgroundColor = UIColor.clearColor;

    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
    _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles" withConfiguration:symbol]];
    _icon.tintColor = UIColor.whiteColor;
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];

    _titleLabel = [UILabel new];
    _titleLabel.text = @"Glass UI";
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [self addSubview:_titleLabel];

    _toggle = [UISwitch new];
    _toggle.onTintColor = [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1];
    [_toggle addTarget:self action:@selector(flipped) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_toggle];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];

    [self syncFromStore];
    return self;
}

- (void)syncFromStore {
    self.toggle.on = PGFlag(PGKeyLegacyGlass, NO);
}

- (void)flipped {
    PGSetEnabled(PGKeyLegacyGlass, self.toggle.isOn);
    PGLog(@"drawer: Glass UI switched %@", self.toggle.isOn ? @"on" : @"off");
    offerRestart(self.toggle.isOn);
}

// A tap anywhere on the row flips the switch, as a tap on the switch itself does.
- (void)tapped {
    [self.toggle setOn:!self.toggle.isOn animated:YES];
    [self flipped];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isDescendantOfView:self.toggle];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGSize sw = self.toggle.intrinsicContentSize;
    self.toggle.frame = CGRectMake(width - 20 - sw.width, (height - sw.height) / 2, sw.width, sw.height);
    self.icon.frame = CGRectMake(16, (height - 24) / 2, 24, 24);
    self.titleLabel.frame = CGRectMake(52, 0, CGRectGetMinX(self.toggle.frame) - 12 - 52, height);
}

@end

static BOOL hasName(NSString *name, NSString *part) {
    return [name rangeOfString:part].location != NSNotFound;
}

static UIScrollView *drawerList(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:UIScrollView.class] && hasName(NSStringFromClass(view.class), @"SideDrawerListCollectionView")) return (UIScrollView *)view;
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

// Rows of other tweaks (spoti.pw's Mod Settings) sit in the same strip above the list's first item. They are
// plain views of the list that lie wholly above its content (negative y), span the list and are neither
// cells nor the scroll indicators. The highest of them is returned (0 when there is none), so this row
// stacks above it instead of over it, whichever of the two tweaks laid its row out first.
static CGFloat foreignStripTop(UIScrollView *scroll, UIView *ours) {
    CGFloat top = 0, width = CGRectGetWidth(scroll.bounds);
    for (UIView *view in scroll.subviews) {
        if (view == ours || view.hidden || view.alpha < 0.01) continue;
        if ([view isKindOfClass:UICollectionReusableView.class]) continue;   // cells and section headers
        if (hasName(NSStringFromClass(view.class), @"ScrollIndicator")) continue;
        CGRect frame = view.frame;
        if (CGRectGetHeight(frame) < 1 || CGRectGetWidth(frame) < width * 0.6) continue;
        if (CGRectGetMinY(frame) >= 0 || CGRectGetMaxY(frame) > 1) continue;
        top = MIN(top, CGRectGetMinY(frame));
    }
    return top;
}

static void placeRow(UIViewController *vc) {
    UIScrollView *scroll = drawerList(vc.view);
    if (!scroll) {
        PGLog(@"drawer: %@ appeared, no SideDrawerListCollectionView in it yet", NSStringFromClass(vc.class));
        return;
    }
    PGGlassToggleRow *row = objc_getAssociatedObject(scroll, &kRowKey);
    if (!row) {
        row = [PGGlassToggleRow new];
        objc_setAssociatedObject(scroll, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PGLog(@"drawer: Glass UI row put on %@", NSStringFromClass(scroll.class));
    }
    if (row.superview != scroll) [scroll addSubview:row];
    [row syncFromStore];

    // The row goes right above whatever other rows the strip already holds, and the strip grows to take it.
    // The inset is raised to what is needed, never added to, so another tweak that sizes the strip the same
    // way finds it already big enough and the two do not pile up.
    CGFloat y = foreignStripTop(scroll, row) - kRowHeight;
    if (scroll.contentInset.top < -y - 0.5) {
        UIEdgeInsets inset = scroll.contentInset;
        BOOL atTop = scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1;
        inset.top = -y;
        scroll.contentInset = inset;
        if (atTop) scroll.contentOffset = CGPointMake(scroll.contentOffset.x, -scroll.adjustedContentInset.top);
    }
    CGRect frame = CGRectMake(0, y, CGRectGetWidth(scroll.bounds), kRowHeight);
    if (!CGRectEqualToRect(row.frame, frame)) {
        row.frame = frame;
        PGLog(@"drawer: Glass UI row at y=%.0f, inset top %.0f", y, scroll.contentInset.top);
    }
    [scroll bringSubviewToFront:row];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!PGRedesignAvailable() || !hasName(NSStringFromClass(self.class), @"SideDrawer")) return;
    placeRow(self);
    // Spotify, and any tweak beside this one, fill the drawer in after it appears and may reset the inset as
    // they do; the row is placed again, and finds the other rows where they ended up.
    __weak UIViewController *weakSelf = self;
    for (NSNumber *delay in @[@0.4, @1.2, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *vc = weakSelf;
            if (vc.viewIfLoaded.window) placeRow(vc);
        });
    }
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (!PGRedesignAvailable() || !hasName(NSStringFromClass(self.class), @"SideDrawer")) return;
    if (self.viewIfLoaded.window) placeRow(self);   // changes nothing when the row already sits right
}
%end

%ctor {
    %init;
}
