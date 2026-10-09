// The saved composition of the redesign's bar, as NSUserDefaults property lists, apart from the native look's.
#import "Navbar.h"
#import "Shared/Navigation/Links.h"
#import "Core/PGCore.h"
#import "Redesigned/Kit/PGRForeign.h"

NSString *const PGRNavbarID = @"id";
NSString *const PGRNavbarTitle = @"title";
NSString *const PGRNavbarURI = @"uri";
NSString *const PGRNavbarIcon = @"icon";
NSString *const PGRNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"pureglass.redesign.navbar.layout";
static NSString *const kNavbarStock = @"pureglass.redesign.navbar.stock";

#pragma mark - the other tweak's page

// spoti.pw's Navbar page writes the same four things as this tweak's keys above, under its own prefix
// (<prefix>.redesign.navbar, .layout, .stock, .hideLabels). The prefix is not known here, so it is read off
// the keys that exist: the first one of each that does not start with this tweak's. Until the page has
// written one (nothing changed yet) the lookup is repeated once a second at most.
static NSMutableDictionary<NSString *, NSString *> *pg_foreign;
static CFTimeInterval pg_foreignScanned;

static NSArray<NSString *> *foreignSuffixes(void) {
    return @[@".redesign.navbar.layout", @".redesign.navbar.stock", @".redesign.navbar.hideLabels", @".redesign.navbar"];
}

static void scanForeign(void) {
    pg_foreign = [NSMutableDictionary dictionary];
    pg_foreignScanned = CACurrentMediaTime();
    for (NSString *key in NSUserDefaults.standardUserDefaults.dictionaryRepresentation) {
        if ([key hasPrefix:@"pureglass."]) continue;
        for (NSString *suffix in foreignSuffixes()) {
            if ([key hasSuffix:suffix] && !pg_foreign[suffix]) pg_foreign[suffix] = key;
        }
    }
    static BOOL logged;
    if (!logged && pg_foreign.count) {
        logged = YES;
        PGLog(@"navbar: the Navbar page of the other tweak writes %@", pg_foreign.allValues);
    }
}

// The key a value is read from: the other tweak's when it has written one, else this tweak's own.
static NSString *keyFor(NSString *own, NSString *suffix) {
    if (!PGRForeignTweakPresent()) return own;
    if (!pg_foreign || (!pg_foreign[suffix] && CACurrentMediaTime() - pg_foreignScanned > 1)) scanForeign();
    return pg_foreign[suffix] ?: own;
}

BOOL PGRNavbarEnabled(void) {
    return PGEnabled(keyFor(PGRKeyNavbar, @".redesign.navbar"));
}

BOOL PGRNavbarLabelsHidden(void) {
    return PGHidden(keyFor(PGRKeyNavbarHideLabels, @".redesign.navbar.hideLabels"));
}

#pragma mark - this tweak's own

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *PGRNavbarLayout(void) {
    return listOfKind(keyFor(kNavbarLayout, @".redesign.navbar.layout"), NSDictionary.class);
}

void PGRSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

NSArray<NSString *> *PGRNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void PGRSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}

// The other tweak's page lists Spotify's tabs from its own copy of this list, which its bar fills in. With its
// bar out of the row it may never have, and the page would have nothing to rename or hide. Its key is this
// one's with its prefix, which is read off the layout key it writes (or the other two).
void PGRMirrorNavbarStock(NSArray<NSString *> *stock) {
    if (!stock.count || !PGRForeignTweakPresent()) return;
    static NSArray<NSString *> *last;
    static CFTimeInterval at;
    if ([stock isEqualToArray:last] && CACurrentMediaTime() - at < 3) return;
    last = [stock copy];
    at = CACurrentMediaTime();
    keyFor(PGRKeyNavbar, @".redesign.navbar.layout");   // looks for the keys if they have not been looked for
    for (NSString *suffix in @[@".redesign.navbar.layout", @".redesign.navbar.hideLabels", @".redesign.navbar"]) {
        NSString *key = pg_foreign[suffix];
        if (!key) continue;
        NSString *stockKey = [[key substringToIndex:key.length - suffix.length] stringByAppendingString:@".redesign.navbar.stock"];
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        if (![[store arrayForKey:stockKey] isEqualToArray:stock]) [store setObject:stock forKey:stockKey];
        return;
    }
}

NSURL *PGRNavbarTabURL(NSString *uri) {
    NSURL *url = PGSpotifyURIFromText(uri);
    if ([url.absoluteString isEqualToString:@"spotify:collection:playlists"]) return [NSURL URLWithString:@"spotify:playlists"];
    return url;
}
