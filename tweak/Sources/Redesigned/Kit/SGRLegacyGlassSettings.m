#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "SGRLegacyGlass.h"

// A switch where the device has the private APIs legacy glass leans on (SGLegacyGlassAvailable()); where
// it has not, a row that says so, and panes stay a plain blur.
SGModRow *SGRLegacyGlassRow(void) {
    if (SGLegacyGlassAvailable()) {
        SGModRow *row = SGOptionRow(@"Legacy Liquid Glass", @"An approximation of iOS 26's glass for the navbar and round buttons, on this iOS.", SGKeyLegacyGlass);
        return SGWithSymbol(row, @"cube.transparent");
    }
    NSString *reason = [NSString stringWithFormat:@"This phone (iOS %@) doesn't have the private APIs it leans on, so glass panes stay a plain blur.", UIDevice.currentDevice.systemVersion];
    SGModRow *row = SGStatActionRow(@"Legacy Liquid Glass", nil, ^NSString *{ return @"Unavailable"; }, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Legacy Liquid Glass" message:reason preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    return SGWithSymbol(row, @"cube.transparent");
}
