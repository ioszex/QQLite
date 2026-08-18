//
//  QQTweakListBuilder.h
//  把 QQTweakSection / QQTweakRow 翻译成QQ原生的 QUIListSectionModel / QUIListSingleLineConfig
//

#import <UIKit/UIKit.h>

@class QQTweakSection;

@interface QQTweakListBuilder : NSObject

// QQ的QUI列表组件是否可用
+ (BOOL)isAvailable;

// 从QQ设置页（QQSettingsBaseViewController子类）的listView上抄一份样式参数，
// 这样我们的页面和QQ设置页在间距、分割线、底色上完全一致。
+ (void)captureListStyleFromViewController:(UIViewController *)viewController;

// 抄到的列表底色，没抄到返回 nil
+ (UIColor *)capturedBackgroundColor;

// 新建一个和QQ设置页同款的 QUIListView。QUIListView 在 init 时就会 setupUI，
// 所以这里要求传入真实 frame，别给 CGRectZero。
+ (UIView *)makeListViewWithFrame:(CGRect)frame;

// 生成 dataArray。switchBridges 用来接住开关回调的代理对象（QUI那边是weak持有，必须外部保活）
+ (NSArray *)buildDataArrayWithSections:(NSArray<QQTweakSection *> *)sections
				   host:(UIViewController *)host
			  switchBridges:(NSMutableArray *)switchBridges;

// 把数据灌进列表
+ (void)reloadListView:(UIView *)listView withData:(NSArray *)data;

@end
