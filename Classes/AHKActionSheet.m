//
//  AHKActionSheet.m
//  AHKActionSheetExample
//
//  Created by Arkadiusz on 08-04-14.
//  Copyright (c) 2014 Arkadiusz Holko. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "AHKActionSheet.h"
#import "AHKActionSheetViewController.h"
#import "UIView+Snapshots.h"
#import "UIImage+AHKAdditions.h"
#import "AHKActionSheetTableViewCell.h"

// Length of the range at which the blurred background is being hidden when the user scrolls the tableView to the top.
static CGFloat kBlurFadeRangeSize = 200.0f;
static NSString * const kCellIdentifier = @"Cell";
// How much user has to scroll beyond the top of the tableView for the view to dismiss automatically.
static CGFloat autoDismissOffset = 80.0f;
// Offset at which there's a check if the user is flicking the tableView down.
static CGFloat flickDownHandlingOffset = 20.0f;
static CGFloat flickDownMinVelocity = 2000.0f;
// How much free space to leave at the top (above the tableView's contents) when there's a lot of elements. It makes this control look similar to the UIActionSheet.
static CGFloat topSpaceMarginFraction = 0.0f;


/// Used for storing button configuration.
@interface AHKActionSheetItem : NSObject
@property (copy, nonatomic) NSString *title;
@property (strong, nonatomic) UIImage *image;
@property (nonatomic) AHKActionSheetButtonType type;
@property (strong, nonatomic) AHKActionSheetHandler handler;
@end

@implementation AHKActionSheetItem
@end



@interface AHKActionSheet() <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) NSMutableArray *items;
@property (strong, nonatomic) UIView *backgroundView;
@property (strong, nonatomic) UIView *blurredBackgroundView;
@property (weak, nonatomic) UITableView *tableView;
@property (strong, nonatomic) AHKActionSheetViewController *actionSheetVC;

@property (assign, nonatomic) BOOL isAnimatingAPresentationOrDismissal;
@property (assign, nonatomic) BOOL isDismissing;
@property (assign, nonatomic) BOOL viewHasAppeared;
@property (assign, nonatomic) BOOL isPresented;
@property (assign, nonatomic) BOOL statusBarHiddenPriorToPresentation;

@end

@implementation AHKActionSheet

#pragma mark - Init

+ (void)initialize
{
    if (self != [AHKActionSheet class]) {
        return;
    }

    AHKActionSheet *appearance = [self appearance];
    [appearance setBlurRadius:16.0f];
    [appearance setBlurTintColor:[UIColor colorWithWhite:1.0f alpha:0.5f]];
    [appearance setBlurSaturationDeltaFactor:1.8f];
    [appearance setButtonHeight:60.0f];
    [appearance setCancelButtonHeight:44.0f];
    [appearance setDestructiveButtonBackgroundColor:[UIColor clearColor]];
    [appearance setAutomaticallyTintButtonImages:@YES];
    [appearance setSelectedBackgroundColor:[UIColor colorWithWhite:0.1 alpha:0.2]];
    [appearance setCancelButtonTextAttributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:17.0f],
                                                 NSForegroundColorAttributeName : [UIColor darkGrayColor] }];
    [appearance setButtonTextAttributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:17.0f]}];
    [appearance setDestructiveButtonTextAttributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:17.0f],
                                                      NSForegroundColorAttributeName : [UIColor redColor] }];
    [appearance setTitleTextAttributes:@{ NSFontAttributeName : [UIFont systemFontOfSize:14.0f],
                                                      NSForegroundColorAttributeName : [UIColor grayColor] }];
    [appearance setPresentationDuration:@0.3];
    [appearance setPresentationSpringVelocity:@5];
    [appearance setPresentationSpringDamping:@10];
    [appearance setDismissalDuration:@0.3];
    [appearance setDismissalDurationFlick:@0.2];
}

- (instancetype)initWithTitle:(NSString *)title
{
    self = [super init];

    if (self) {
        _title = title;
        _cancelButtonTitle = @"Cancel";
        
    }

    return self;
}

- (instancetype)init
{
    return [self initWithTitle:nil];
}

