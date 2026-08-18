//
//  QQTweakAboutViewController.h
//  QQTweak 关于插件页面（独立二级页面）
//
//  展示插件品牌头部 + 版本 / 开发者 / 包标识 / 宿主版本等信息。
//  继承 QQTweakSettingsViewController 复用整套 QUI 列表渲染与导航逻辑。
//

#import "QQTweakSettingsViewController.h"

@interface QQTweakAboutViewController : QQTweakSettingsViewController

// 构造关于页
+ (instancetype)aboutViewController;

@end
