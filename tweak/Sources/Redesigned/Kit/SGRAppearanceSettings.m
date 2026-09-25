#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccent.h"

// Going back to Spotify's green is offered only once a colour of the mod's is set, so a stray tap
// cannot wipe it.
static void chooseAccent(void) {
    if (!SGRAccentColor()) {
        SGRPickAccent();
        return;
    }
    UIViewController *top = SGTopController();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Accent colour" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Pick a colour" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRPickAccent(); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Spotify's green" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { SGSetInt(SGRKeyAccent, -1); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = top.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [top presentViewController:sheet animated:YES completion:nil];
}

// Below a capable device the row is a switch for the redesign's navbar and round buttons' glass
// (Core/SGGlass.m); above it, or off a device that cannot do it, it reads out why there is nothing
// to switch (SGLegacyGlassAvailable(), Core/SGLegacyGlass.h).
static SGModRow *legacyGlassRow(void) {
    if (SGLegacyGlassAvailable()) {
        SGModRow *row = SGOptionRow(@"Legacy Liquid Glass", @"An approximation of iOS 26's glass for the navbar and round buttons, on this iOS.", SGKeyLegacyGlass);
        return SGWithSymbol(row, @"cube.transparent");
    }
    BOOL modern = NO;
    if (@available(iOS 26.0, *)) modern = YES;
    NSString *status = modern ? @"Not needed" : @"Unavailable";
    NSString *reason = modern
        ? @"Not needed here: this phone already draws real Liquid Glass."
        : [NSString stringWithFormat:@"This phone (iOS %@) doesn't have the private APIs it leans on, so glass panes stay a plain blur.", UIDevice.currentDevice.systemVersion];
    SGModRow *row = SGStatActionRow(@"Legacy Liquid Glass", nil, ^NSString *{ return status; }, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Legacy Liquid Glass" message:reason preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    return SGWithSymbol(row, @"cube.transparent");
}

// The redesign's rows of the Appearance card (App/Pages.m). AMOLED has no row: the redesign is always black.
NSArray<SGModRow *> *SGRAppearanceRows(void) {
    return @[
        SGWithSymbol(SGStatActionRow(@"Accent colour", nil, ^NSString *{ return SGRAccentLabel(); }, ^{ chooseAccent(); }), @"paintpalette"),
        legacyGlassRow(),
    ];
}
