#import <libactivator/libactivator.h>
#import <UIKit/UIKit.h>
#import <SpringboardUI/SBUIPasscodeLockViewSimple4DigitKeypad.h>
#import "Asphaleia.h"

typedef void (^ASPasscodeHandlerEventBlock) (BOOL authenticated);
 
@interface ASPasscodeHandler : NSObject
@property (retain) NSString *passcode;
+(instancetype)sharedInstance;
-(void)showInKeyWindowWithPasscode:(NSString *)passcode iconView:(SBIconView *)iconView eventBlock:(ASPasscodeHandlerEventBlock)eventBlock;
-(void)dismissPasscodeView;
@end