- (void)dealloc
{
    self.tableView.dataSource = nil;
    self.tableView.delegate = nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return self.items.count;
    } else if (section == 1) {
        return 1;
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    AHKActionSheetTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    if (self.selectedBackgroundColor && ![cell.selectedBackgroundView.backgroundColor isEqual:self.selectedBackgroundColor]) {
        cell.selectedBackgroundView = [[UIView alloc] init];
        cell.selectedBackgroundView.backgroundColor = self.selectedBackgroundColor;
    }

    if (indexPath.section == 0) {
        AHKActionSheetItem *item = self.items[indexPath.row];
        
        NSDictionary *attributes = item.type == AHKActionSheetButtonTypeDefault ? self.buttonTextAttributes : self.destructiveButtonTextAttributes;
        NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:item.title attributes:attributes];
        cell.textLabel.attributedText = attrTitle;
        cell.textLabel.textAlignment = [self.buttonTextCenteringEnabled boolValue] ? NSTextAlignmentCenter : NSTextAlignmentLeft;
        
        cell.backgroundColor = item.type == AHKActionSheetButtonTypeDefault ? [UIColor clearColor] : self.destructiveButtonBackgroundColor;
        
        // Use image with template mode with color the same as the text (when enabled).
        cell.imageView.image = [self.automaticallyTintButtonImages boolValue] ? [item.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : item.image;
        cell.imageView.tintColor = attributes[NSForegroundColorAttributeName] ? attributes[NSForegroundColorAttributeName] : [UIColor blackColor];
        
        //If we have a separator color, here's where we make it
        if (!cell.bottomStroke) {
            cell.bottomStroke = [[UIView alloc] initWithFrame:CGRectMake(0, cell.frame.size.height, cell.frame.size.width, 0.5)];
            [cell.contentView addSubview:cell.bottomStroke];
        }
        cell.bottomStroke.backgroundColor = self.separatorColor;

        
    } else if (indexPath.section == 1) {
        NSDictionary *attrs = self.cancelButtonTextAttributes;
        NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:self.cancelButtonTitle attributes:attrs];
        cell.textLabel.attributedText = attrTitle;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.bottomStroke.backgroundColor = [UIColor clearColor];
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        AHKActionSheetItem *item = self.items[indexPath.row];
        [self dismissAnimated:YES duration:self.dismissalDuration.floatValue completion:item.handler];
    } else if (indexPath.section == 1) {
        [self dismissAnimated:YES duration:self.dismissalDuration.floatValue completion:self.cancelHandler];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        return self.buttonHeight;
    } else {
        return self.cancelButtonHeight;
    }

}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self fadeBlursOnScrollToTop];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    CGPoint scrollVelocity = [scrollView.panGestureRecognizer velocityInView:self];

    BOOL viewWasFlickedDown = scrollVelocity.y > flickDownMinVelocity && scrollView.contentOffset.y < -self.tableView.contentInset.top - flickDownHandlingOffset;
    BOOL shouldSlideDown = scrollView.contentOffset.y < -self.tableView.contentInset.top - autoDismissOffset;
    if (viewWasFlickedDown) {
        // use a shorter duration for a flick down animation
        [self dismissAnimated:YES duration:self.dismissalDurationFlick.floatValue completion:self.cancelHandler];
    } else if (shouldSlideDown) {
        [self dismissAnimated:YES duration:self.dismissalDuration.floatValue completion:self.cancelHandler];
    }
}

#pragma mark - Properties

- (NSMutableArray *)items
{
    if (!_items) {
        _items = [NSMutableArray array];
    }

    return _items;
}

#pragma mark - Actions

- (void)tableViewTapped:(UITapGestureRecognizer *)tapGesture
{
    CGPoint tapGesturePoint = [tapGesture locationInView:nil];
    //Is the tap inside the tableview?
    __block BOOL shouldDismiss = YES;
    [self.tableView.visibleCells enumerateObjectsUsingBlock:^(UITableViewCell *cell, NSUInteger idx, BOOL *stop) {
        CGRect cellRect = [self.tableView convertRect:cell.frame toView:nil];
        if (CGRectContainsPoint(cellRect, tapGesturePoint)) {
            shouldDismiss = NO;
            NSIndexPath *idxPath = [self.tableView indexPathForCell:cell];
            [self.tableView selectRowAtIndexPath:idxPath animated:NO scrollPosition:UITableViewScrollPositionNone];
            [self tableView:self.tableView didSelectRowAtIndexPath:idxPath];
        }
    }];
    if (shouldDismiss) {
        [self dismissAnimated:YES];
    }
}

