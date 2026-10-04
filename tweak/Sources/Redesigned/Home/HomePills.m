// Home redesign: the filter pills (All, Music, Podcasts) as a row of glass chips under the large title, the
// way the Library's chips sit under its title (Library/LibraryHeader.x): an unselected pill's flat grey fill
// goes (Kit/SGRRepaint.x holds it clear when Spotify paints it back) and a glass capsule stands under its
// label; a selected pill keeps its own colour.
//
// Legacy only (SGRHomePillsShown): below iOS 26. From 26 the pills are not shown, see HomeHeader.x.
//
// Spotify arranges the pills in the header's stack beside the avatar, in a row 32pt tall at the header's own
// height, and the title takes that row. So the pill row is taken out of the stack (removeArrangedSubview, not
// hidden: hiding inside Spotify's stacks crashes), put in the page's view right under the header and laid out
// by frame, and the list is given the row's height as extra top inset so its first row starts below it and
// the rest scroll under the glass. Spotify's own controls stay the controls: they are only moved.
//
// The pills are Home_PillUIKit.PillScrollView's own, a Swift class tree that no tree under trees/ records
// yet, so they are found by what they are rather than by a class name: the widest view around a text label
// that holds that label alone, no taller than a pill, and is neither a scroll view nor a stack. The first
// run logs what it found, once, and a miss says so rather than leaving a header with nothing in it.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// Tallest a pill can be (the header row it sits in is 32pt).
static const CGFloat kPillMaxHeight = 48;
// How much of a pill a view must cover to be taken for its fill.
static const CGFloat kFillCover = 0.9;

static char kPillGlassKey, kPillWatchedKey;

BOOL SGRHomePillsShown(void) {
    if (@available(iOS 26.0, *)) return NO;
    return YES;
}

static NSUInteger textLabels(UIView *view) {
    __block NSUInteger count = 0;
    SGForEachView(view, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) count++;
    });
    return count;
}

// The pills under the scroll view, one per label.
static NSArray<UIView *> *pillsIn(UIView *scroll) {
    NSMutableArray<UIView *> *pills = [NSMutableArray array];
    SGForEachView(scroll, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || !((UILabel *)v).text.length) return;
        UIView *pill = nil;
        for (UIView *up = v.superview; up && up != scroll; up = up.superview) {
            if ([up isKindOfClass:UIScrollView.class] || [up isKindOfClass:UIStackView.class]) break;
            if (up.bounds.size.height > kPillMaxHeight) break;
            if (textLabels(up) != 1) break;
            pill = up;
        }
        if (pill && ![pills containsObject:pill]) [pills addObject:pill];
    });
    return pills;
}

// The views a pill's capsule can be painted on: the pill itself or a plain UIView laid across it. They are
// marked for the repaint hook, so the grey Spotify tints them with never lands, and read for the selection.
static void eachFill(UIView *pill, UIView *glass, void (^fn)(UIView *fill)) {
    CGSize size = pill.bounds.size;
    fn(pill);
    SGForEachView(pill, ^(UIView *v) {
        if (v == pill || v == glass || (glass && [v isDescendantOfView:glass])) return;
        if (![v isMemberOfClass:UIView.class]) return;
        if (v.bounds.size.width < size.width * kFillCover || v.bounds.size.height < size.height * kFillCover) return;
        fn(v);
    });
}

// A selected pill is painted a solid colour of its own to say so; an unselected one a translucent white.
static BOOL pillIsSelected(UIView *pill, UIView *glass) {
    __block BOOL selected = NO;
    eachFill(pill, glass, ^(UIView *fill) {
        CGColorRef color = fill.layer.backgroundColor;
        if (color && CGColorGetAlpha(color) > 0.5) selected = YES;
    });
    return selected;
}

// The glass goes in the pill itself, first among its subviews and under what it draws, as the Library's chips
// have it (LibraryHeader.x glassChip): a selected pill's own colour covers it by order where the colour is on
// a view above it, and is shown by hiding it where the colour is the pill's own background.
static void glassPill(UIView *pill) {
    CGSize size = pill.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    UIView *glass = objc_getAssociatedObject(pill, &kPillGlassKey);
    if (pillIsSelected(pill, glass)) {
        if (glass && !glass.hidden) glass.hidden = YES;
        return;
    }
    eachFill(pill, glass, ^(UIView *fill) {
        SGRMarkChipFill(fill);
        if (fill.layer.backgroundColor) fill.layer.backgroundColor = NULL;
    });
    SGRGlassCapsuleInside(pill, &kPillGlassKey, size, NO);
}

