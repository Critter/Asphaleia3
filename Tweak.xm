#import <UIKit/UIKit.h>
#import "PKGlyphView.h"
#import "BTTouchIDController.h"
#import "ASCommon.h"
#import "SBIconView.h"
#import "SBIcon.h"
#import "SBIconController.h"
#import "PreferencesHandler.h"
#import "substrate.h"
#import "UIImage+ImageEffects.h"
#import "SBUIController.h"
#import "SBDisplayLayout.h"
#import "SBDisplayItem.h"
#import "SBAppSwitcherIconController.h"
#import "SBAppSwitcherSnapshotView.h"
#import "CAFilter.h"
#import "SBApplication.h"
#import "SBApplicationIcon.h"
#import "SpringBoard.h"
#import "SBSearchViewController.h"
#import "SBControlCenterController.h"
#import <AudioToolbox/AudioServices.h>
#import "ASActivatorListener.h"
#import "ASControlPanel.h"
#import "NSTimer+Blocks.h"
#import "ASPasscodeHandler.h"
#import "ASTouchWindow.h"
#import "SBIconLabelView.h"
#import "SBIconLabelImageParameters.h"
#import "SBBannerContainerViewController.h"
#import "BBBulletin.h"
#import "SBApplicationController.h"

#define kBundlePath @"/Library/Application Support/Asphaleia/AsphaleiaAssets.bundle"

PKGlyphView *fingerglyph;
SBIconView *currentIconView;
SBAppSwitcherIconController *iconController;
BTTouchIDController *iconTouchIDController;
NSString *temporarilyUnlockedAppBundleID;
NSTimer *currentTempUnlockTimer;
NSTimer *currentTempGlobalDisableTimer;
ASTouchWindow *anywhereTouchWindow;
BOOL appAlreadyAuthenticated;

%hook SBIconController

