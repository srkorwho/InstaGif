#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define MAIN_THREAD(block) dispatch_async(dispatch_get_main_queue(), block)
#define DELAY(seconds, block) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block)

@interface IGGifOverlayManager : NSObject
+ (void)presentOverlay:(NSString *)msg;
+ (void)fetchMeta:(NSString *)mid;
@end

static NSMutableArray *_overlayQueue;

@implementation IGGifOverlayManager

+ (void)presentOverlay:(NSString *)msg {
    MAIN_THREAD(^{
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (!win) return;
        
        if (!_overlayQueue) _overlayQueue = [NSMutableArray new];
        
        UIFont *font = [UIFont boldSystemFontOfSize:12];
        CGFloat maxW = win.frame.size.width - 40;
        
        CGRect rect = [msg boundingRectWithSize:CGSizeMake(maxW, 40)
                                        options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName: font}
                                        context:nil];
        
        CGFloat w = rect.size.width + 30;
        CGFloat h = 30;
        CGFloat yPos = 60;
        
        if (_overlayQueue.count > 0) {
            UIView *last = [_overlayQueue lastObject];
            yPos = last.frame.origin.y + last.frame.size.height + 8;
        }
        
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos, w, h)];
        lbl.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        lbl.textColor = [UIColor whiteColor];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.font = font;
        lbl.text = msg;
        lbl.layer.cornerRadius = 8;
        lbl.clipsToBounds = YES;
        lbl.alpha = 0;

        [win addSubview:lbl];
        [_overlayQueue addObject:lbl];
        
        [UIView animateWithDuration:0.3 animations:^{
            lbl.alpha = 1;
        }];
        
        
        DELAY(5.0, ^{
            [UIView animateWithDuration:0.5 animations:^{
                lbl.alpha = 0;
            } completion:^(BOOL finished) {
                [lbl removeFromSuperview];
                if ([_overlayQueue containsObject:lbl]) {
                    [_overlayQueue removeObject:lbl];
                }
            }];
        });
    });
}

+ (void)fetchMeta:(NSString *)mid {
    if (!mid || [mid length] < 5) return;

    NSString *str = [NSString stringWithFormat:@"https://giphy.com/gifs/%@", mid];
    NSURL *u = [NSURL URLWithString:str];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    [req setHTTPMethod:@"GET"];
    [req setCachePolicy:NSURLRequestReturnCacheDataElseLoad];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (!r) return;     
        NSString *abs = r.URL.absoluteString;
        if ([abs containsString:@"/gifs/"]) {
            NSArray *comp = [abs componentsSeparatedByString:@"/gifs/"];
            if (comp.count > 1) {
                NSString *slug = comp[1];
                NSRange rng = [slug rangeOfString:@"-" options:NSBackwardsSearch];
                if (rng.location != NSNotFound) {
                    NSString *raw = [slug substringToIndex:rng.location];
                    NSString *final = [[raw stringByReplacingOccurrencesOfString:@"-" withString:@" "] capitalizedString];
                    
                    NSString *out = [NSString stringWithFormat:@"GIF: %@", final];
                    [IGGifOverlayManager presentOverlay:out];
                }
            }
        }
    }] resume];
}

@end


%hook IGAPICommentGiphyMediaInfo

static NSMutableArray *_processedIDs;

- (NSString *)gifMediaId {
    NSString *gid = %orig;
    
    if (gid && [gid length] > 5) {
        static dispatch_once_t token;
        dispatch_once(&token, ^{
            _processedIDs = [NSMutableArray new];
        });

        if (![_processedIDs containsObject:gid]) {
            [_processedIDs addObject:gid];
            if (_processedIDs.count > 50) [_processedIDs removeObjectAtIndex:0];
            DELAY(1.0, ^{
                 [IGGifOverlayManager fetchMeta:gid];
            });
        }
    }
    
    return gid;
}

%end

%ctor {
    
    NSLog(@"ctor bro");
}
