//
//  QQTweakListBuilder.m
//

#import "QQTweakListBuilder.h"
#import "QQTweakPrefs.h"
#import "QQTweakQUI.h"
#import "QQTweakSettingsViewController.h"

#pragma mark - 开关回调桥接

// QUIListCellConfig.actionDelegate 是 weak 的，而且回调只给一个 sender，
// 不好反查是哪一行。所以每个开关行单独配一个桥接对象，直接把 row 捕获进来，
// 回调时不需要再做任何查找。桥接对象由页面用数组保活。
@interface QQTweakSwitchBridge : NSObject <QQTweakQUIListCellConfigDelegate>
@property(nonatomic, strong) QQTweakRow *row;
@end

@implementation QQTweakSwitchBridge

- (void)onSwitchValueChanged:(id)sender switchValue:(BOOL)switchValue {
	if (self.row.prefKey.length > 0) {
		[QQTweakPrefs setBool:switchValue forKey:self.row.prefKey];
	}
	if (self.row.switchChangedBlock) {
		self.row.switchChangedBlock(switchValue);
	}
}

@end

#pragma mark -

static BOOL sHasCapturedStyle = NO;
static unsigned long long sListStyle = 0;
static unsigned long long sSeperatorStyle = 0;
static double sTopSpacing = 0.0;
static double sSectionSpacing = 0.0;
static UIColor *sBackgroundColor = nil;

@implementation QQTweakListBuilder

+ (BOOL)isAvailable {
	return NSClassFromString(@"QUIListView") != nil && NSClassFromString(@"QUIListSectionModel") != nil &&
	       NSClassFromString(@"QUIListSingleLineConfig") != nil;
}

#pragma mark - QQ设置页的样式

+ (void)captureListStyleFromViewController:(UIViewController *)viewController {
	if (sHasCapturedStyle || !viewController)
		return;
	if (![viewController respondsToSelector:@selector(listView)])
		return;

	id listView = [(id<QQTweakQQSettingsVC>)viewController listView];
	if (![listView isKindOfClass:NSClassFromString(@"QUIListView")])
		return;

	id<QQTweakQUIListView> list = listView;
	if ([list respondsToSelector:@selector(style)])
		sListStyle = [list style];
	if ([list respondsToSelector:@selector(seperatorStyle)])
		sSeperatorStyle = [list seperatorStyle];
	if ([list respondsToSelector:@selector(topSpacing)])
		sTopSpacing = [list topSpacing];
	if ([list respondsToSelector:@selector(sectionSpacing)])
		sSectionSpacing = [list sectionSpacing];
	if ([list respondsToSelector:@selector(tableView)]) {
		UITableView *table = [list tableView];
		sBackgroundColor = table.backgroundColor ?: ((UIView *)listView).backgroundColor;
	}

	sHasCapturedStyle = YES;
}

+ (UIColor *)capturedBackgroundColor {
	return sBackgroundColor;
}

#pragma mark - 造列表

+ (UIView *)makeListViewWithFrame:(CGRect)frame {
	Class listClass = NSClassFromString(@"QUIListView");
	if (!listClass)
		return nil;

	id<QQTweakQUIListView> list = [listClass alloc];

	if (sHasCapturedStyle && [listClass instancesRespondToSelector:@selector(initWithFrame:style:)]) {
		list = [list initWithFrame:frame style:sListStyle];
	} else {
		list = [list initWithFrame:frame];
	}
	if (!list)
		return nil;

	if (sHasCapturedStyle) {
		if ([list respondsToSelector:@selector(setSeperatorStyle:)])
			[list setSeperatorStyle:sSeperatorStyle];
		if (sTopSpacing > 0.0 && [list respondsToSelector:@selector(setTopSpacing:)])
			[list setTopSpacing:sTopSpacing];
		if (sSectionSpacing > 0.0 && [list respondsToSelector:@selector(setSectionSpacing:)])
			[list setSectionSpacing:sSectionSpacing];
	}

	return (UIView *)list;
}

+ (void)reloadListView:(UIView *)listView withData:(NSArray *)data {
	if (!listView)
		return;

	id<QQTweakQUIListView> list = (id<QQTweakQUIListView>)listView;
	if ([list respondsToSelector:@selector(reloadWithData:)]) {
		[list reloadWithData:(data ?: @[])];
	} else if ([listView respondsToSelector:@selector(setDataArray:)]) {
		[listView setValue:(data ?: @[]) forKey:@"dataArray"];
		if ([list respondsToSelector:@selector(reloadData)])
			[list reloadData];
	}
}

#pragma mark - 造数据

