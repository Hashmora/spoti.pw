// The player screen's pinned header: the row of title, device, add and play that comes down under the status
// bar once the cover has scrolled away (id=now-playing-sticky-header, NowPlaying_ViewImpl.
// StickyHeaderViewControllerImpl; trees/continuous 2026-10-09, screens 2 and 5).
//
// Spotify draws it opaque, the album's colour (#F8A048 in the trees) in the row's stack and in the 47pt strip
// over the status bar, and a 60% black over each. Glass UI leaves it as a plain flat band across the top of
// everything else the redesign made glass. So the paint goes (PGRRepaint.x keeps it gone when Spotify paints
// it again on the next track) and a glass pane takes its place, behind the row's own views.
//
// The pane is a subview of the row's stack, not of the header: the stack is the view Spotify hides and shows
// as the header comes and goes, and the pane is hidden and shown with it without this file hearing of it. It
// reaches up over the status bar strip and is square: a band across the screen, as the header is, where the
// now playing bar and the tab bar are floating cards. The player screen is otherwise left to Spotify.
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"
#import "Redesigned/Kit/PGRRepaint.h"

static char kGlassKey;

// The stack the pinned row is in: the tallest stack under the header (63pt; the one beside it is 0pt high
// until a second line is shown).
static UIView *rowStackIn(UIView *root) {
    UIView *best = nil;
    for (UIView *sub in root.subviews) {
        if (![sub isKindOfClass:UIStackView.class]) continue;
        if (!best || sub.bounds.size.height > best.bounds.size.height) best = sub;
    }
    return best.bounds.size.height > 40 ? best : nil;
}

static void styleStickyHeader(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root || root.bounds.size.width < 100 || root.bounds.size.height < 40) return;
    pgr_stickyHeaderRoot = root;

    UIView *row = rowStackIn(root);
    if (!row) return;

    UIView *glass = PGGlassFor(row, &kGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // The paint: the header's own views other than the row, then the row's, leaving the pane alone (its tint
    // is painted too).
    for (UIView *sub in root.subviews) {
        if (sub != row) PGStripBackgrounds(sub);
    }
    row.layer.backgroundColor = NULL;
    for (UIView *sub in row.subviews) {
        if (sub != glass) PGStripBackgrounds(sub);
    }

    // From the top of the screen to the bottom of the row, the width of the screen.
    CGRect band = [row convertRect:root.bounds fromView:root];
    if (!CGRectEqualToRect(glass.frame, band)) glass.frame = band;
    PGShapeGlass(glass, 0, NO);
    PGRThickenSheetGlass(glass, 0);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PGLog(@"player sticky header: glass band %@ over a row of %@", NSStringFromCGRect(band), NSStringFromCGRect(row.frame));
    });
}

%hook _TtC19NowPlaying_ViewImpl30StickyHeaderViewControllerImpl
- (void)viewDidLayoutSubviews {
    %orig;
    styleStickyHeader((UIViewController *)self);
}

// The header is there from the first frame the player opens with, before the first layout pass of its own.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    styleStickyHeader((UIViewController *)self);
}
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
    PGRequireClasses(@[@"_TtC19NowPlaying_ViewImpl30StickyHeaderViewControllerImpl"]);
}
