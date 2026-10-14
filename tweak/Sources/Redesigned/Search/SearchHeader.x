// Search redesign, iOS < 26: the header of the results page, the one that holds the field once something is typed
// and sent with return (and the recents under it). Spotify draws it as a flat #1F1F1F backing with a grey capsule
// for the field and grey capsules for the chips. Here the backing goes, the field is a glass capsule and the chips
// are glass the way the Library's are (Library/LibraryHeader.x takes them: it answers to this row's identifier too).
//
// Tree (trees/continuous/14.txt:511-610): Search_FeatureImpl.HeaderViewController's view is a plain UIView
// 390x143 bg=#1F1F1F, holding at {0, 47} a 96pt UIView with a vertical UIStackView of
//
//     a 32pt row   MultilineSearchBarContainer (id=SearchBarSearch) > UIView 358x32 > the field's fill, a plain
//                  UIView 304x32 bg=#FFFFFF@0.10 r=16 clips holding the text view and the clear button, and
//                  the Cancel button beside it
//     a 40pt row   id=Components.UI.FiltersView, a collection of FilterChipView (the chips' fills are plain
//                  UIViews bg=#FFFFFF@0.10 r=16, as in the Library)
//
// With the backing gone the results would run up under the status bar and the field with nothing behind them, so a
// black plate stands behind everything above the chips, and the chips are glass over the list. The page's own paint
// is held clear by SGRRepaint.x (sgr_searchHeaderRoot, sgr_searchFieldFill), which Spotify puts back on its passes.
// Threading: main thread only.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Search.h"

static char kContainerKey, kFiltersKey, kPlateKey, kFieldGlassKey;

// The field's own fill: a plain UIView with the text view in it, one level under the container's wrapper. Known
// again once it is ours (its corners stay, its paint is gone).
static UIView *fieldFill(UIView *container) {
    for (UIView *wrapper in container.subviews) {
        for (UIView *sub in wrapper.subviews) {
            if (![sub isMemberOfClass:UIView.class]) continue;
            if (sub.bounds.size.width < 100 || sub.bounds.size.height < 20) continue;
            if (sub == sgr_searchFieldFill || sub.layer.cornerRadius > 0) return sub;
        }
    }
    return nil;
}

// A black plate behind the status bar and the field row; the chips under it are glass over the list.
static void plateBehindField(UIView *root) {
    UIView *filters = SGRFindByIdentifier(root, SGRSearchFiltersIdentifier, &kFiltersKey);
    CGFloat edge = root.bounds.size.height;
    if (filters.superview) {
        CGFloat top = SGFrameIn(filters, root).origin.y;
        if (top > 1) edge = MIN(edge, top);
    }
    UIView *plate = objc_getAssociatedObject(root, &kPlateKey);
    if (!plate) {
        plate = [UIView new];
        plate.backgroundColor = UIColor.blackColor;
        plate.userInteractionEnabled = NO;
        plate.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(root, &kPlateKey, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (plate.superview != root || root.subviews.firstObject != plate) [root insertSubview:plate atIndex:0];
    CGRect frame = CGRectMake(0, 0, root.bounds.size.width, edge);
    if (!CGRectEqualToRect(plate.frame, frame)) plate.frame = frame;
}

static void dress(UIView *root) {
    if (!root || root.bounds.size.width < 1) return;
    if (sgr_searchHeaderRoot != root) sgr_searchHeaderRoot = root;
    if (root.layer.backgroundColor) root.layer.backgroundColor = NULL;

    UIView *container = SGRFindByIdentifier(root, @"SearchBarSearch", &kContainerKey);
    UIView *fill = container ? fieldFill(container) : nil;
    if (fill) {
        if (sgr_searchFieldFill != fill) sgr_searchFieldFill = fill;
        SGRGlassFlatBox(fill, &kFieldGlassKey);
    }
    plateBehindField(root);

    static BOOL logged;
    if (!logged && root.window && fill) {
        logged = YES;
        SGLog(@"redesign search: results header %@, field %@, chips %@", NSStringFromCGRect(root.frame),
              NSStringFromCGRect(fill.frame), SGRFindByIdentifier(root, SGRSearchFiltersIdentifier, &kFiltersKey) ? @"found" : @"not shown");
    }
}

%hook _TtC18Search_FeatureImpl20HeaderViewController
- (void)viewDidLayoutSubviews {
    %orig;
    dress(((UIViewController *)self).viewIfLoaded);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dress(((UIViewController *)self).viewIfLoaded);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGBelowiOS26()) return;
    %init;
    SGRequireClasses(@[@"_TtC18Search_FeatureImpl20HeaderViewController"]);
}