#pragma mark - Public

- (void)addButtonWithTitle:(NSString *)title type:(AHKActionSheetButtonType)type handler:(AHKActionSheetHandler)handler
{
    [self addButtonWithTitle:title image:nil type:type handler:handler];
}

- (void)addButtonWithTitle:(NSString *)title image:(UIImage *)image type:(AHKActionSheetButtonType)type handler:(AHKActionSheetHandler)handler
{
    AHKActionSheetItem *item = [[AHKActionSheetItem alloc] init];
    item.title = title;
    item.image = image;
    item.type = type;
    item.handler = handler;
    [self.items addObject:item];
}

- (void)showFromViewController:(UIViewController *)viewController
{
	NSAssert([self.items count] > 0, @"Please add some buttons before calling -show.");
    
    BOOL actionSheetIsVisible = !!self.actionSheetVC; // action sheet is visible iff it's associated with a viewController
    if (actionSheetIsVisible) {
        return;
   }
    
    self.bounds = [UIScreen mainScreen].bounds;
    
	_statusBarHiddenPriorToPresentation = [UIApplication sharedApplication].statusBarHidden;
	[self setIsAnimatingAPresentationOrDismissal:YES];
	[self setUserInteractionEnabled:NO];
	self.backgroundView = [self snapshotFromParentmostViewController:viewController];
	self.blurredBackgroundView = [self blurredSnapshotFromParentmostViewController:viewController];
	self.blurredBackgroundView.alpha = 0;
	[self.backgroundView addSubview:self.blurredBackgroundView];
    
	[self insertSubview:self.backgroundView atIndex:0];
    
    _actionSheetVC = [[AHKActionSheetViewController alloc] initWithNibName:nil bundle:nil];
    _actionSheetVC.actionSheet = self;
    
	[self setUpTableView];
    
    CGFloat tableContentHeight = ([self.items count] +1) * self.buttonHeight + CGRectGetHeight(self.tableView.tableHeaderView.frame);
    
    CGFloat topInset;
    BOOL buttonsFitInWithoutScrolling = tableContentHeight < CGRectGetHeight(self.tableView.frame) * (1.0 - topSpaceMarginFraction);
    if (buttonsFitInWithoutScrolling) {
        // show all buttons if there isn't many
        topInset = CGRectGetHeight(self.tableView.frame) - tableContentHeight;
    } else {
        // leave an empty space on the top to make the control look similar to UIActionSheet
        topInset = round(CGRectGetHeight(self.tableView.frame) * topSpaceMarginFraction);
    }
    self.tableView.contentInset = UIEdgeInsetsMake(topInset, 0, 0, 0);

    CGRect tableViewFrameOriginal = self.tableView.frame;
    CGRect tableViewFrameOffset = tableViewFrameOriginal;
    tableViewFrameOffset.origin.y += topInset;
    
    self.tableView.frame = tableViewFrameOffset;
    
    [self.tableView.visibleCells enumerateObjectsUsingBlock:^(AHKActionSheetTableViewCell *cell, NSUInteger idx, BOOL *stop) {
        cell.bottomStroke.alpha = 0.0f;
    }];
    
	[viewController presentViewController:_actionSheetVC animated:NO completion:^{
        [UIView animateWithDuration:self.presentationDuration.floatValue
                              delay:0
             usingSpringWithDamping:self.presentationSpringDamping.floatValue
              initialSpringVelocity:self.presentationSpringVelocity.floatValue
                            options:0
                         animations:^{
                             self.tableView.frame = tableViewFrameOriginal;
                             self.blurredBackgroundView.alpha = 1.0f;
                             
                             [self.tableView.visibleCells enumerateObjectsUsingBlock:^(AHKActionSheetTableViewCell *cell, NSUInteger idx, BOOL *stop) {
                                 cell.bottomStroke.alpha = 1.0f;
                             }];
                             
                         } completion:^(BOOL finished) {
                             self.userInteractionEnabled = YES;
                         }];
    }];
    
    
    
}

