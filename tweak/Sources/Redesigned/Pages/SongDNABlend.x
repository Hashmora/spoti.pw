// Song DNA's pages under SPNavigationBar, the redesign's bar over each (Pages/PageBar.m):
//
//   BlendViewController         the songs two people share, reached from a contributor's "view N songs together"
//   ArtistsDNAViewController    the contributors' page (trees/continuous/15.txt): the same bar (Back, Share and Close
//                               in the trailing stack, the Song DNA logo and its Beta tag as the title), which had
//                               none of the redesign. Its first row is a view above the list, not a row in it, so
//                               only the bar is dressed and the list is left as Spotify's
//
// Tree (trees/continuous/41.txt): a black page holding a radial gradient and the list from y=91, over it the navigation
// controller's blur (a plain 390x91 view with a UIVisualEffectView, #1C1C1C@0.73) and SPNavigationBar with Back, a
// trailing stack of Share (the Song DNA share button) and Close, and a title that is a picture, the Song DNA logo and
// its Beta tag, not a label. So the blur goes, Back, Share and Close are glass circles pinned to the corners (Close at
// the corner, Share beside it), and the logo sits on a glass capsule the way a name does on the playlist.
//
// The list began where the bar ends and stopped where the tab bar begins (trees/continuous/10.txt: {0, 91}, 670 high,
// clipped), so the rows scrolled up were cut off in a straight line under the glass buttons, a black band where the
// bar's blur used to be. Now the list is the page's whole height from its top edge, with the bar as its top inset and
// what the bars below take as its bottom inset, so rows run on under the glass the way Recents' do (Pages/Recents.x).
// Spotify's constraints put the frame back after each pass, so the view the list stands in is watched for its layout.
//
// A swipe back keeps the title's capsule on the bar until the page is gone (SGRUndressBarPage).
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Pages.h"

// The page's list: the collection view as wide as the page.
static UICollectionView *listIn(UIView *view) {
    __block UICollectionView *list = nil;
    SGForEachView(view, ^(UIView *v) {
        if (!list && [v isKindOfClass:UICollectionView.class] && v.bounds.size.width >= view.bounds.size.width * 0.9) list = (UICollectionView *)v;
    });
    return list;
}

static void extendList(UIView *page, UICollectionView *list) {
    UIView *host = list.superview;
    if (!host || host.bounds.size.height < 1) return;
    SGRListRoom room = SGRListRoomOf(list);
    SGRSetOwnFrame(list, CGRectMake(list.frame.origin.x, 0, list.frame.size.width, host.bounds.size.height));
    SGRSetListInsets(list, UIEdgeInsetsMake(room.top, 0, MAX(room.below, page.safeAreaInsets.bottom), 0));
}

static void dress(UIViewController *page) {
    SGRDressBarPage(page);
    UIView *view = page.viewIfLoaded;
    if (!view.window) return;
    UICollectionView *list = listIn(view);
    if (!list) return;
    extendList(view, list);
    __weak UIViewController *weakPage = page;
    SGRWatchLayout(list.superview, ^(UIView *laidOut) {
        UIView *root = weakPage.viewIfLoaded;
        UICollectionView *found = root ? listIn(root) : nil;
        if (found) extendList(root, found);
    });
}

%ctor {
    if (!SGRedesignedUI() || !SGBelowiOS26()) return;
    // Both are hosted by a controller of Spotify's page template, which is the top of the stack.
    Class page = SGRSwiftClass(@"SongDNA_ArtistsDNAPageImpl", @"BlendViewController");
    if (!page) SGLog(@"class SongDNA_ArtistsDNAPageImpl.BlendViewController not found, Song DNA keeps Spotify's bar");
    SGRDressBarPagesWith(page, YES, ^(UIViewController *c) { dress(c); });
    Class artists = SGRSwiftClass(@"SongDNA_ArtistsDNAPageImpl", @"ArtistsDNAViewController");
    if (!artists) SGLog(@"class SongDNA_ArtistsDNAPageImpl.ArtistsDNAViewController not found, the contributors' page keeps Spotify's bar");
    SGRDressBarPagesOf(artists, YES);
}
