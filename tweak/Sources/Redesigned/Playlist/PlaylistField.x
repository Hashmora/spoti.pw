// Playlist redesign: the artwork field behind the whole page, and what the switch forces.
//
// Tree (trees/clean/playlist/02.txt:23 and :1096): FTPViewController's view holds the list
// (ListUXPlatform_FreeTierPlaylistImpl.FTPTouchCancellingCollectionView, id=SPTFreeTierPlaylistTableView,
// the size of the window) and, after it and so over it, the header (id=PL.Header). Neither scrolls the
// other: the list keeps its frame and the header's y runs from -134 at rest to -529 scrolled, so a field
// put behind both stays still while the cover at the top of the header slides up over it -- which is what
// the Music app does with the page colour.
//
// So the field is the page's bottom-most view, the size of the view and bleeding past it, with no backdrop
// of its own: the sharp cover at the top of the header is the picture, and PlaylistHeader.x fades it into
// exactly this field's colour. What Spotify paints over the field -- the page, the list and every row, all
// of them the base surface -- is kept clear by the Kit's repaint hook while pgr_playlistRoot is this page.
//
// The colour is read from the cover the header shows (PlaylistHeader.x hands it over), and until that has
// loaded the field is the neutral one, as it is for a playlist with no cover at all.
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"
#import "Playlist.h"

NSString *const PGRPlaylistListIdentifier = @"SPTFreeTierPlaylistTableView";

// Above for the bounce at the top of the list, below for the one at the end of it.
static const UIEdgeInsets kBleed = {600, 0, 600, 0};

static char kFieldKey;

#pragma mark - the page's field

static PGRArtworkField *fieldOn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        PGRArtworkField *field = objc_getAssociatedObject(v, &kFieldKey);
        if (field) return field;
    }
    return nil;
}

UIColor *PGRPlaylistFieldColor(UIView *view) {
    PGRArtworkField *field = fieldOn(view);
    return field.fieldColor ?: PGRNeutralField();
}

void PGRPlaylistSetArtwork(UIView *view, UIImage *image) {
    if (image) [fieldOn(view) setArtwork:image identity:nil animated:YES];
}

static PGRArtworkField *fieldIn(UIView *page) {
    PGRArtworkField *field = objc_getAssociatedObject(page, &kFieldKey);
    if (field) return field;
    field = [[PGRArtworkField alloc] initWithFrame:page.bounds];
    field.bleed = kBleed;
    objc_setAssociatedObject(page, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PGLog(@"redesign playlist: field on the page %.0fx%.0f", page.bounds.size.width, page.bounds.size.height);
    return field;
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (!page || page.bounds.size.height < 200) return;
    pgr_playlistRoot = page;
    PGRArtworkField *field = fieldIn(page);
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
}

// The page the repaint hook keeps clear is the one on screen; another playlist pushed over this one sets
// itself from its own pass, and this one sets itself again when it comes back.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (page) pgr_playlistRoot = page;
}
%end

// The list paints itself the base surface from its own pass rather than through a layer that the repaint
// hook would hear about, so it is cleared where it is laid out.
%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    UIScrollView *list = (UIScrollView *)self;
    if (list.backgroundColor && PGIsBaseSurface(list.backgroundColor.CGColor)) list.backgroundColor = UIColor.clearColor;
}
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
    PGRequireClasses(@[
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController",
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView",
    ]);
}
