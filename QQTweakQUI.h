//
//  QQTweakQUI.h
//  QQ私有UI组件（QUIKit）的接口声明
//
//  全部方法签名取自 QQHeaders 里的头文件转储，用 @protocol 声明而不是 @interface，
//  这样既有编译期类型检查，又不会和QQ进程里真实的类定义冲突。
//  运行时统一用 NSClassFromString 取类。
//

#import <UIKit/UIKit.h>

#pragma mark - 左侧样式  (QQHeaders/QUILeftTextStyle.h, QUILeftTextAvatarStyle.h)

// QUILeftTextStyle : QUIListItemLeftStyle
@protocol QQTweakQUILeftTextStyleClass <NSObject>
+ (id)styleWithTitle:(NSString *)title;
+ (id)styleWithAttributedStrTitle:(NSAttributedString *)attributedTitle;
@end

// QUILeftTextIconStyle : QUILeftTextAvatarStyle，styleWithTitle:image: 继承自父类
@protocol QQTweakQUILeftIconStyleClass <NSObject>
+ (id)styleWithTitle:(NSString *)title image:(UIImage *)image;
@end

#pragma mark - 右侧样式  (QQHeaders/QUIRightTextStyle.h, QUIRightSwitchStyle.h)

@protocol QQTweakQUIRightTextStyleClass <NSObject>
+ (id)styleWithDetailText:(NSString *)detailText showRedPoint:(BOOL)showRedPoint showArrow:(BOOL)showArrow;
@end

@protocol QQTweakQUIRightSwitchStyleClass <NSObject>
+ (id)styleWithSwitchOn:(BOOL)switchOn;
@end

#pragma mark - 行配置  (QQHeaders/QUIListSingleLineConfig.h, QUIListCellConfig.h, QUIListCellBaseModel.h)

@protocol QQTweakQUIListConfigClass <NSObject>
+ (id)configWithLeftStyle:(id)leftStyle rightStyle:(id)rightStyle;
@end

@protocol QQTweakQUIListConfig <NSObject>
@property(nonatomic) NSInteger tag;
@property(nonatomic, copy) id didSelectBlock;
@property(nonatomic, weak) id actionDelegate;	 // id<QUIListCellConfigDelegate>
@property(nonatomic, retain) id leftStyle;
@property(nonatomic, retain) id rightStyle;
@end

#pragma mark - 分组  (QQHeaders/QUIListSectionModel.h)

@protocol QQTweakQUISectionModelClass <NSObject>
+ (id)sectionWithHeaderTitle:(NSString *)headerTitle footerTitle:(NSString *)footerTitle rowModelArray:(NSArray *)rowModelArray;
@end

#pragma mark - 列表视图  (QQHeaders/QUIListView.h)

@protocol QQTweakQUIListView <NSObject>
- (instancetype)initWithFrame:(CGRect)frame;
- (instancetype)initWithFrame:(CGRect)frame style:(unsigned long long)style;
- (void)reloadWithData:(NSArray *)data;
- (void)reloadData;
- (UITableView *)tableView;
- (unsigned long long)style;
- (unsigned long long)seperatorStyle;
- (void)setSeperatorStyle:(unsigned long long)seperatorStyle;
- (double)topSpacing;
- (void)setTopSpacing:(double)topSpacing;
- (double)sectionSpacing;
- (void)setSectionSpacing:(double)sectionSpacing;
@end

#pragma mark - 开关回调  (QQHeaders 里19个 QUIListCellConfigDelegate 实现类的共同签名)

@protocol QQTweakQUIListCellConfigDelegate <NSObject>
- (void)onSwitchValueChanged:(id)sender switchValue:(BOOL)switchValue;
@end

#pragma mark - 取QQ设置页的listView，用来抄样式  (QQHeaders/QQSettingsBaseViewController.h)

@protocol QQTweakQQSettingsVC <NSObject>
- (id)listView;
@end
