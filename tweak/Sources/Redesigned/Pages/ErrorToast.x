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
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

static char kGlassKey, kFilmKey, kReloadGlassKey;

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
        if (reload.layer.backgroundColor) reload.layer.backgroundColor = NULL;
        for (UIView *sub in reload.subviews) {
            if ([sub isKindOfClass:UILabel.class]) continue;
            if (sub.layer.backgroundColor && sub.bounds.size.width >= reload.bounds.size.width - 1) sub.layer.backgroundColor = NULL;
        }
        SGRGlassCapsuleInside(reload, &kReloadGlassKey, CGSizeMake(reload.bounds.size.width + kReloadPadX * 2, kReloadHeight), NO);
    }

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