// A pill is laid out again at a new width when a filter is picked, which reaches neither the header nor the
// page: its glass is sized again on every pass of its own (LibraryHeader.x watchChip).
static void watchPill(UIView *pill) {
    if (objc_getAssociatedObject(pill, &kPillWatchedKey)) return;
    if (SGRObserveLayout(pill, ^(UIView *view) { glassPill(view); })) {
        objc_setAssociatedObject(pill, &kPillWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - the row under the title

// Height of the row the pills sit in, and the gap kept under it before the list's first row.
static const CGFloat kRowHeight = 32;
static const CGFloat kRowGap = 8;

static char kInsetWrittenKey, kInsetExtraKey, kScrollInsetKey;
static __weak UIView *sg_row;
static __weak UIScrollView *sg_list;

// The row: the arranged view of the header's stack that holds the PillScrollView, or the one this file
// already moved out of it.
static UIView *findRow(UIStackView *stack) {
    static Class pillClass;
    if (!pillClass) pillClass = NSClassFromString(@"_TtC14Home_PillUIKit14PillScrollView");
    if (sg_row && sg_row.superview) return sg_row;
    if (!pillClass) return nil;
    for (UIView *part in stack.arrangedSubviews) {
        __block BOOL holds = NO;
        SGForEachView(part, ^(UIView *v) { if ([v isKindOfClass:pillClass]) holds = YES; });
        if (holds) { sg_row = part; return part; }
    }
    return nil;
}

// The scroll view the pills actually scroll in. Home_PillUIKit.PillScrollView is not one itself (it answered
// no to contentInset on the device, 2026-10-05), so the first real UIScrollView at or under the row is taken:
// the PillScrollView if it is one, else whatever it wraps. nil when the row holds none.
static UIScrollView *pillScroll(UIView *row) {
    __block UIScrollView *found = nil;
    SGForEachView(row, ^(UIView *v) {
        if (!found && [v isKindOfClass:UIScrollView.class]) found = (UIScrollView *)v;
    });
    return found;
}

// Home's list: the widest, tallest scroll view of the page that is not the pill row's own.
static UIScrollView *findList(UIView *page, UIView *row) {
    if (sg_list && sg_list.window && [sg_list isDescendantOfView:page]) return sg_list;
    __block UIScrollView *best = nil;
    SGForEachView(page, ^(UIView *v) {
        if (![v isKindOfClass:UIScrollView.class] || [v isDescendantOfView:row]) return;
        if (v.bounds.size.width < page.bounds.size.width * 0.9 || v.bounds.size.height < page.bounds.size.height * 0.5) return;
        if (!best || v.bounds.size.height > best.bounds.size.height) best = (UIScrollView *)v;
    });
    sg_list = best;
    return best;
}

// The list starts `extra` lower. Spotify sets its inset as an absolute value on its own passes, so what was
// written last is remembered: an inset that still is that value has our extra in it, any other has not and
// gets it added. At the top of the list the offset moves with it, so nothing jumps.
static void makeRoom(UIScrollView *list, CGFloat extra) {
    NSNumber *written = objc_getAssociatedObject(list, &kInsetWrittenKey);
    UIEdgeInsets inset = list.contentInset;
    if (written && fabs(inset.top - written.doubleValue) < 0.01 && fabs([objc_getAssociatedObject(list, &kInsetExtraKey) doubleValue] - extra) < 0.01) return;
    CGFloat had = written && fabs(inset.top - written.doubleValue) < 0.01 ? [objc_getAssociatedObject(list, &kInsetExtraKey) doubleValue] : 0;
    BOOL atTop = list.contentOffset.y <= -inset.top + 1;
    inset.top += extra - had;
    list.contentInset = inset;
    UIEdgeInsets bar = list.verticalScrollIndicatorInsets;
    bar.top += extra - had;
    list.verticalScrollIndicatorInsets = bar;
    if (atTop) list.contentOffset = CGPointMake(list.contentOffset.x, -inset.top);
    objc_setAssociatedObject(list, &kInsetWrittenKey, @(inset.top), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, &kInsetExtraKey, @(extra), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void SGRHomeDockPills(UIViewController *controller, UIStackView *stack, UIView *header) {
    if (!SGRHomePillsShown()) return;
    UIView *page = controller.viewIfLoaded;
    UIView *row = findRow(stack);
    if (!page || !row) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: pill row not found in the header, the pills stay where Spotify has them"); });
        return;
    }
    if (row.superview != page) {
        if ([row.superview isKindOfClass:UIStackView.class]) [(UIStackView *)row.superview removeArrangedSubview:row];
        row.translatesAutoresizingMaskIntoConstraints = YES;
        row.alpha = 1;
        row.userInteractionEnabled = YES;
        row.accessibilityElementsHidden = NO;
        [page addSubview:row];
    }
    // Right under the header's row, above the list and the header's own views.
    CGFloat top = CGRectGetMaxY([header convertRect:header.bounds toView:page]);
    CGRect frame = CGRectMake(0, top, page.bounds.size.width, kRowHeight);
    if (!CGRectEqualToRect(row.frame, frame)) row.frame = frame;
    row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [page bringSubviewToFront:row];

    UIScrollView *scroll = pillScroll(row);
    if (scroll && [scroll isKindOfClass:UIScrollView.class]) {
        // The first pill lines up with the title.
        if (!objc_getAssociatedObject(scroll, &kScrollInsetKey)) {
            UIEdgeInsets inset = scroll.contentInset;
            inset.left = SGRSideMargin;
            inset.right = SGRSideMargin;
            scroll.contentInset = inset;
            scroll.contentOffset = CGPointMake(-inset.left, scroll.contentOffset.y);
            objc_setAssociatedObject(scroll, &kScrollInsetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        scroll.showsHorizontalScrollIndicator = NO;
    }
    // The pills are glassed whether or not a real scroll view holds them.
    for (UIView *pill in pillsIn(scroll ?: row)) {
        glassPill(pill);
        watchPill(pill);
    }

    UIScrollView *list = findList(page, row);
    if (list && [list isKindOfClass:UIScrollView.class]) makeRoom(list, kRowHeight + kRowGap);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign home: pill row %@ under the header (%@), pills in %@, %lu pills on glass, list %@", NSStringFromCGRect(row.frame),
              NSStringFromClass(row.class), scroll ? NSStringFromClass(scroll.class) : @"no scroll view found", (unsigned long)pillsIn(scroll ?: row).count,
              list ? NSStringFromClass(list.class) : @"not found, no room made for the row");
    });
}