+ (NSArray *)buildDataArrayWithSections:(NSArray<QQTweakSection *> *)sections
				   host:(UIViewController *)host
			  switchBridges:(NSMutableArray *)switchBridges {
	Class sectionClass = NSClassFromString(@"QUIListSectionModel");
	Class configClass = NSClassFromString(@"QUIListSingleLineConfig");
	if (!sectionClass || !configClass)
		return @[];

	NSMutableArray *dataArray = [NSMutableArray array];

	for (QQTweakSection *section in sections) {
		NSMutableArray *rowModels = [NSMutableArray array];

		for (QQTweakRow *row in section.rows) {
			id config = [self configForRow:row configClass:configClass host:host switchBridges:switchBridges];
			if (config)
				[rowModels addObject:config];
		}

		if (rowModels.count == 0)
			continue;

		id sectionModel = [(Class<QQTweakQUISectionModelClass>)sectionClass sectionWithHeaderTitle:section.headerTitle
											      footerTitle:section.footerTitle
											    rowModelArray:rowModels];
		if (sectionModel)
			[dataArray addObject:sectionModel];
	}

	return dataArray;
}

+ (id)configForRow:(QQTweakRow *)row
       configClass:(Class)configClass
	      host:(UIViewController *)host
     switchBridges:(NSMutableArray *)switchBridges {
	id leftStyle = [self leftStyleForRow:row];
	if (!leftStyle)
		return nil;
	id rightStyle = [self rightStyleForRow:row];

	id<QQTweakQUIListConfig> config = [(Class<QQTweakQUIListConfigClass>)configClass configWithLeftStyle:leftStyle rightStyle:rightStyle];
	if (!config)
		return nil;

	if (row.type == QQTweakRowTypeSwitch) {
		// 开关：走 actionDelegate 的 onSwitchValueChanged:switchValue:
		QQTweakSwitchBridge *bridge = [[QQTweakSwitchBridge alloc] init];
		bridge.row = row;
		[switchBridges addObject:bridge];
		if ([config respondsToSelector:@selector(setActionDelegate:)]) {
			[config setActionDelegate:bridge];
		}
	} else if (row.actionBlock) {
		// 点击：走 didSelectBlock，签名沿用原有 hook 里已验证可用的 ^(id sender)
		__weak UIViewController *weakHost = host;
		QQTweakRow *capturedRow = row;
		id didSelectBlock = ^(id sender) {
		  __strong UIViewController *strongHost = weakHost;
		  if (strongHost && capturedRow.actionBlock)
			  capturedRow.actionBlock(strongHost);
		};
		if ([config respondsToSelector:@selector(setDidSelectBlock:)]) {
			[config setDidSelectBlock:didSelectBlock];
		}
	}

	return config;
}

+ (id)leftStyleForRow:(QQTweakRow *)row {
	Class textStyleClass = NSClassFromString(@"QUILeftTextStyle");

	if (row.destructive && textStyleClass && [textStyleClass respondsToSelector:@selector(styleWithAttributedStrTitle:)]) {
		NSAttributedString *attributed =
		    [[NSAttributedString alloc] initWithString:(row.title ?: @"")
						    attributes:@{NSForegroundColorAttributeName : [UIColor colorWithRed:0.98
																green:0.32
																 blue:0.32
																alpha:1.0]}];
		id style = [(Class<QQTweakQUILeftTextStyleClass>)textStyleClass styleWithAttributedStrTitle:attributed];
		if (style)
			return style;
	}

	UIImage *icon = [self iconImageForRow:row];

	if (icon) {
		Class iconStyleClass = NSClassFromString(@"QUILeftTextIconStyle");
		if (iconStyleClass && [iconStyleClass respondsToSelector:@selector(styleWithTitle:image:)]) {
			id style = [(Class<QQTweakQUILeftIconStyleClass>)iconStyleClass styleWithTitle:row.title image:icon];
			if (style)
				return style;
		}
	}

	if (textStyleClass && [textStyleClass respondsToSelector:@selector(styleWithTitle:)]) {
		return [(Class<QQTweakQUILeftTextStyleClass>)textStyleClass styleWithTitle:row.title];
	}
	return nil;
}

+ (id)rightStyleForRow:(QQTweakRow *)row {
	if (row.type == QQTweakRowTypeSwitch) {
		Class switchStyleClass = NSClassFromString(@"QUIRightSwitchStyle");
		if (switchStyleClass && [switchStyleClass respondsToSelector:@selector(styleWithSwitchOn:)]) {
			return [(Class<QQTweakQUIRightSwitchStyleClass>)switchStyleClass styleWithSwitchOn:[QQTweakPrefs boolForKey:row.prefKey]];
		}
		return nil;
	}

	Class textStyleClass = NSClassFromString(@"QUIRightTextStyle");
	if (textStyleClass && [textStyleClass respondsToSelector:@selector(styleWithDetailText:showRedPoint:showArrow:)]) {
		return [(Class<QQTweakQUIRightTextStyleClass>)textStyleClass styleWithDetailText:row.detail
										   showRedPoint:NO
										      showArrow:(row.type == QQTweakRowTypeDisclosure)];
	}
	return nil;
}

+ (UIImage *)iconImageForRow:(QQTweakRow *)row {
	if (row.iconName.length == 0)
		return nil;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightMedium];
	UIImage *symbol = [UIImage systemImageNamed:row.iconName withConfiguration:config];
	if (!symbol)
		return nil;

	UIColor *tint = row.iconTintColor ?: [UIColor colorWithRed:0.15 green:0.60 blue:1.00 alpha:1.0];
	return [symbol imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
}

@end
