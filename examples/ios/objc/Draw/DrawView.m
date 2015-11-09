////////////////////////////////////////////////////////////////////////////
//
// Copyright 2014 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "DrawView.h"
#import "DrawPath.h"
#import "SwatchesView.h"
#import "SwatchColor.h"
#import <Realm/Realm.h>

@interface DrawView ()

@property DrawPath *drawPath;
@property NSString *pathID;
@property NSMutableSet *drawnPathIDs;
@property RLMResults *paths;
@property RLMNotificationToken *notificationToken;
@property NSString *vendorID;
@property SwatchesView *swatchesView;
@property SwatchColor *currentColor;
@property CGContextRef onscreenContext;
@property CGLayerRef offscreenLayer;
@property CGContextRef offscreenContext;

@end

@implementation DrawView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.notificationToken = [[RLMRealm defaultRealm] addNotificationBlock:^(NSString *notification, RLMRealm *realm) {
            self.paths = [DrawPath allObjects];
            [self setNeedsDisplay];
        }];
        self.vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        self.paths = [DrawPath allObjects];
        self.swatchesView = [[SwatchesView alloc] initWithFrame:CGRectZero];
        [self addSubview:self.swatchesView];
        
        __block typeof(self) blockSelf = self;
        self.swatchesView.swatchColorChangedHandler = ^{
            blockSelf.currentColor = blockSelf.swatchesView.selectedColor;
        };
        self.drawnPathIDs = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGRect frame = self.swatchesView.frame;
    frame.size.width = CGRectGetWidth(self.frame);
    frame.origin.y = CGRectGetHeight(self.frame) - CGRectGetHeight(frame);
    self.swatchesView.frame = frame;
    [self.swatchesView setNeedsLayout];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSString *colorName = self.currentColor ? self.currentColor.name : @"Black";
    self.drawPath = [[DrawPath alloc] init];
    self.drawPath.color = colorName;
    
    CGPoint point = [[touches anyObject] locationInView:self];
    DrawPoint *drawPoint = [[DrawPoint alloc] init];
    drawPoint.x = point.x;
    drawPoint.y = point.y;
    
    [self.drawPath.points addObject:drawPoint];
    
    RLMRealm *defaultRealm = [RLMRealm defaultRealm];
    [defaultRealm transactionWithBlock:^{
        [defaultRealm addObject:self.drawPath];
    }];
}

- (void)addPoint:(CGPoint)point
{
    [[RLMRealm defaultRealm] transactionWithBlock:^{
        DrawPoint *newPoint = [DrawPoint createInDefaultRealmWithValue:@[@(point.x), @(point.y)]];
        [self.drawPath.points addObject:newPoint];
    }];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint point = [[touches anyObject] locationInView:self];
    [self addPoint:point];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint point = [[touches anyObject] locationInView:self];
    [self addPoint:point];
    [[RLMRealm defaultRealm] transactionWithBlock:^{
        self.drawPath.drawerID = @""; // mark this path as ended
    }];

    self.drawPath = nil;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self touchesEnded:touches withEvent:event];
}

- (void)drawPath:(DrawPath*)path withContext:(CGContextRef)context
{
    SwatchColor *swatchColor = [SwatchColor swatchColorForName:path.color];
    CGContextSetStrokeColorWithColor(context, [swatchColor.color CGColor]);
    CGContextSetLineWidth(context, path.path.lineWidth);
    CGContextAddPath(context, [path.path CGPath]);
    CGContextStrokePath(context);
}

- (void)drawRect:(CGRect)rect
{
    // create offscreen context just once (must be done here)
    if (self.offscreenContext == nil) {
        self.onscreenContext = UIGraphicsGetCurrentContext();

        float contentScaleFactor = [self contentScaleFactor];
        CGSize size = CGSizeMake(self.bounds.size.width * contentScaleFactor, self.bounds.size.height * contentScaleFactor);

        self.offscreenLayer = CGLayerCreateWithContext(self.onscreenContext, size, NULL);
        self.offscreenContext = CGLayerGetContext(self.offscreenLayer);
        CGContextScaleCTM(self.offscreenContext, contentScaleFactor, contentScaleFactor);

        CGContextSetFillColorWithColor(self.offscreenContext, [[UIColor whiteColor] CGColor]);
        CGContextFillRect(self.offscreenContext, self.bounds);
    }

    // draw new "inactive" paths to the offscreen image
    NSMutableArray* activePaths = [[NSMutableArray alloc] init];

    for (DrawPath *path in self.paths) {
        BOOL pathEnded = [path.drawerID isEqualToString:@""];
        if (pathEnded) {
            [self drawPath:path withContext:self.offscreenContext];
        } else {
            [activePaths addObject:path];
        }
    }

    // copy offscreen image to screen
    CGContextDrawLayerInRect(self.onscreenContext, self.bounds, self.offscreenLayer);

    // lastly draw the currently active paths
    for (DrawPath *path in activePaths) {
        [self drawPath:path withContext:self.onscreenContext];
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

@end