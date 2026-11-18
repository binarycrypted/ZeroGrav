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
static NSMutableArray *floatingIcons = nil;
static NSMutableDictionary *originalParents = nil;
static NSMutableDictionary *originalFrames = nil;
static NSTimeInterval lastShakeTime = 0;

static void collectVisibleIcons(UIView *view, NSMutableArray *result) {
    if (view.hidden || view.alpha < 0.1) return;
    if ([view isKindOfClass:NSClassFromString(@"SBIconView")]) {
        CGRect frameInWin = [view convertRect:view.bounds toView:nil];
        if (CGRectIntersectsRect(frameInWin, [UIScreen mainScreen].bounds)) {
            [result addObject:view];
        }
        return;
    }
    for (UIView *sub in [view.subviews copy]) {
        collectVisibleIcons(sub, result);
    }
}

static void toggleZeroGrav(void) {
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.hidden && w.alpha > 0.1 && [NSStringFromClass([w class]) containsString:@"HomeScreen"]) {
            keyWin = w;
            break;
        }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
    if (!keyWin) return;

    if (!isZeroGravActive) {
        NSMutableArray *icons = [NSMutableArray array];
        collectVisibleIcons(keyWin, icons);
        if (icons.count == 0) return;

        floatingIcons = icons;
        originalParents = [NSMutableDictionary dictionary];
        originalFrames = [NSMutableDictionary dictionary];

        for (UIView *icon in icons) {
            NSValue *key = [NSValue valueWithPointer:(__bridge const void *)(icon)];
            if (icon.superview) {
                originalParents[key] = icon.superview;
                originalFrames[key] = [NSValue valueWithCGRect:icon.frame];
                CGRect winFrame = [icon convertRect:icon.bounds toView:keyWin];
                icon.translatesAutoresizingMaskIntoConstraints = YES;
                [icon removeFromSuperview];
                icon.frame = winFrame;
                [keyWin addSubview:icon];
            }
        }

        isZeroGravActive = YES;
        animator = [[UIDynamicAnimator alloc] initWithReferenceView:keyWin];

        UICollisionBehavior *collision = [[UICollisionBehavior alloc] initWithItems:icons];
        collision.translatesReferenceBoundsIntoBoundary = YES;
        [animator addBehavior:collision];

        UIDynamicItemBehavior *itemBehavior = [[UIDynamicItemBehavior alloc] initWithItems:icons];
        itemBehavior.elasticity = 0.72;
        itemBehavior.friction = 0.02;
        itemBehavior.resistance = 0.04;
        [animator addBehavior:itemBehavior];

        gravity = [[UIGravityBehavior alloc] initWithItems:icons];
        gravity.gravityDirection = CGVectorMake(0.0, 1.2);
        [animator addBehavior:gravity];

        for (UIView *icon in icons) {
            UIPushBehavior *push = [[UIPushBehavior alloc] initWithItems:@[icon] mode:UIPushBehaviorModeInstantaneous];
            double rx = ((arc4random_uniform(100) / 50.0) - 1.0) * 0.4;
            double ry = -((arc4random_uniform(100) / 100.0) * 0.5);
            push.pushDirection = CGVectorMake(rx, ry);
            [animator addBehavior:push];
        }
    } else {
        isZeroGravActive = NO;
        [animator removeAllBehaviors];
        animator = nil;
        gravity = nil;

        if (floatingIcons && originalParents && originalFrames) {
            [UIView animateWithDuration:0.35 animations:^{
                for (UIView *icon in floatingIcons) {
                    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)(icon)];
                    UIView *parent = originalParents[key];
                    NSValue *frameVal = originalFrames[key];
                    if (parent && frameVal) {
                        icon.transform = CGAffineTransformIdentity;
                        [icon removeFromSuperview];
                        icon.frame = [frameVal CGRectValue];
                        [parent addSubview:icon];
                    }
                }
            } completion:^(BOOL finished) {
                for (UIView *parent in [originalParents allValues]) {
                    if ([parent respondsToSelector:@selector(layoutIconsNow)]) {
                        [(SBIconListView *)parent layoutIconsNow];
                    }
                }
                floatingIcons = nil;
                originalParents = nil;
                originalFrames = nil;
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
            gravity.gravityDirection = CGVectorMake(x * 2.5, -y * 2.5);
        }
    }];
}
%end

%hook SBIconListView
- (void)layoutSubviews {
    if (isZeroGravActive) return;
    %orig;
}

- (void)layoutIconsNow {
    if (isZeroGravActive) return;
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