-(void)iconTapped:(SBIconView *)iconView {
	if ([ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled) {
		[[%c(SBIconController) sharedInstance] resetAsphaleiaIconView];
		%orig;
		return;
	}

	if (fingerglyph && currentIconView) {
		[iconView setHighlighted:NO];
		if ([iconView isEqual:currentIconView]) {
			[[ASPasscodeHandler sharedInstance] showInKeyWindowWithPasscode:getPasscode() iconView:iconView eventBlock:^void(BOOL authenticated){
				if (authenticated) {
					appAlreadyAuthenticated = YES;
					[iconView.icon launchFromLocation:iconView.location];
				}
			}];
		}
		[[%c(SBIconController) sharedInstance] resetAsphaleiaIconView];

		return;
	} else if ((![getProtectedApps() containsObject:iconView.icon.applicationBundleID] && !shouldProtectAllApps()) || ([temporarilyUnlockedAppBundleID isEqual:iconView.icon.applicationBundleID] && !shouldProtectAllApps()) || !iconView.icon.applicationBundleID) {
		%orig;
		return;
	} else if (!touchIDEnabled() && passcodeEnabled()) {
		[[ASPasscodeHandler sharedInstance] showInKeyWindowWithPasscode:getPasscode() iconView:iconView eventBlock:^void(BOOL authenticated){
			[iconView setHighlighted:NO];

			if (authenticated){
				appAlreadyAuthenticated = YES;
				%orig;
			}
		}];
		return;
	}

	anywhereTouchWindow = [[ASTouchWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

	currentIconView = iconView;
	fingerglyph = [[%c(PKGlyphView) alloc] initWithStyle:1];
	fingerglyph.secondaryColor = [UIColor grayColor];
	fingerglyph.primaryColor = [UIColor redColor];
	CGRect fingerframe = fingerglyph.frame;
	fingerframe.size.height = [iconView _iconImageView].frame.size.height-10;
	fingerframe.size.width = [iconView _iconImageView].frame.size.width-10;
	fingerglyph.frame = fingerframe;
	fingerglyph.center = CGPointMake(CGRectGetMidX([iconView _iconImageView].bounds),CGRectGetMidY([iconView _iconImageView].bounds));
	[[iconView _iconImageView] addSubview:fingerglyph];

	fingerglyph.transform = CGAffineTransformMakeScale(0.01,0.01);
	[UIView animateWithDuration:0.3f animations:^{
		fingerglyph.transform = CGAffineTransformMakeScale(1,1);
	}];

	if (!iconTouchIDController) {
		iconTouchIDController = [[BTTouchIDController alloc] initWithEventBlock:^void(BTTouchIDController *controller, id monitor, unsigned event) {
			switch (event) {
			case TouchIDMatched:
				if (fingerglyph && currentIconView) {
					appAlreadyAuthenticated = YES;
					[currentIconView.icon launchFromLocation:currentIconView.location];
					[[%c(SBIconController) sharedInstance] resetAsphaleiaIconView];
				}
				break;
			case TouchIDFingerDown:
				[fingerglyph setState:1 animated:YES completionHandler:nil];

				[currentIconView updateLabelWithText:@"Scanning..."];

				break;
			case TouchIDFingerUp:
				[fingerglyph setState:0 animated:YES completionHandler:nil];
				break;
			case TouchIDNotMatched:
				[fingerglyph setState:0 animated:YES completionHandler:nil];

				[currentIconView updateLabelWithText:@"Scan finger..."];

				if (shouldVibrateOnIncorrectFingerprint())
						AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
				break;
			}
		}];
	}
	[iconTouchIDController startMonitoring];

	[currentIconView updateLabelWithText:@"Scan finger..."];

	[anywhereTouchWindow blockTouchesAllowingTouchInView:currentIconView touchBlockedHandler:^void(ASTouchWindow *touchWindow, BOOL blockedTouch){
		if (blockedTouch) {
			[[%c(SBIconController) sharedInstance] resetAsphaleiaIconView];
		}
	}];
}

-(void)iconHandleLongPress:(SBIconView *)iconView {
	if (self.isEditing || !shouldSecureAppArrangement() || [ASPreferencesHandler sharedInstance].asphaleiaDisabled) {
		%orig;
		return;
	}

	[iconView setHighlighted:NO];
	[iconView cancelLongPressTimer];
	[iconView setTouchDownInIcon:NO];
	
	[[ASCommon sharedInstance] showAuthenticationAlertOfType:ASAuthenticationAlertAppArranging beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
		if (!wasCancelled)
			[self setIsEditing:YES];
		}];
}

%new
-(void)resetAsphaleiaIconView {
	if (fingerglyph && currentIconView) {
		[currentIconView _updateLabel];

		[UIView animateWithDuration:0.3f animations:^{
			fingerglyph.transform = CGAffineTransformMakeScale(0.01,0.01);
		}];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[currentIconView setHighlighted:NO];
			[iconTouchIDController stopMonitoring];
			[fingerglyph release];
			fingerglyph = nil;

			currentIconView = nil;
			if (anywhereTouchWindow) {
				[anywhereTouchWindow release];
				anywhereTouchWindow = nil;
			}
		});
	}
}

%end

%hook SBIconView

%new
-(void)updateLabelWithText:(NSString *)text {
	SBIconLabelView *iconLabelView = [self valueForKey:@"_labelView"];

	SBIconLabelImageParameters *imageParameters = [[iconLabelView imageParameters] mutableCopy];
	[imageParameters setText:text];
	[%c(SBIconLabelView) updateIconLabelView:iconLabelView withSettings:nil imageParameters:imageParameters];
}

%end

%hook SBAppSwitcherController

