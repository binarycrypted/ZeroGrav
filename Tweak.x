#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>

@interface SBIconView : UIView
@end

@interface SBIconListView : UIView
@end

static BOOL isZeroGravActive = NO;
static UIDynamicAnimator *animator = nil;
static UIGravityBehavior *gravity = nil;
static CMMotionManager *motionManager = nil;
static NSMutableDictionary *originalCenters = nil;
static __weak UIView *activeContainer = nil;

static SBIconListView* findIconListView(UIView *view) {
    if ([view isKindOfClass:NSClassFromString(@"SBIconListView")] && view.window != nil && !view.hidden && view.alpha > 0.1) {
        CGRect frameInWin = [view convertRect:view.bounds toView:nil];
        if (CGRectIntersectsRect(frameInWin, [UIScreen mainScreen].bounds) && view.subviews.count > 1) {
            return (SBIconListView *)view;
        }
    }
    for (UIView *sub in view.subviews) {
        SBIconListView *found = findIconListView(sub);
        if (found) return found;
    }
    return nil;
}

static void toggleZeroGrav(void) {
    if (!isZeroGravActive) {
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        SBIconListView *listView = findIconListView(keyWin);
        if (!listView) return;

        NSMutableArray *icons = [NSMutableArray array];
        originalCenters = [NSMutableDictionary dictionary];

        for (UIView *sub in listView.subviews) {
            if ([sub isKindOfClass:NSClassFromString(@"SBIconView")]) {
                [icons addObject:sub];
                NSValue *key = [NSValue valueWithPointer:(__bridge const void *)(sub)];
                originalCenters[key] = [NSValue valueWithCGPoint:sub.center];
            }
        }
        if (icons.count == 0) return;

        activeContainer = listView;
        animator = [[UIDynamicAnimator alloc] initWithReferenceView:listView];

        UICollisionBehavior *collision = [[UICollisionBehavior alloc] initWithItems:icons];
        collision.translatesReferenceBoundsIntoBoundary = YES;
        [animator addBehavior:collision];

        UIDynamicItemBehavior *itemBehavior = [[UIDynamicItemBehavior alloc] initWithItems:icons];
        itemBehavior.elasticity = 0.65;
        itemBehavior.friction = 0.05;
        itemBehavior.resistance = 0.15;
        [animator addBehavior:itemBehavior];

        gravity = [[UIGravityBehavior alloc] initWithItems:icons];
        gravity.gravityDirection = CGVectorMake(0.0, 0.0);
        [animator addBehavior:gravity];

        motionManager = [[CMMotionManager alloc] init];
        motionManager.accelerometerUpdateInterval = 0.03;
        [motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMAccelerometerData *data, NSError *error) {
            if (data && gravity) {
                gravity.gravityDirection = CGVectorMake(data.acceleration.x * 1.4, -data.acceleration.y * 1.4);
            }
        }];

        isZeroGravActive = YES;
    } else {
        [motionManager stopAccelerometerUpdates];
        motionManager = nil;
        [animator removeAllBehaviors];
        animator = nil;
        gravity = nil;

        if (activeContainer && originalCenters) {
            [UIView animateWithDuration:0.35 animations:^{
                for (UIView *sub in activeContainer.subviews) {
                    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)(sub)];
                    NSValue *centerVal = originalCenters[key];
                    if (centerVal) {
                        sub.transform = CGAffineTransformIdentity;
                        sub.center = [centerVal CGPointValue];
                    }
                }
            }];
        }
        isZeroGravActive = NO;
    }
}

%hook UIWindow
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    %orig;
    if (motion == UIEventSubtypeMotionShake) {
        toggleZeroGrav();
    }
}
%end
