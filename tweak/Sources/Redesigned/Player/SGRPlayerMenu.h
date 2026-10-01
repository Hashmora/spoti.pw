// The player's ⋯ menu drawn the way the Music app draws its own: a pane of glass grown out of the button,
// a row of up to three tiles across its top (a glyph over its words), then groups of rows split by a
// hairline, each row a glyph at the leading edge with its words and a line under them, a destructive row
// in red, and rows that open in place, onto rows of their own (More) or onto a view of the caller's (Speed
// and pitch). What the rows are and what they do is the caller's -- PlayerMenu.x reads them off Spotify's
// own sheet -- so this only draws them and says which was tapped.
//
// Laid out by hand at a fixed width; taller than maxHeight, the content scrolls inside the pane.
//
// Ownership: the caller keeps the card; the items are kept by the rows made for them.
// Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGRPlayerMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
// A template drawn in the row's colour: an SF Symbol at its own size, anything else fitted to the glyph box.
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL destructive;
@property (nonatomic) BOOL disabled;
// What a tap does, for a plain row.
@property (nonatomic, copy) void (^action)(void);
// A row that opens in place instead: onto `children`, or onto the view `makeExpansion` makes the first
// time it opens, `expansionHeight` tall.
@property (nonatomic, copy) NSArray<SGRPlayerMenuItem *> *children;
@property (nonatomic, copy) UIView *(^makeExpansion)(void);
@property (nonatomic) CGFloat expansionHeight;
// Names the row across -showSections: calls, so a row that was open stays open and -setSubtitle:forKey:
// can find it.
@property (nonatomic, copy) NSString *key;
+ (instancetype)itemWithTitle:(NSString *)title image:(UIImage *)image action:(void (^)(void))action;
@end

@interface SGRPlayerMenuSection : NSObject
@property (nonatomic, copy) NSArray<SGRPlayerMenuItem *> *items;
// Up to three across, each a glyph over its words, as the Music app's Download, Favorite and Share.
@property (nonatomic) BOOL tiles;
+ (instancetype)sectionWithItems:(NSArray<SGRPlayerMenuItem *> *)items tiles:(BOOL)tiles;
@end

// The width the card is laid out at.
extern const CGFloat SGRPlayerMenuWidth;

@interface SGRPlayerMenuCard : UIView
// Content taller than this scrolls. 0 is no limit.
@property (nonatomic) CGFloat maxHeight;
// Called when the content's height changed (a row opened or closed, a subtitle grew a line), from inside
// the animation when there is one, so the owner's new frame animates with it.
@property (nonatomic, copy) void (^sizeChanged)(SGRPlayerMenuCard *card);
// VoiceOver's escape gesture.
@property (nonatomic, copy) void (^onEscape)(void);

- (void)showSections:(NSArray<SGRPlayerMenuSection *> *)sections;
// A spinner in place of the rows, while the caller waits for them.
- (void)showLoading;
// A row's line under its words, in place; nil takes it away.
- (void)setSubtitle:(NSString *)subtitle forKey:(NSString *)key;
// A row's view grew or shrank: its expansionHeight, in place, the card following when it is open.
- (void)setExpansionHeight:(CGFloat)height forKey:(NSString *)key;
// The content's height at SGRPlayerMenuWidth, uncapped.
- (CGFloat)preferredHeight;

// Grown out of `anchor`, a point in the card's own coordinates (where the ⋯ is), or faded in under Reduce
// Motion; and taken away the other way, `completion` called once it is gone.
- (void)growFrom:(CGPoint)anchor;
- (void)shrinkAway:(void (^)(void))completion;
@end
