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
// buttons) and left a gap of nothing beside a short label, so the card is as wide as what it holds (the label, the
// action and an even padding), centred in the view and never wider than kSideInset short of either edge. Spotify
// lays the label and the button out for the 374, so the mod places both itself, also when the content lays out
// again (trees/continuous/12.txt:1459-1470: the button's glass ran 26pt past a 342pt card). The strips of the view
// that are left bare do not take touches.
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
// The card's padding left of the label, and right of the glass round the action (or of the label when it has none).
static const CGFloat kPadLeft = 20, kPadRight = 20;
// The space between the label and the glass round the action.
static const CGFloat kLabelGap = 10;

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

// The label and the action of the toast's content (SPTSnackbarWithActionView), found among its direct subviews.
static void contentParts(UIView *content, UIView **label, UIView **action) {
    *label = nil;
    *action = nil;
    for (UIView *sub in content.subviews) {
        if (isActionButton(sub)) *action = sub;
        else if (!*label && [NSStringFromClass(sub.class) containsString:@"Label"]) *label = sub;
    }
}

static UILabel *innerLabel(UIView *label) {
    __block UILabel *found = nil;
    SGForEachView(label, ^(UIView *view) {
        if (!found && [view isKindOfClass:UILabel.class]) found = (UILabel *)view;
    });
    return found;
}

// How wide the label wants to be within maxWidth (a long one takes all of it and wraps).
static CGSize labelSize(UIView *label, CGFloat maxWidth) {
    UILabel *text = innerLabel(label);
    CGSize size = text ? [text sizeThatFits:CGSizeMake(maxWidth, CGFLOAT_MAX)] : label.bounds.size;
    return CGSizeMake(MIN(ceil(size.width), maxWidth), ceil(size.height));
}

// The card's width for its content: padding, label, and the action's glass when there is one.
static CGFloat cardWidth(UIView *content, CGFloat maxWidth) {
    UIView *label = nil, *action = nil;
    contentParts(content, &label, &action);
    CGFloat actionWidth = action ? action.bounds.size.width + kActionPadX * 2 + kLabelGap : 0;
    CGFloat padRight = action ? kPadRight - kActionPadX : kPadRight;
    CGFloat room = maxWidth - kPadLeft - padRight - actionWidth;
    CGFloat labelWidth = label ? labelSize(label, MAX(room, 1)).width : 0;
    return MIN(kPadLeft + labelWidth + actionWidth + padRight, maxWidth);
}

// The label and the action inside the card, centred on its height: the label from the left padding, the action
// against the right one.
static void layoutContent(UIView *content) {
    CGSize size = content.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    UIView *label = nil, *action = nil;
    contentParts(content, &label, &action);
    CGFloat padRight = action ? kPadRight - kActionPadX : kPadRight;
    CGFloat actionWidth = action ? action.bounds.size.width : 0;
    if (action) {
        CGRect frame = CGRectMake(size.width - padRight - actionWidth, round((size.height - action.bounds.size.height) / 2), actionWidth, action.bounds.size.height);
        if (!CGRectEqualToRect(action.frame, frame)) action.frame = frame;
    }
    if (label) {
        CGFloat room = size.width - kPadLeft - padRight - (action ? actionWidth + kActionPadX * 2 + kLabelGap : 0);
        CGSize fit = labelSize(label, MAX(room, 1));
        CGRect frame = CGRectMake(kPadLeft, round((size.height - fit.height) / 2), fit.width, fit.height);
        if (!CGRectEqualToRect(label.frame, frame)) label.frame = frame;
    }
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

    // The content is the card's one view that is not the mod's glass or film (it is what Spotify added).
    UIView *content = nil;
    for (UIView *sub in card.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"SPTSnackbarWithActionView"]) content = sub;
    }
    CGFloat maxWidth = snackbar.bounds.size.width - kSideInset * 2;
    CGFloat width = content ? cardWidth(content, maxWidth) : maxWidth;
    CGRect frame = CGRectMake(round((snackbar.bounds.size.width - width) / 2), 0, width, snackbar.bounds.size.height);
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

    // What the card holds follows it, and the label and the button are placed for its width.
    for (UIView *sub in card.subviews) {
        if (sub == glass || sub == objc_getAssociatedObject(card, &kFilmKey)) continue;
        if (!CGRectEqualToRect(sub.frame, card.bounds)) sub.frame = card.bounds;
        if (sub.layer.backgroundColor) sub.layer.backgroundColor = NULL;
    }
    if (content) layoutContent(content);
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

// Spotify lays the label and the action out again for its own width whenever the content lays out.
%hook SPTSnackbarWithActionView
- (void)layoutSubviews {
    %orig;
    UIView *content = (UIView *)self;
    UIView *snackbar = content.superview.superview;
    if (snackbar && objc_getAssociatedObject(snackbar, &kDressedKey)) layoutContent(content);
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
    SGRequireClasses(@[@"SPTSnackbarView", @"SPTSnackbarWithActionView", @"SPTSnackbarTextActionButton"]);
}
