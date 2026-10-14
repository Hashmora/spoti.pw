// Redesign, iOS < 26: Spotify's toasts (Added to Queue, Saved in Liked Songs and the rest) on glass.
//
// Tree (trees/continuous/26.txt:1459-1466): SPTSnackbarView id=SPTSnackbarView {8, 639} 374x50, in the main
// content view above the now playing bar, holding a UIView #FFFFFF r=6 clips (the card), which holds an
// SPTSnackbarWithActionView #FFFFFF around the label (13pt #000000) and, when the toast has an action, an
// SPTSnackbarTextActionButton (id=SPTSnackbarTextButton, "Open" 13pt #19B551).
//
// The card is dressed the way the now playing bar is (Redesigned/NowPlayingBar): its white goes, a glass pane and
// the faint white film that keeps a floating card from sinking into the page stand behind the content, and the
// corners are a capsule's (half the height, up to kMaxRadius for a toast of several lines) instead of Spotify's 6.
// The black text turns white. The action button gets a glass capsule of its own, bigger than the word so it has
// room, and a hit area to match.
//
// 374pt wide the toast ran over the controls at either edge of the page (the buttons of a header, the rows' trailing
// buttons), so the card is kSideInset narrower on each side, the content with it (Spotify lays the label and the
// button out from the content's bounds), and the strips of the view that are left bare do not take touches.
//
// The toast is laid out as it comes up, so the pass runs from its layout; it runs again a moment later in case
// Spotify paints the white back with the content.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

static const CGFloat kSideInset = 16;
static const CGFloat kMaxRadius = 28;
// The glass capsule round the action's word: its padding on each side and its height.
static const CGFloat kActionPadX = 10;
static const CGFloat kActionHeight = 32;
// How far past the button the touch still counts, so the capsule is all button.
static const CGFloat kActionHitX = 10, kActionHitY = 8;

static char kGlassKey, kFilmKey, kActionGlassKey, kDressedKey;

// The card: the plain UIView the toast holds its content in.
static UIView *cardOf(UIView *snackbar) {
    for (UIView *sub in snackbar.subviews) {
        if ([sub isMemberOfClass:UIView.class]) return sub;
    }
    return nil;
}

static BOOL isActionButton(UIView *view) {
    return [NSStringFromClass(view.class) containsString:@"SPTSnackbarTextActionButton"];
}

// The toast's text is black on its white; on glass it is white. Only a dark one is changed, so a colour Spotify
// chose on purpose (the action's green) stays.
static BOOL isDarkNeutral(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) return MAX(r, MAX(g, b)) < 0.3 && MAX(r, MAX(g, b)) - MIN(r, MIN(g, b)) < 0.1;
    CGFloat white = 0;
    return [color getWhite:&white alpha:&a] && white < 0.3;
}

static void lightenText(UIView *root) {
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (isDarkNeutral(label.textColor)) label.textColor = UIColor.whiteColor;
    });
}

static void dressAction(UIView *button) {
    CGSize size = button.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    SGRGlassCapsuleInside(button, &kActionGlassKey, CGSizeMake(size.width + kActionPadX * 2, kActionHeight), NO);
}

static void dressSnackbar(UIView *snackbar) {
    UIView *card = cardOf(snackbar);
    if (!card || snackbar.bounds.size.width < 1 || snackbar.bounds.size.height < 1) return;
    // Dressed: from here the bare strips beside the card do not take touches (pointInside below).
    if (!objc_getAssociatedObject(snackbar, &kDressedKey)) objc_setAssociatedObject(snackbar, &kDressedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGRect frame = CGRectInset(snackbar.bounds, kSideInset, 0);
    if (!CGRectEqualToRect(card.frame, frame)) card.frame = frame;
    CGFloat radius = MIN(card.bounds.size.height / 2, kMaxRadius);
    if (card.layer.backgroundColor) card.layer.backgroundColor = NULL;
    if (card.layer.cornerRadius != radius) card.layer.cornerRadius = radius;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    // The legacy glass's press grows past its pane, and the pane has the corners: nothing to clip.
    BOOL clip = !SGUseLegacyGlass();
    if (card.layer.masksToBounds != clip) card.layer.masksToBounds = clip;

    UIView *glass = SGGlassFor(card, &kGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (!CGRectEqualToRect(glass.frame, card.bounds)) glass.frame = card.bounds;
    SGShapeGlass(glass, radius, NO);
    SGRGlassFilm(card, &kFilmKey, glass, radius);

    // What the card holds follows it, so the label and the button are laid out for the narrower width.
    for (UIView *sub in card.subviews) {
        if (sub == glass || sub == objc_getAssociatedObject(card, &kFilmKey)) continue;
        if (!CGRectEqualToRect(sub.frame, card.bounds)) sub.frame = card.bounds;
        if (sub.layer.backgroundColor) sub.layer.backgroundColor = NULL;
    }
    lightenText(card);
    SGForEachView(card, ^(UIView *view) {
        if (isActionButton(view)) dressAction(view);
    });

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"toast: glass over a card of %@", NSStringFromCGRect(card.bounds)); });
}

static void dressAfterSettling(UIView *snackbar) {
    __weak UIView *weak = snackbar;
    for (NSNumber *wait in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *shown = weak;
            if (shown.window) dressSnackbar(shown);
        });
    }
}

%hook SPTSnackbarView
- (void)layoutSubviews {
    %orig;
    dressSnackbar((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    UIView *snackbar = (UIView *)self;
    if (!snackbar.window) return;
    dressSnackbar(snackbar);
    dressAfterSettling(snackbar);
}

// The bare strips either side of the card are not the toast's: a touch there reaches the controls under them.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *snackbar = (UIView *)self;
    UIView *card = objc_getAssociatedObject(snackbar, &kDressedKey) ? cardOf(snackbar) : nil;
    if (card) return CGRectContainsPoint(card.frame, point);
    return %orig;
}
%end

%hook SPTSnackbarTextActionButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(((UIView *)self).bounds, -kActionHitX, -kActionHitY), point);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"SPTSnackbarView", @"SPTSnackbarTextActionButton"]);
}
