// Private UIKit the SDK does not declare.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIView (PGPrivate)
- (NSString *)recursiveDescription;
@end

@interface UIViewController (PGPrivate)
- (NSString *)_printHierarchy;
@end
