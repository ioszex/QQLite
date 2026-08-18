//
//  QQTweakAlert.m
//

#import "QQTweakAlert.h"
#import <objc/runtime.h>

#pragma mark - QQ弹窗的接口声明

// 用协议而不是 @interface 来声明，避免和QQ进程里真实的类定义冲突。
// 方法签名取自 QQHeaders/QUIBaseAlertView.h 与 QQHeaders/QUIPopupView.h。
@protocol QQTweakQUIAlertView <NSObject>
- (instancetype)initWithTitle:(NSString *)title
		      message:(NSString *)message
		     delegate:(id)delegate
	    cancelButtonTitle:(NSString *)cancelButtonTitle
	otherButtonTitleArray:(NSArray *)otherButtonTitleArray;
- (void)show;
- (NSInteger)cancelButtonIndex;
- (NSInteger)firstOtherButtonIndex;
- (void)setDestructiveButtonIndex:(NSInteger)index;
@end

// QUIBaseAlertViewController 只是 -show 内部用来承载弹窗的容器控制器，
// 它对 alertView 是 weak 持有，弹窗自身也没人 retain，
// 所以这里必须自己把弹窗强引用住，否则 ARC 会在方法返回时就把它释放掉。
static NSMutableArray *QQTweakLiveAlerts(void) {
	static NSMutableArray *alerts = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
	  alerts = [NSMutableArray array];
	});
	return alerts;
}

static void QQTweakReleaseAlert(id alert) {
	if (!alert)
		return;
	[QQTweakLiveAlerts() removeObjectIdenticalTo:alert];
}

#pragma mark - 弹窗回调代理

@interface QQTweakAlertHandler : NSObject
@property(nonatomic, copy) void (^onConfirm)(void);
@end

@implementation QQTweakAlertHandler

- (void)alertView:(id)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	NSInteger cancelIndex = -1;
	if ([alertView respondsToSelector:@selector(cancelButtonIndex)]) {
		cancelIndex = [(id<QQTweakQUIAlertView>)alertView cancelButtonIndex];
	}
	if (buttonIndex != cancelIndex && self.onConfirm) {
		self.onConfirm();
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
	  QQTweakReleaseAlert(alertView);
	});
}

- (void)alertView:(id)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	QQTweakReleaseAlert(alertView);
}

@end

#pragma mark -

static const void *kQQTweakAlertHandlerKey = &kQQTweakAlertHandlerKey;

@implementation QQTweakAlert

+ (void)showWithTitle:(NSString *)title
	      message:(NSString *)message
	 confirmTitle:(NSString *)confirmTitle
	  destructive:(BOOL)destructive
	  cancelTitle:(NSString *)cancelTitle
	   fromViewController:(UIViewController *)host
		onConfirm:(void (^)(void))onConfirm {
	if ([self showQUIAlertWithTitle:title
				message:message
			   confirmTitle:confirmTitle
			    destructive:destructive
			    cancelTitle:cancelTitle
			      onConfirm:onConfirm]) {
		return;
	}
	[self showSystemAlertWithTitle:title
			       message:message
			  confirmTitle:confirmTitle
			   destructive:destructive
			   cancelTitle:cancelTitle
		    fromViewController:host
			     onConfirm:onConfirm];
}

+ (BOOL)showQUIAlertWithTitle:(NSString *)title
		      message:(NSString *)message
		 confirmTitle:(NSString *)confirmTitle
		  destructive:(BOOL)destructive
		  cancelTitle:(NSString *)cancelTitle
		    onConfirm:(void (^)(void))onConfirm {
	Class alertClass = NSClassFromString(@"QUIAlertView") ?: NSClassFromString(@"QUIBaseAlertView");
	if (!alertClass)
		return NO;

	SEL initSelector = @selector(initWithTitle:message:delegate:cancelButtonTitle:otherButtonTitleArray:);
	if (![alertClass instancesRespondToSelector:initSelector] || ![alertClass instancesRespondToSelector:@selector(show)]) {
		return NO;
	}

	QQTweakAlertHandler *handler = [[QQTweakAlertHandler alloc] init];
	handler.onConfirm = onConfirm;

	id<QQTweakQUIAlertView> alert = [alertClass alloc];
	alert = [alert initWithTitle:title
			     message:message
			    delegate:handler
		   cancelButtonTitle:cancelTitle
	       otherButtonTitleArray:(confirmTitle.length > 0 ? @[ confirmTitle ] : @[])];
	if (!alert)
		return NO;

	objc_setAssociatedObject(alert, kQQTweakAlertHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[QQTweakLiveAlerts() addObject:alert];

	if (destructive && [alert respondsToSelector:@selector(setDestructiveButtonIndex:)] &&
	    [alert respondsToSelector:@selector(firstOtherButtonIndex)]) {
		[alert setDestructiveButtonIndex:[alert firstOtherButtonIndex]];
	}

	[alert show];
	return YES;
}

+ (void)showSystemAlertWithTitle:(NSString *)title
			 message:(NSString *)message
		    confirmTitle:(NSString *)confirmTitle
		     destructive:(BOOL)destructive
		     cancelTitle:(NSString *)cancelTitle
	      fromViewController:(UIViewController *)host
		       onConfirm:(void (^)(void))onConfirm {
	if (!host)
		return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
								      message:message
							       preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:confirmTitle
						  style:(destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault)
						handler:^(UIAlertAction *action) {
						  if (onConfirm)
							  onConfirm();
						}]];
	if (cancelTitle.length > 0) {
		[alert addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];
	}
	[host presentViewController:alert animated:YES completion:nil];
}

@end
