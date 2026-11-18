#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>

@interface SBIconView : UIView
@end

@interface SBIconListView : UIView
- (void)layoutIconsNow;
@end

static BOOL isZeroGravActive = NO;
static UIDynamicAnimator *animator = nil;
static UIGravityBehavior *gravity = nil;
static CMMotionManager *motionManager = nil;
static NSMutableDictionary *originalCenters = nil;
static __weak SBIconListView *activeContainer = nil;
static NSTimeInterval lastShakeTime = 0;

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
        UIWindow *keyWin = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w.hidden && w.alpha > 0.1 && findIconListView(w) != nil) {
                keyWin = w;
                break;
            }
        }
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
        isZeroGravActive = YES;

        animator = [[UIDynamicAnimator alloc] initWithReferenceView:listView];

        UICollisionBehavior *collision = [[UICollisionBehavior alloc] initWithItems:icons];
        collision.translatesReferenceBoundsIntoBoundary = YES;
        [animator addBehavior:collision];

        UIDynamicItemBehavior *itemBehavior = [[UIDynamicItemBehavior alloc] initWithItems:icons];
        itemBehavior.elasticity = 0.75;
        itemBehavior.friction = 0.02;
        itemBehavior.resistance = 0.05;
        [animator addBehavior:itemBehavior];

        gravity = [[UIGravityBehavior alloc] initWithItems:icons];
        gravity.gravityDirection = CGVectorMake(0.0, 0.2);
        [animator addBehavior:gravity];

        UIPushBehavior *push = [[UIPushBehavior alloc] initWithItems:icons mode:UIPushBehaviorModeInstantaneous];
        push.pushDirection = CGVectorMake(0.0, -0.6);
        [animator addBehavior:push];
    } else {
        isZeroGravActive = NO;
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
            } completion:^(BOOL finished) {
                [activeContainer layoutIconsNow];
                activeContainer = nil;
            }];
        }
    }
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    motionManager = [[CMMotionManager alloc] init];
    motionManager.accelerometerUpdateInterval = 0.02;
    [motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMAccelerometerData *data, NSError *error) {
        if (!data) return;
        double x = data.acceleration.x;
        double y = data.acceleration.y;
        double z = data.acceleration.z;
        double magnitude = sqrt(x*x + y*y + z*z);

        if (magnitude > 2.2) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (now - lastShakeTime > 1.2) {
                lastShakeTime = now;
                toggleZeroGrav();
            }
        }

        if (isZeroGravActive && gravity) {
            gravity.gravityDirection = CGVectorMake(x * 2.2, -y * 2.2);
        }
    }];
}
%end

%hook SBIconListView
- (void)layoutSubviews {
    if (isZeroGravActive && self == activeContainer) return;
    %orig;
}

- (void)layoutIconsNow {
    if (isZeroGravActive && self == activeContainer) return;
    %orig;
}

- (void)didMoveToWindow {
    %orig;
    BOOL hasDoubleTap = NO;
    for (UIGestureRecognizer *gr in self.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]] && ((UITapGestureRecognizer *)gr).numberOfTapsRequired == 2) {
            hasDoubleTap = YES;
            break;
        }
    }
    if (!hasDoubleTap) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(zg_handleDoubleTap)];
        tap.numberOfTapsRequired = 2;
        tap.cancelsTouchesInView = NO;
        [self addGestureRecognizer:tap];
    }
}

%new
- (void)zg_handleDoubleTap {
    toggleZeroGrav();
}
%end