-(void)_askDelegateToDismissToDisplayLayout:(SBDisplayLayout *)displayLayout displayIDsToURLs:(id)urls displayIDsToActions:(id)actions {
	SBDisplayItem *item = [displayLayout.displayItems objectAtIndex:0];
	NSMutableDictionary *iconViews = [iconController valueForKey:@"_iconViews"];

	SBApplication *frontmostApp = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];

	SBIconView *iconView = [iconViews objectForKey:displayLayout];

	if ((![getProtectedApps() containsObject:item.displayIdentifier] && !shouldProtectAllApps()) || !shouldObscureAppContent() || [temporarilyUnlockedAppBundleID isEqual:item.displayIdentifier] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled || [item.displayIdentifier isEqual:[frontmostApp bundleIdentifier]] || !iconView.icon.displayName) {
		%orig;
		return;
	}

	[[ASCommon sharedInstance] showAppAuthenticationAlertWithIconView:iconView customMessage:nil beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
	if (!wasCancelled)
		%orig;
	}];
}

%end

%hook SBAppSwitcherIconController

/*-(void)dealloc {
	iconController = nil;
	%orig;
}*/

-(id)init {
	iconController = %orig;
	return iconController;
}

%end

%hook SBAppSwitcherSnapshotView

-(void)_layoutStatusBar {
	if ((![getProtectedApps() containsObject:self.displayItem.displayIdentifier] && !shouldProtectAllApps()) || !shouldObscureAppContent() || [temporarilyUnlockedAppBundleID isEqual:self.displayItem.displayIdentifier] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled)
		%orig;
}

-(void)prepareToBecomeVisibleIfNecessary {
	%orig;
	UIImageView *snapshotImageView = [self valueForKey:@"_snapshotImageView"];

	BOOL alreadyBlurred = snapshotImageView.layer.filters != nil;

	if ((![getProtectedApps() containsObject:self.displayItem.displayIdentifier] && !shouldProtectAllApps()) || !shouldObscureAppContent() || [temporarilyUnlockedAppBundleID isEqual:self.displayItem.displayIdentifier] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled || alreadyBlurred) {
		return;
	}

	//UIImageView *snapshotImageView = [self valueForKey:@"_snapshotImageView"];
	CAFilter* filter = [CAFilter filterWithName:@"gaussianBlur"];
	[filter setValue:[NSNumber numberWithFloat:15] forKey:@"inputRadius"];
	[filter setValue:[NSNumber numberWithBool:YES] forKey:@"inputHardEdges"];
	snapshotImageView.layer.filters = [NSArray arrayWithObject:filter];
	[self setValue:snapshotImageView forKey:@"_snapshotImageView"];

	NSBundle *asphaleiaAssets = [[NSBundle alloc] initWithPath:kBundlePath];
	UIImage *obscurityEye = [UIImage imageNamed:@"unocme.png" inBundle:asphaleiaAssets compatibleWithTraitCollection:nil];
	
	UIView *obscurityView = [[UIView alloc] initWithFrame:self.bounds];
	obscurityView.backgroundColor = [UIColor colorWithWhite:0.f alpha:0.7f];
	
	UIImageView *imageView = [[UIImageView alloc] init];
	imageView.image = obscurityEye;
	imageView.frame = CGRectMake(0, 0, obscurityEye.size.width*2, obscurityEye.size.height*2);
	imageView.center = obscurityView.center;
	[obscurityView addSubview:imageView];
	
	obscurityView.tag = 80085; // ;)
	[self addSubview:obscurityView];
	[asphaleiaAssets release];
}

-(void)_viewDismissing:(id)dismissing {
	UIImageView *snapshotImageView = [self valueForKey:@"_snapshotImageView"];
	snapshotImageView.layer.filters = nil;
	[self setValue:snapshotImageView forKey:@"_snapshotImageView"];

	@autoreleasepool {
		NSArray *array = [[[[ASCommon sharedInstance] allSubviewsOfView:self] copy] autorelease];

		for (UIView *view in array) {
			if (view.tag == 80085 && [[view class] isKindOfClass:[UIView class]]) {
				[view removeFromSuperview];
			}
		}
	}

	%orig;
}

