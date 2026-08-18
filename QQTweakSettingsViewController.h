//
//  QQTweakSettingsViewController.h
//  QQLite二级设置页面
//
//  由于 QQ 的 QUIListView / QUIListSectionModel 属于私有 UI 组件且缺少完整头文件，
//  这里用 UITableView 自行实现，按 QQ NT 设置页的视觉规范还原，push 进 QQ 的导航栈。
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, QQTweakRowType) {
	QQTweakRowTypeDisclosure = 0, // 右侧箭头，点击进入下一级
	QQTweakRowTypeSwitch,	      // 右侧开关
	QQTweakRowTypeValue,	      // 右侧纯文本，不可点击
	QQTweakRowTypeButton,	      // 整行居中文字按钮
};

#pragma mark - 行模型

@interface QQTweakRow : NSObject

@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;	   // 右侧详情文本
@property(nonatomic, copy) NSString *iconName;	   // SF Symbol 名称，为空则不显示图标
@property(nonatomic, strong) UIColor *iconTintColor;
@property(nonatomic, assign) QQTweakRowType type;
@property(nonatomic, copy) NSString *prefKey;	   // 开关行对应的偏好 key
@property(nonatomic, assign) BOOL destructive;	   // 按钮行是否用红色
@property(nonatomic, copy) void (^actionBlock)(UIViewController *host);
@property(nonatomic, copy) void (^switchChangedBlock)(BOOL isOn);

+ (instancetype)switchRowWithTitle:(NSString *)title icon:(NSString *)iconName tint:(UIColor *)tint prefKey:(NSString *)prefKey;
+ (instancetype)disclosureRowWithTitle:(NSString *)title
				  icon:(NSString *)iconName
				  tint:(UIColor *)tint
				detail:(NSString *)detail
				action:(void (^)(UIViewController *host))action;
+ (instancetype)valueRowWithTitle:(NSString *)title icon:(NSString *)iconName tint:(UIColor *)tint detail:(NSString *)detail;
+ (instancetype)buttonRowWithTitle:(NSString *)title destructive:(BOOL)destructive action:(void (^)(UIViewController *host))action;

@end

#pragma mark - 分组模型

@interface QQTweakSection : NSObject

@property(nonatomic, copy) NSString *headerTitle;
@property(nonatomic, copy) NSString *footerTitle;
@property(nonatomic, strong) NSArray<QQTweakRow *> *rows;

+ (instancetype)sectionWithHeader:(NSString *)header rows:(NSArray<QQTweakRow *> *)rows;
+ (instancetype)sectionWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray<QQTweakRow *> *)rows;

@end

#pragma mark - 页面

@interface QQTweakSettingsViewController : UIViewController

@property(nonatomic, copy) NSString *pageTitle;
@property(nonatomic, strong) NSArray<QQTweakSection *> *sections;
@property(nonatomic, assign) BOOL showsBrandHeader; // 顶部品牌区（图标 + 名称 + 版本）

// 构造主设置页
+ (instancetype)mainSettingsViewController;

// 从 QQ 设置页的 didSelectBlock 里调用：自动找到当前导航栈并 push
+ (void)showSettings;

// 在当前页 push 下一级
- (void)pushViewController:(UIViewController *)viewController;

@end
