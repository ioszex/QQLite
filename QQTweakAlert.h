//
//  QQTweakAlert.h
//  用QQ自带的弹窗组件（QUIAlertView / QUIBaseAlertViewController）显示确认框
//
//  类关系（来自QQHeaders）：
//    QUIAlertView : QUIBaseAlertView : QUIPopupView : UIView
//    QUIBaseAlertView 通过 QUIBaseAlertViewController + 独立 UIWindow 弹出，
//    调用 -show 即可，不需要自己找宿主控制器。
//

#import <UIKit/UIKit.h>

@interface QQTweakAlert : NSObject

// 弹出一个"确认 / 取消"弹窗。优先用QQ原生弹窗，取不到类时回退到 UIAlertController。
+ (void)showWithTitle:(NSString *)title
	      message:(NSString *)message
	 confirmTitle:(NSString *)confirmTitle
	  destructive:(BOOL)destructive
	  cancelTitle:(NSString *)cancelTitle
	   fromViewController:(UIViewController *)host
		onConfirm:(void (^)(void))onConfirm;

@end