-(void)dealloc {
	UIImageView *snapshotImageView = [self valueForKey:@"_snapshotImageView"];
	snapshotImageView.layer.filters = nil;
	[self setValue:snapshotImageView forKey:@"_snapshotImageView"];

	@autoreleasepool {
		NSArray *array = [[[[ASCommon sharedInstance] allSubviewsOfView:self] copy] autorelease];

		for (UIView *view in array) {
			if (view.tag == 80085 && [[view class] isKindOfClass:[UIView class]]) {
				[view removeFromSuperview];
			}
		}
	}

	%orig;
}

%end

%hook SBUIController

-(BOOL)_activateAppSwitcher {
	if (!shouldSecureSwitcher()) {
		return %orig;
	}

	[[ASCommon sharedInstance] showAuthenticationAlertOfType:ASAuthenticationAlertSwitcher beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
		if (!wasCancelled)
			%orig;
		}];
	return NO;
}

%end

%hook SBLockScreenManager

-(void)_lockUI {
	[[%c(SBIconController) sharedInstance] resetAsphaleiaIconView];
	[[ASCommon sharedInstance] dismissAnyAuthenticationAlerts];
	[[ASPasscodeHandler sharedInstance] dismissPasscodeView];
	%orig;
	if (shouldResetAppExitTimerOnLock() && currentTempUnlockTimer) {
		[currentTempUnlockTimer fire];
		[currentTempGlobalDisableTimer fire];
	}
}

-(void)_finishUIUnlockFromSource:(int)source withOptions:(id)options {
	%orig;
	if (shouldDelayAppSecurity()) {
		[ASPreferencesHandler sharedInstance].appSecurityDisabled = YES;
		currentTempGlobalDisableTimer = [NSTimer scheduledTimerWithTimeInterval:appSecurityDelayTimeInterval() block:^{
			[ASPreferencesHandler sharedInstance].appSecurityDisabled = NO;
		} repeats:NO];
		return;
	}

	SBApplication *frontmostApp = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
	if (([getProtectedApps() containsObject:[frontmostApp bundleIdentifier]] || shouldProtectAllApps()) && !shouldUnsecurelyUnlockIntoApp() && frontmostApp && ![temporarilyUnlockedAppBundleID isEqual:[frontmostApp bundleIdentifier]]) {
		SBApplicationIcon *appIcon = [[%c(SBApplicationIcon) alloc] initWithApplication:frontmostApp];
		SBIconView *iconView = [[%c(SBIconView) alloc] initWithDefaultSize];
		[iconView _setIcon:appIcon animated:YES];

		__block UIWindow *blurredWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
		blurredWindow.backgroundColor = [UIColor clearColor];

		UIVisualEffect *blurEffect;
		blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
		
		UIVisualEffectView *visualEffectView;
		visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
		
		visualEffectView.frame = [[UIScreen mainScreen] bounds];

		blurredWindow.windowLevel = UIWindowLevelAlert-1;
		[blurredWindow addSubview:visualEffectView];
		[blurredWindow makeKeyAndVisible];
		[[ASCommon sharedInstance] showAppAuthenticationAlertWithIconView:iconView customMessage:nil beginMesaMonitoringBeforeShowing:NO dismissedHandler:^(BOOL wasCancelled) {
			blurredWindow.hidden = YES;

			if (wasCancelled) {
				[[%c(SBUIController) sharedInstanceIfExists] clickedMenuButton];
			}
		}];
	}
}

%end

%hook SBSearchViewController
static BOOL searchControllerHasAuthenticated;
static BOOL searchControllerAuthenticating;

-(void)_setShowingKeyboard:(BOOL)keyboard {
	%orig;
	if (keyboard && !searchControllerHasAuthenticated && !searchControllerAuthenticating && shouldSecureSpotlight()) {
		[self cancelButtonPressed];
		[[ASCommon sharedInstance] showAuthenticationAlertOfType:ASAuthenticationAlertSpotlight beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
		searchControllerAuthenticating = NO;
		if (!wasCancelled) {
			searchControllerHasAuthenticated = YES;
			[(SpringBoard *)[UIApplication sharedApplication] _revealSpotlight];
			[self _setShowingKeyboard:YES];
		}
		}];
		searchControllerAuthenticating = YES;
	}
}

