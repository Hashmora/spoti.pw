// The switch for this tweak: a Glass UI row with its own UISwitch at the top of Spotify's side drawer (the
// avatar menu), under the profile header. It belongs to this tweak alone and asks nothing of any other: no
// other tweak's settings page is hooked, so it is there whatever else is injected beside it. The row stores
// PGKeyLegacyGlass (Core/PGUIMode.h) itself and the glass reads it at launch, so a change waits for the
// restart, which the row offers.
//
// The drawer is SideDrawer_ECMKit.SideDrawerContainer holding SideDrawer_ListPageImpl.ListViewController,
// whose list is a SideDrawer_ListPageImpl SideDrawerListCollectionView. The row goes into that list in a strip of
// contentInset above the first item, the same place the Mod Settings row of spoti.pw sits.
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

    // A strip of inset above the first item is where the row lives; Spotify may set the inset again, so a
    // missing strip is put back.
    if (scroll.contentInset.top < kRowHeight - 0.5) {
        UIEdgeInsets inset = scroll.contentInset;
        BOOL atTop = scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1;
        inset.top += kRowHeight;
        scroll.contentInset = inset;
        if (atTop) scroll.contentOffset = CGPointMake(scroll.contentOffset.x, -scroll.adjustedContentInset.top);
    }
    row.frame = CGRectMake(0, -kRowHeight, CGRectGetWidth(scroll.bounds), kRowHeight);
    [scroll bringSubviewToFront:row];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!PGRedesignAvailable() || !hasName(NSStringFromClass(self.class), @"SideDrawer")) return;
    placeRow(self);
    // Spotify fills the drawer in after it appears and may reset the inset as it does.
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
