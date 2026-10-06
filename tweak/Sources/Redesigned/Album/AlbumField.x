// Album redesign: the artwork field behind the whole page, and what the switch forces.
//
// Tree (trees/clean/album/01.txt:22). The page is CreativeWorkPlatform.CreativeWorkTemplateView, and it
// holds, in this order: the header's colour wash (a LegacyUI HeaderView the height of the header, with
// Spotify's GradientView in it), CreativeWorkPlatform.Tab with the scrolling list inside it, the sticky
// HeaderNavigationBar, and the two controls Spotify floats over the page, shuffle and play. Nothing of it
// scrolls except what is inside the Tab, so a field put behind the lot stays still while the cover at the
// top of the header slides up over it -- which is what the Music app does with the page colour.
//
// So the field is the page's bottom-most view, the size of the view and bleeding past it, with no backdrop
// of its own: the sharp cover at the top of the header is the picture, and AlbumHeader.x fades it into
// exactly this field's colour, and conceals Spotify's wash so the field is what shows. What Spotify paints
// over the field -- the list and every row, all of them the base surface -- is kept clear by the Kit's
// repaint hook while pgr_albumRoot is this page, and by the list's own pass below, which paints itself
// rather than through a layer the repaint hook would hear about.
//
// The colour is Spotify's own for the album, read off the wash it paints behind the header, which
// AlbumHeader.x hands over as it conceals it. Spotify reads the whole cover; the Kit's palette reads its
// bottom edge, and a scanned cover's bottom edge is the scanner's pale border, which turned the field grey
// where Spotify had it blue (device, 2026-09-18). The colour read from the cover is what shows until
// Spotify's arrives, or for good if it never does, and before either the field is the neutral one.
//
// The page is the album's by its identifier, which is how Native/Album/Album.x has told it apart since it
// shipped: the artist page is TemplateKit's TemplateView instead. A podcast's episode page is built from
// this same template (trees/continuous/1.txt 2026-09-20: CreativeWorkTemplateView over Element_List cells
// of EpisodePage_ModernEpisodePageImpl), so it is given the field too, and everything below that holds for
// the album holds for it. What it puts on the field is its own -- a description, a comments card, Episode
// Transcript, See all episodes -- and only the paint is taken off it; AlbumHeader.x and AlbumSections.x
// look for the album's own elements and find none of them there.
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRKit.h"
#import "Album.h"

static NSString *const kPageIdentifier = @"CreativeWorkPlatform.CreativeWorkTemplateView";

// Above for the bounce at the top of the list, below for the one at the end of it.
static const UIEdgeInsets kBleed = {600, 0, 600, 0};

static char kFieldKey;

#pragma mark - the page

UIView *PGRAlbumPageOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPageIdentifier]) return v;
    }
    return nil;
}

// A cell of the page's own list rather than a card inside one of its carousels: a card is a cell of the
// same class, and the row that carries the carousel decides for it (Artist/ArtistSections.x). So the walk
// up to the page stops at the first cell it meets on the way.
static BOOL isPageCell(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionViewCell.class]) return NO;
        if ([v.accessibilityIdentifier isEqualToString:kPageIdentifier]) return YES;
    }
    return NO;
}

#pragma mark - the page's field

static PGRArtworkField *fieldOn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        PGRArtworkField *field = objc_getAssociatedObject(v, &kFieldKey);
        if (field) return field;
    }
    return nil;
}

UIColor *PGRAlbumFieldColor(UIView *view) {
    PGRArtworkField *field = fieldOn(view);
    return field.fieldColor ?: PGRNeutralField();
}

void PGRAlbumSetArtwork(UIView *view, UIImage *image) {
    if (image) [fieldOn(view) setArtwork:image identity:nil animated:YES];
}

void PGRAlbumSetSpotifyColor(UIView *view, UIColor *color) {
    if (color) [fieldOn(view) setPreferredColor:color];
}

static PGRArtworkField *fieldIn(UIView *page) {
    PGRArtworkField *field = objc_getAssociatedObject(page, &kFieldKey);
    if (field) return field;
    field = [[PGRArtworkField alloc] initWithFrame:page.bounds];
    field.bleed = kBleed;
    objc_setAssociatedObject(page, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PGLog(@"redesign album: field on the page %.0fx%.0f", page.bounds.size.width, page.bounds.size.height);
    return field;
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    UIView *page = (UIView *)self;
    if (page.bounds.size.height < 200) return;
    // The page the repaint hook keeps clear is the one laying out, which is the one on screen; an album
    // pushed over this one sets itself from its own pass, and this one sets itself again coming back.
    pgr_albumRoot = page;
    PGRArtworkField *field = fieldIn(page);
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
}
%end

// The list paints itself the base surface from its own pass. Its collection view is a private class whose
// name carries a build hash, so the list view around it -- one public name, one child -- is where it is
// cleared.
%hook _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView
- (void)layoutSubviews {
    %orig;
    UIView *list = (UIView *)self;
    if (!PGRAlbumPageOf(list)) return;
    if (list.backgroundColor && PGIsBaseSurface(list.backgroundColor.CGColor)) list.backgroundColor = UIColor.clearColor;
    for (UIView *sub in list.subviews) {
        if (sub.backgroundColor && PGIsBaseSurface(sub.backgroundColor.CGColor)) sub.backgroundColor = UIColor.clearColor;
    }
}
%end

// Every cell of the list paints the base surface too, and the repaint hook misses it: a cell is painted
// before it is inside the page, and a reused one brings its old paint with it. On the episode page the
// Episode Transcript row, the empty section under it and the rule under that sat on black bands (device,
// trees/continuous/1.txt 2026-09-20).
%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *cell = (UIView *)self;
    if (isPageCell(cell)) PGRClearCellPaint(cell);
}
%end

%ctor {
    if (!PGRedesignedUI()) return;
    %init;
    PGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView",
        @"_TtC12Element_List18CollectionViewCell",
    ]);
}