-(void)_handleDismissGesture {
	searchControllerHasAuthenticated = NO;
	searchControllerAuthenticating = NO;
	%orig;
}

-(void)dismiss {
	searchControllerHasAuthenticated = NO;
	searchControllerAuthenticating = NO;
	%orig;
}

%end

%hook SBPowerDownController

-(void)orderFront {
	if (!shouldSecurePowerDownView()) {
		%orig;
		return;
	}

	[[ASCommon sharedInstance] showAuthenticationAlertOfType:ASAuthenticationAlertPowerDown beginMesaMonitoringBeforeShowing:NO dismissedHandler:^(BOOL wasCancelled) {
	if (!wasCancelled)
		%orig;
	}];
}

%end

%hook SBControlCenterController
static BOOL controlCentreAuthenticating;
static BOOL controlCentreHasAuthenticated;

-(void)beginTransitionWithTouchLocation:(CGPoint)touchLocation {
	if (!shouldSecureControlCentre() || controlCentreHasAuthenticated || controlCentreAuthenticating) {
		%orig;
		return;
	}

	controlCentreAuthenticating = YES;
	[[ASCommon sharedInstance] showAuthenticationAlertOfType:ASAuthenticationAlertControlCentre beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
	controlCentreAuthenticating = NO;
	if (!wasCancelled) {
		controlCentreHasAuthenticated = YES;
		[self presentAnimated:YES];
	}
	}];
}

-(void)_endPresentation {
	controlCentreHasAuthenticated = NO;
	controlCentreAuthenticating = NO;
	%orig;
}

%end

%hook SBApplication

-(void)willAnimateDeactivation:(BOOL)deactivation {
	%orig;
	if (![getProtectedApps() containsObject:[self bundleIdentifier]] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled)
		return;

	if (currentTempUnlockTimer)
		[currentTempUnlockTimer fire];

	if (appExitUnlockTimeInterval() <= 0)
		return;

	temporarilyUnlockedAppBundleID = [self bundleIdentifier];
	currentTempUnlockTimer = [NSTimer scheduledTimerWithTimeInterval:appExitUnlockTimeInterval() block:^{
		temporarilyUnlockedAppBundleID = nil;
		currentTempUnlockTimer = nil;
		[temporarilyUnlockedAppBundleID release];
		[currentTempUnlockTimer release];
	} repeats:NO];
}

%end

%hook SpringBoard
static BOOL openURLHasAuthenticated;

-(void)_applicationOpenURL:(id)url withApplication:(id)application sender:(id)sender publicURLsOnly:(BOOL)only animating:(BOOL)animating activationSettings:(id)settings withResult:(id)result {
	%orig;
	openURLHasAuthenticated = NO;
}

-(void)applicationOpenURL:(id)url withApplication:(id)application sender:(id)sender publicURLsOnly:(BOOL)only animating:(BOOL)animating needsPermission:(BOOL)permission activationSettings:(id)settings withResult:(id)result {
	if ((![getProtectedApps() containsObject:[application bundleIdentifier]] && !shouldProtectAllApps()) || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled) {
		%orig;
		return;
	}

	SBApplicationIcon *appIcon = [[%c(SBApplicationIcon) alloc] initWithApplication:application];
	SBIconView *iconView = [[%c(SBIconView) alloc] initWithDefaultSize];
	[iconView _setIcon:appIcon animated:YES];

	[[ASCommon sharedInstance] showAppAuthenticationAlertWithIconView:iconView customMessage:nil beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
			if (!wasCancelled) {
				// using %orig; crashes springboard, so this is my alternative.
				openURLHasAuthenticated = YES;
				[self applicationOpenURL:url];
			}
		}];
}

/*- (void)_menuButtonDown:(id)arg1 {
	if ([[UIApplication sharedApplication].keyWindow isMemberOfClass:[UIWindow class]])
	{
		// no alertview
	}
}*/