- (void)dismissAnimated:(BOOL)animated
{
	[self dismissAnimated:animated duration:self.dismissalDuration.floatValue completion:self.cancelHandler];
}




#pragma mark - Private

#pragma mark Snapshots

- (UIView *)snapshotFromParentmostViewController:(UIViewController *)viewController {
    
	UIViewController *presentingViewController = viewController.view.window.rootViewController;
	while (presentingViewController.presentedViewController) presentingViewController = presentingViewController.presentedViewController;
	UIView *snapshot = [presentingViewController.view snapshotViewAfterScreenUpdates:YES];
	[snapshot setClipsToBounds:NO];
	return snapshot;
}

- (UIView *)blurredSnapshotFromParentmostViewController:(UIViewController *)viewController {
    
	UIViewController *presentingViewController = viewController.view.window.rootViewController;
	while (presentingViewController.presentedViewController) presentingViewController = presentingViewController.presentedViewController;
    
	CGFloat outerBleed = 0.0f;
	CGRect contextBounds = CGRectInset(presentingViewController.view.bounds, -outerBleed, -outerBleed);
	UIGraphicsBeginImageContextWithOptions(contextBounds.size, YES, 0);
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextConcatCTM(context, CGAffineTransformMakeTranslation(outerBleed, outerBleed));
	[presentingViewController.view.layer renderInContext:context];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    
	UIGraphicsEndImageContext();
    
	UIImage *blurredImage = [image AHKapplyBlurWithRadius:self.blurRadius
												tintColor:self.blurTintColor
									saturationDeltaFactor:1.0f
												maskImage:nil];
    
	UIImageView *imageView = [[UIImageView alloc] initWithFrame:contextBounds];
	[imageView setImage:blurredImage];
	[imageView setAutoresizingMask:UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth];
	[imageView setBackgroundColor:[UIColor blackColor]];
    
	return imageView;
}

- (void)dismissAnimated:(BOOL)animated duration:(CGFloat)duration completion:(AHKActionSheetHandler)completionHandler
{
    
    [self setUserInteractionEnabled:NO];
    self.isAnimatingAPresentationOrDismissal = YES;
    self.isDismissing = YES;
    
    
    // delegate isn't needed anymore because tableView will be hidden (and we don't want delegate methods to be called now)
    self.tableView.delegate = nil;
    self.tableView.userInteractionEnabled = NO;
    // keep the table from scrolling back up
    self.tableView.contentInset = UIEdgeInsetsMake(-self.tableView.contentOffset.y, 0, 0, 0);

    void(^tearDownView)(void) = ^(void) {
        // remove the views because it's easiest to just recreate them if the action sheet is shown again
        for (UIView *view in @[self.tableView, self.blurredBackgroundView, self.backgroundView]) {
            [view removeFromSuperview];
        }
        
        // Needed if dismissing from a different orientation then the one we started with
        [self.actionSheetVC.presentingViewController dismissViewControllerAnimated:NO completion:^{
            if (completionHandler) {
                completionHandler(self);
            }
        }];
    };
    
    if (animated) {
        // animate sliding down tableView and cancelButton.
        
        [UIView animateWithDuration:duration
                              delay:0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
                             self.blurredBackgroundView.alpha = 0.0f;
                             
                             // Shortest shift of position sufficient to hide all tableView contents below the bottom margin.
                             // contentInset isn't used here (unlike in -show) because it caused weird problems with animations in some cases.
                             CGFloat slideDownMinOffset = MIN(CGRectGetHeight(self.frame) + self.tableView.contentOffset.y, CGRectGetHeight(self.frame));
                             self.tableView.transform = CGAffineTransformMakeTranslation(0, slideDownMinOffset);
                             
                             [self.tableView.visibleCells enumerateObjectsUsingBlock:^(AHKActionSheetTableViewCell *cell, NSUInteger idx, BOOL *stop) {
                                 cell.bottomStroke.alpha = 0.0f;
                             }];
                         } completion:^(BOOL finished) {
                             tearDownView();
                         }];
    } else {
        tearDownView();
    }
}

