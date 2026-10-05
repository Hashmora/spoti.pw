// The switch for this tweak, in spoti.pw's Mod Settings: a Legacy Glass row under Redesigned UI in the
// Appearance card. spoti.pw knows nothing of it. The page is built from its own classes (SGModPage,
// SGModRow, SGModSection), found by name, and the row is put into the card as the page is made, so the
// tweak has a switch of its own wherever it is installed beside spoti.pw. The row is an ordinary switch
// row of that page: it stores its key (Core/PGUIMode.h) itself, and the glass reads it at launch.
// Nothing happens without spoti.pw, or from iOS 26, where there is no glass of ours to switch.
#import "Core/PGCore.h"

static NSString *const kAnchorRow = @"Redesigned UI";

static UIViewController *topController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) window = candidate;
    }
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Spotify"
        message:on ? @"Legacy Glass takes over when Spotify starts again. Spotify closes now; open it again to see it."
                   : @"Legacy Glass is switched off when Spotify starts again. Spotify closes now; open it again to see it."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { PGRestartSpotify(); }]];
    [topController() presentViewController:alert animated:YES completion:nil];
}

static id legacyGlassRow(void) {
    id row = [NSClassFromString(@"SGModRow") new];
    [row setValue:@"Legacy Glass" forKey:@"title"];
    [row setValue:PGKeyLegacyGlass forKey:@"key"];
    [row setValue:@NO forKey:@"defaultOn"];
    [row setValue:@YES forKey:@"glows"];
    [row setValue:@"circle.hexagongrid" forKey:@"symbol"];
    [row setValue:@"Liquid Glass for iOS below 26, from the pureglass tweak installed beside this one. While it is on, pureglass draws the tab bar and the redesign's own bar steps aside." forKey:@"info"];
    void (^changed)(BOOL) = ^(BOOL on) { offerRestart(on); };
    [row setValue:changed forKey:@"changed"];
    return row;
}

// The card is the one holding the Redesigned UI row, whatever it is called; the new row goes right under it.
static NSArray *withLegacyGlassRow(NSArray *sections) {
    if (!PGRedesignAvailable()) {
        PGLog(@"settings: no Legacy Glass row, this is iOS 26 or later");
        return sections;
    }
    for (id section in sections) {
        NSArray *rows = [section valueForKey:@"rows"];
        NSUInteger anchor = [[rows valueForKey:@"title"] indexOfObject:kAnchorRow];
        if (anchor == NSNotFound) continue;
        PGLog(@"settings: Legacy Glass row added under %@ in card %@", kAnchorRow, [section valueForKey:@"title"]);
        NSMutableArray *with = [rows mutableCopy];
        [with insertObject:legacyGlassRow() atIndex:anchor + 1];
        [section setValue:with forKey:@"rows"];
        return sections;
    }
    NSMutableString *out = [NSMutableString stringWithFormat:@"settings: no %@ row on this page", kAnchorRow];
    for (id section in sections) [out appendFormat:@"\n  %@: %@", [section valueForKey:@"title"], [[section valueForKey:@"rows"] valueForKey:@"title"]];
    PGLog(@"%@", out);
    return sections;
}

%hook SGModPage
- (id)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer {
    PGLog(@"settings: page %@ made with %lu sections", title, (unsigned long)sections.count);
    return %orig(title, intro, withLegacyGlassRow(sections), footer);
}
%end

%ctor {
    %init;
    PGRequireClasses(@[@"SGModPage", @"SGModRow"]);
}