%end

%hook SBUIController

- (void)activateApplicationAnimated:(id)application {
	if ((![getProtectedApps() containsObject:[application bundleIdentifier]] && !shouldProtectAllApps()) || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled || appAlreadyAuthenticated) {
		appAlreadyAuthenticated = NO;
		%orig;
		return;
	}

	appAlreadyAuthenticated = NO;

	SBApplicationIcon *appIcon = [[%c(SBApplicationIcon) alloc] initWithApplication:application];
	SBIconView *iconView = [[%c(SBIconView) alloc] initWithDefaultSize];
	[iconView _setIcon:appIcon animated:YES];

	[[ASCommon sharedInstance] showAppAuthenticationAlertWithIconView:iconView customMessage:nil beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
			if (!wasCancelled) {
				%orig;
			}
		}];
}

%end

%hook SBBannerContainerViewController
UIVisualEffectView *notificationBlurView;
PKGlyphView *bannerFingerGlyph;
BTTouchIDController *bannerTouchIDController;
BOOL currentBannerAuthenticated;

-(void)loadView {
	%orig;

	currentBannerAuthenticated = NO;

	if ((![getProtectedApps() containsObject:[[self _bulletin] sectionID]] && !shouldProtectAllApps()) || [temporarilyUnlockedAppBundleID isEqual:[[self _bulletin] sectionID]] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled)
		return;

	UIVisualEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
	notificationBlurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
	notificationBlurView.frame = self._bannerFrame;
	notificationBlurView.userInteractionEnabled = NO;
	[self.bannerContextView addSubview:notificationBlurView];

	bannerFingerGlyph = [[%c(PKGlyphView) alloc] initWithStyle:1];
	bannerFingerGlyph.secondaryColor = [UIColor grayColor];
	bannerFingerGlyph.primaryColor = [UIColor redColor];
	CGRect fingerframe = bannerFingerGlyph.frame;
	fingerframe.size.height = notificationBlurView.frame.size.height-10;
	fingerframe.size.width = notificationBlurView.frame.size.width-10;
	bannerFingerGlyph.frame = fingerframe;
	bannerFingerGlyph.center = CGPointMake(CGRectGetMidX(notificationBlurView.bounds),CGRectGetMidY(notificationBlurView.bounds));
	[notificationBlurView.contentView addSubview:bannerFingerGlyph];

	if (!bannerTouchIDController) {
		bannerTouchIDController = [[BTTouchIDController alloc] initWithEventBlock:^void(BTTouchIDController *controller, id monitor, unsigned event) {
			switch (event) {
			case TouchIDMatched:
				if (bannerFingerGlyph && notificationBlurView) {
					currentBannerAuthenticated = YES;
					[bannerTouchIDController stopMonitoring];
					[UIView animateWithDuration:0.3f animations:^{
						[notificationBlurView setAlpha:0.0f];
					}];
				}
				break;
			case TouchIDFingerDown:
				[bannerFingerGlyph setState:1 animated:YES completionHandler:nil];
	
				break;
			case TouchIDFingerUp:
				[bannerFingerGlyph setState:0 animated:YES completionHandler:nil];
				break;
			case TouchIDNotMatched:
				[bannerFingerGlyph setState:0 animated:YES completionHandler:nil];
	
				if (shouldVibrateOnIncorrectFingerprint())
						AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
				break;
			}
		}];
	}
	[bannerTouchIDController startMonitoring];
}

-(void)_handleBannerTapGesture:(id)gesture {
	if ((![getProtectedApps() containsObject:[[self _bulletin] sectionID]] && !shouldProtectAllApps()) || [temporarilyUnlockedAppBundleID isEqual:[[self _bulletin] sectionID]] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled || currentBannerAuthenticated)
		%orig;
}