- (void)setUpTableView
{
    CGRect statusBarViewRect = [self convertRect:[UIApplication sharedApplication].statusBarFrame fromView:nil];
    CGFloat statusBarHeight = CGRectGetHeight(statusBarViewRect);
    CGRect frame = CGRectMake(0,
                              statusBarHeight,
                              CGRectGetWidth(self.bounds),
                              CGRectGetHeight(self.bounds) - statusBarHeight);

    UITableView *tableView = [[UITableView alloc] initWithFrame:frame];
    tableView.backgroundColor = [UIColor clearColor];
    tableView.showsVerticalScrollIndicator = NO;
    tableView.separatorInset = UIEdgeInsetsZero;
    tableView.separatorColor = [UIColor clearColor];

    tableView.delegate = self;
    tableView.dataSource = self;
    [tableView registerClass:[AHKActionSheetTableViewCell class] forCellReuseIdentifier:kCellIdentifier];
    [self insertSubview:tableView aboveSubview:self.blurredBackgroundView];
    // move the content below the screen, ready to be animated in -show
    tableView.contentInset = UIEdgeInsetsMake(CGRectGetHeight(self.bounds), 0, 0, 0);

    self.tableView = tableView;
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tableViewTapped:)];
    [self.tableView addGestureRecognizer:tapGesture];

    [self setUpTableViewHeader];
}

- (void)setUpTableViewHeader
{
    if (self.title) {
        // paddings similar to those in the UITableViewCell
        
        static CGFloat leftRightPadding = 15.0f;
        static CGFloat topBottomPadding = 8.0f;
        CGFloat labelWidth = CGRectGetWidth(self.bounds) - 2*leftRightPadding;

        NSAttributedString *attrText = [[NSAttributedString alloc] initWithString:self.title attributes:self.titleTextAttributes];
        
        // create a label and calculate its size
        UILabel *label = [[UILabel alloc] init];
        label.textAlignment = [self.titleTextCenteringEnabled boolValue] ? NSTextAlignmentCenter : NSTextAlignmentLeft;
        label.numberOfLines = 0;
        [label setAttributedText:attrText];
        CGSize labelSize = [label sizeThatFits:CGSizeMake(labelWidth, MAXFLOAT)];
        label.frame = CGRectMake(leftRightPadding, topBottomPadding, labelWidth, labelSize.height);

        // create and add a header consisting of the label
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.bounds), labelSize.height + 2*topBottomPadding)];
        [headerView addSubview:label];
        self.tableView.tableHeaderView = headerView;

    } else if (self.headerView) {
        self.tableView.tableHeaderView = self.headerView;
    }

    // add a separator between the tableHeaderView and a first row (technically at the bottom of the tableHeaderView)
    if (self.tableView.tableHeaderView && self.tableView.separatorStyle != UITableViewCellSeparatorStyleNone) {
        CGFloat separatorHeight = 1.0f / [UIScreen mainScreen].scale;
        CGRect separatorFrame = CGRectMake(0,
                                           CGRectGetHeight(self.tableView.tableHeaderView.frame) - separatorHeight,
                                           CGRectGetWidth(self.tableView.tableHeaderView.frame),
                                           separatorHeight);
        UIView *separator = [[UIView alloc] initWithFrame:separatorFrame];
        separator.backgroundColor = self.tableView.separatorColor;
        [self.tableView.tableHeaderView addSubview:separator];
    }
}

- (void)fadeBlursOnScrollToTop
{
    if (self.tableView.isDragging || self.tableView.isDecelerating) {
        CGFloat alphaWithoutBounds = 1.0f - ( -(self.tableView.contentInset.top + self.tableView.contentOffset.y) / kBlurFadeRangeSize);
        // limit alpha to the interval [0, 1]
        CGFloat alpha = MAX(MIN(alphaWithoutBounds, 1.0f), 0.0f);
        self.blurredBackgroundView.alpha = alpha;
//        self.cancelButtonShadowView.alpha = alpha;
    }
}

@end
