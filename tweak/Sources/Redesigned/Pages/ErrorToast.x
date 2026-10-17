// Redesign, iOS < 26: the page loader's error toast, "Something went wrong / Have another go?" with its Reload button,
// on glass like Spotify's other toasts (Kit/SGRSnackbar.x).
//
// Tree (trees/continuous/3.txt): not an SPTSnackbarView. Tome_MusicClientPageLoaderViewKit.DefaultErrorToastView,
// id=default-error-toast-view, 358x128 at the foot of a page that failed to load, #FFFFFF r=8 clips, holding two
// Encore labels in black 16pt and 13pt and an Encore.Button.Primary "Reload" (74x32, its word 13pt black). The snackbar's
// hooks never met it, so it stayed a flat white card in the middle of the glass look.
//
// It is dressed the way the snackbar's card is: the white goes, a glass pane and the faint film that keeps a floating
// card from sinking into the page stand behind the content, the corners are rounder (kRadius), the black text turns
// white, and Reload gets a glass capsule of its own, bigger than the word so it has room.
//
// Two things stood under Reload besides its capsule (trees/continuous/2.txt:895-906): Encore's own fill, which it paints
// again as the button is pressed or let go, so the button read as a plate inside the capsule (it is held clear now,
// SGRHoldClear, with the plain view Encore lays inside it), and the glass was only dressed on the toast's own passes.
// The cross at the top-left of the page (a Tertiary button beside the toast, 24x48) gets the round glass every top bar
// button has (Kit/SGRGlass.h), the way the cover art page's does.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kGlassKey, kFilmKey, kReloadGlassKey, kCloseGlassKey;

static const CGFloat kRadius = 24;
// The glass round Reload: its padding on each side of the word and its height.
static const CGFloat kReloadPadX = 12, kReloadHeight = 36;

// Only a dark neutral is lightened, so a colour Spotify chose on purpose stays.
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

// The Reload button: Spotify's Primary button, found by its identifier.
static UIView *reloadIn(UIView *toast) {
    __block UIView *found = nil;
    SGForEachView(toast, ^(UIView *view) {
        if (!found && [view.accessibilityIdentifier isEqualToString:@"Encore.Button.Primary"]) found = view;
    });
    return found;
}

// Spotify's own fill of Reload: the button's and the plain view Encore lays inside it, whatever their size. Cleared now and
// kept clear (SGRHoldClear) as Encore paints them again.
static void clearReloadFill(UIView *reload, UIView *shape) {
    if (reload.backgroundColor && ![reload.backgroundColor isEqual:UIColor.clearColor]) reload.backgroundColor = UIColor.clearColor;
    if (reload.layer.backgroundColor) reload.layer.backgroundColor = NULL;
    SGRHoldClear(reload);
    for (UIView *sub in reload.subviews) {
        if (sub == shape || ![sub isMemberOfClass:UIView.class]) continue;
        if (sub.backgroundColor && ![sub.backgroundColor isEqual:UIColor.clearColor]) sub.backgroundColor = UIColor.clearColor;
        if (sub.layer.backgroundColor) sub.layer.backgroundColor = NULL;
        SGRHoldClear(sub);
    }
    // The press of the legacy glass grows past the button and would be cut off at its edge.
    if (reload.clipsToBounds) reload.clipsToBounds = NO;
}

// The cross: the Tertiary button at the top-left of the page the toast stands on, as on the cover art page.
static void glassClose(UIView *page) {
    for (UIView *sub in page.subviews) {
        if (![NSStringFromClass(sub.class) hasSuffix:@"Button8Tertiary"]) continue;
        if (CGRectGetMinY(sub.frame) > 120 || CGRectGetMinX(sub.frame) > 120 || sub.bounds.size.width > 80) continue;
        SGRGlassInside(sub, &kCloseGlassKey, SGRGlassCircleSize);
        if (sub.clipsToBounds) sub.clipsToBounds = NO;
    }
}

static void dressToast(UIView *toast) {
    CGSize size = toast.bounds.size;
    if (!toast.window || size.width < 1 || size.height < 1) return;

    CGFloat radius = MIN(size.height / 2, kRadius);
    if (toast.layer.backgroundColor) toast.layer.backgroundColor = NULL;
    if (toast.layer.cornerRadius != radius) toast.layer.cornerRadius = radius;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    // The legacy glass's press grows past its pane, and the pane has the corners: nothing to clip.
    BOOL clip = !SGUseLegacyGlass();
    if (toast.layer.masksToBounds != clip) toast.layer.masksToBounds = clip;

    UIView *glass = SGGlassFor(toast, &kGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (!CGRectEqualToRect(glass.frame, toast.bounds)) glass.frame = toast.bounds;
    SGShapeGlass(glass, radius, NO);
    SGRGlassFilm(toast, &kFilmKey, glass, radius);

    lightenText(toast);
    UIView *reload = reloadIn(toast);
    if (reload && reload.bounds.size.width > 1 && reload.bounds.size.height > 1) {
        // The button's own fill goes; the capsule stands in it.
        UIView *shape = SGRGlassCapsuleInside(reload, &kReloadGlassKey, CGSizeMake(reload.bounds.size.width + kReloadPadX * 2, kReloadHeight), NO);
        clearReloadFill(reload, shape);
    }
    if (toast.superview) glassClose(toast.superview);

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"error toast: glass over a card of %@", NSStringFromCGRect(toast.bounds)); });
}

%group SGRErrorToast
%hook SGRErrorToastView
- (void)layoutSubviews {
    %orig;
    dressToast((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    UIView *toast = (UIView *)self;
    if (!toast.window) return;
    dressToast(toast);
    // Spotify paints the white and the button back as the toast's content is set.
    __weak UIView *weak = toast;
    for (NSNumber *wait in @[@0.0, @0.25]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *shown = weak;
            if (shown.window) dressToast(shown);
        });
    }
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    Class toast = SGRPageClass(@"Tome_MusicClientPageLoaderViewKit", @"DefaultErrorToastView");
    if (toast) {
        %init(SGRErrorToast, SGRErrorToastView = toast);
    } else {
        SGLog(@"class Tome_MusicClientPageLoaderViewKit.DefaultErrorToastView not found, the page loader's error toast keeps Spotify's card");
    }
}