-(void)dealloc {
	if (bannerFingerGlyph) {
		[bannerFingerGlyph release];
		bannerFingerGlyph = nil;
	}

	if (notificationBlurView) {
		[notificationBlurView removeFromSuperview];
		[notificationBlurView release];
		notificationBlurView = nil;
	}
	%orig;
}

-(void)setBannerPullDisplacement:(float)displacement {
	if ((![getProtectedApps() containsObject:[[self _bulletin] sectionID]] && !shouldProtectAllApps()) || [temporarilyUnlockedAppBundleID isEqual:[[self _bulletin] sectionID]] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled || currentBannerAuthenticated)
		%orig;
}

-(void)setBannerPullPercentage:(float)percentage {
	if ((![getProtectedApps() containsObject:[[self _bulletin] sectionID]] && !shouldProtectAllApps()) || [temporarilyUnlockedAppBundleID isEqual:[[self _bulletin] sectionID]] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled || currentBannerAuthenticated)
		%orig;
}

%end

%hook SBBulletinModalController

-(void)observer:(id)observer addBulletin:(BBBulletin *)bulletin forFeed:(unsigned)feed {
	if ((![getProtectedApps() containsObject:[bulletin sectionID]] && !shouldProtectAllApps()) || [temporarilyUnlockedAppBundleID isEqual:[bulletin sectionID]] || [ASPreferencesHandler sharedInstance].asphaleiaDisabled || [ASPreferencesHandler sharedInstance].appSecurityDisabled || currentBannerAuthenticated)
		%orig;

	SBApplication *application = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:[bulletin sectionID]];
	SBApplicationIcon *appIcon = [[%c(SBApplicationIcon) alloc] initWithApplication:application];
	SBIconView *iconView = [[%c(SBIconView) alloc] initWithDefaultSize];
	[iconView _setIcon:appIcon animated:YES];

	[[ASCommon sharedInstance] showAppAuthenticationAlertWithIconView:iconView customMessage:@"Scan fingerprint to show notification." beginMesaMonitoringBeforeShowing:YES dismissedHandler:^(BOOL wasCancelled) {
			if (!wasCancelled) {
				%orig;
			}
		}];
}

%end

%ctor {
	addObserver(preferencesChangedCallback,kPrefsChangedNotification);
	loadPreferences();
	[[ASControlPanel sharedInstance] load];
	[[ASActivatorListener sharedInstance] loadWithEventHandler:^void(LAEvent *event, BOOL abortEventCalled){
		SBApplication *frontmostApp = [(SpringBoard *)[UIApplication sharedApplication] _accessibilityFrontMostApplication];
		NSString *bundleID = frontmostApp.bundleIdentifier;

		if (!bundleID || !shouldUseDynamicSelection())
			return;

		NSNumber *appSecureValue = [NSNumber numberWithBool:![[[[ASPreferencesHandler sharedInstance].prefs objectForKey:kSecuredAppsKey] objectForKey:bundleID] boolValue]];
		if (abortEventCalled)
			appSecureValue = [NSNumber numberWithBool:NO];

		[[[ASPreferencesHandler sharedInstance].prefs objectForKey:kSecuredAppsKey] setObject:appSecureValue forKey:frontmostApp.bundleIdentifier];
		[[ASPreferencesHandler sharedInstance].prefs writeToFile:kPreferencesFilePath atomically:YES];

		/*NSString *title = nil;
		NSString *description = nil;
		if (![[[[ASPreferencesHandler sharedInstance].prefs objectForKey:kSecuredAppsKey] objectForKey:bundleID] boolValue]) {
			title = @"Disabled authentication";
			description = [NSString stringWithFormat:@"Disabled authentication for %@", frontmostApp.displayName];
		} else {
			title = @"Enabled authentication";
			description = [NSString stringWithFormat:@"Enabled authentication for %@", frontmostApp.displayName];
		}

		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title
				   message:description
				  delegate:nil
		 cancelButtonTitle:@"Okay"
		 otherButtonTitles:nil];
		[alertView show];
		[alertView release];*/
		return;
	}];
}