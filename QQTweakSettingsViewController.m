//
//  QQTweakSettingsViewController.m
//

#import "QQTweakSettingsViewController.h"
#import "QQTweakAboutViewController.h"
#import "QQTweakAlert.h"
#import "QQTweakListBuilder.h"
#import "QQTweakPrefs.h"
#import "QQTweakQUI.h"

#pragma mark - 少量自绘元素的配色

// 列表本体已经交给QQ的 QUIListView 了
static UIColor *QQTweakDynamicColor(uint32_t lightHex, CGFloat lightAlpha, uint32_t darkHex, CGFloat darkAlpha) {
	return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
	  uint32_t hex = (traits.userInterfaceStyle == UIUserInterfaceStyleDark) ? darkHex : lightHex;
	  CGFloat alpha = (traits.userInterfaceStyle == UIUserInterfaceStyleDark) ? darkAlpha : lightAlpha;
	  return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
				 green:((hex >> 8) & 0xFF) / 255.0
				  blue:(hex & 0xFF) / 255.0
				 alpha:alpha];
	}];
}

static UIColor *QQTweakPageBackgroundColor(void) {
	return QQTweakDynamicColor(0xF2F2F2, 1.0, 0x111111, 1.0);
}

static UIColor *QQTweakPrimaryTextColor(void) {
	return QQTweakDynamicColor(0x000000, 0.9, 0xFFFFFF, 0.9);
}

static UIColor *QQTweakSecondaryTextColor(void) {
	return QQTweakDynamicColor(0x000000, 0.4, 0xFFFFFF, 0.4);
}

static UIColor *QQTweakAccentColor(void) {
	return QQTweakDynamicColor(0x0099FF, 1.0, 0x0099FF, 1.0);
}

#pragma mark - 行模型

@implementation QQTweakRow

+ (instancetype)switchRowWithTitle:(NSString *)title icon:(NSString *)iconName tint:(UIColor *)tint prefKey:(NSString *)prefKey {
	QQTweakRow *row = [[self alloc] init];
	row.title = title;
	row.iconName = iconName;
	row.iconTintColor = tint;
	row.prefKey = prefKey;
	row.type = QQTweakRowTypeSwitch;
	return row;
}

+ (instancetype)disclosureRowWithTitle:(NSString *)title
				  icon:(NSString *)iconName
				  tint:(UIColor *)tint
				detail:(NSString *)detail
				action:(void (^)(UIViewController *host))action {
	QQTweakRow *row = [[self alloc] init];
	row.title = title;
	row.iconName = iconName;
	row.iconTintColor = tint;
	row.detail = detail;
	row.actionBlock = action;
	row.type = QQTweakRowTypeDisclosure;
	return row;
}

+ (instancetype)valueRowWithTitle:(NSString *)title icon:(NSString *)iconName tint:(UIColor *)tint detail:(NSString *)detail {
	QQTweakRow *row = [[self alloc] init];
	row.title = title;
	row.iconName = iconName;
	row.iconTintColor = tint;
	row.detail = detail;
	row.type = QQTweakRowTypeValue;
	return row;
}

+ (instancetype)buttonRowWithTitle:(NSString *)title destructive:(BOOL)destructive action:(void (^)(UIViewController *host))action {
	QQTweakRow *row = [[self alloc] init];
	row.title = title;
	row.destructive = destructive;
	row.actionBlock = action;
	row.type = QQTweakRowTypeButton;
	return row;
}

@end

#pragma mark - 分组模型

@implementation QQTweakSection

+ (instancetype)sectionWithHeader:(NSString *)header rows:(NSArray<QQTweakRow *> *)rows {
	return [self sectionWithHeader:header footer:nil rows:rows];
}

+ (instancetype)sectionWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray<QQTweakRow *> *)rows {
	QQTweakSection *section = [[self alloc] init];
	section.headerTitle = header;
	section.footerTitle = footer;
	section.rows = rows ?: @[];
	return section;
}

@end

#pragma mark - 页面

@interface QQTweakSettingsViewController ()
// QUIListView，QQ设置页用的就是这个组件
@property(nonatomic, strong) UIView *listView;
// 开关回调的桥接对象，QUI那边是weak持有，必须在这里保活
@property(nonatomic, strong) NSMutableArray *switchBridges;
@property(nonatomic, assign) BOOL previousNavigationBarHidden;
@property(nonatomic, weak) id previousPopGestureDelegate;
@property(nonatomic, assign) BOOL didCaptureNavigationState;

+ (NSArray<QQTweakSection *> *)buildMainSections;
- (void)reloadList;
- (void)confirmReset;
- (void)showToast:(NSString *)text;
@end

@implementation QQTweakSettingsViewController

#pragma mark - 页面构造

+ (instancetype)mainSettingsViewController {
	QQTweakSettingsViewController *vc = [[self alloc] init];
	vc.pageTitle = @"QQLite";
	vc.sections = [self buildMainSections];
	return vc;
}

+ (NSArray<QQTweakSection *> *)buildMainSections {
	QQTweakSection *feature = [QQTweakSection
	    sectionWithHeader:@"功能设置"
		       footer:@"开启后，别人撤回的消息不会从聊天里消失。"
			 rows:@[
				 [QQTweakRow switchRowWithTitle:@"防撤回"
							   icon:@"arrow.uturn.backward.circle.fill"
							   tint:[UIColor colorWithRed:0.15 green:0.60 blue:1.00 alpha:1.0]
							prefKey:QQTweakKeyAntiRecall],
			 ]];

	QQTweakSection *about = [QQTweakSection
	    sectionWithHeader:@"关于"
			 rows:@[
				 [QQTweakRow disclosureRowWithTitle:@"关于 QQLite"
							      icon:@"info.circle.fill"
							      tint:[UIColor colorWithRed:0.15 green:0.60 blue:1.00 alpha:1.0]
							    detail:QQTWEAK_VERSION
			    action:^(UIViewController *host) {
			      if ([host isKindOfClass:[QQTweakSettingsViewController class]]) {
				      [(QQTweakSettingsViewController *)host
					  pushViewController:[QQTweakAboutViewController aboutViewController]];
			      }
			    }],
			 ]];

	QQTweakSection *reset =
	    [QQTweakSection sectionWithHeader:nil
					 rows:@[
						 [QQTweakRow buttonRowWithTitle:@"恢复默认设置"
								    destructive:YES
									 action:^(UIViewController *host) {
									   if ([host isKindOfClass:[QQTweakSettingsViewController class]]) {
										   [(QQTweakSettingsViewController *)host confirmReset];
									   }
									 }],
					 ]];

	return @[ feature, about, reset ];
}

#pragma mark - 生命周期

- (void)viewDidLoad {
	[super viewDidLoad];

	_switchBridges = [NSMutableArray array];

	self.view.backgroundColor = [QQTweakListBuilder capturedBackgroundColor] ?: QQTweakPageBackgroundColor();
	self.title = self.pageTitle.length > 0 ? self.pageTitle : @"QQLite";

	[self setupNavigationBar];
	[self setupListView];
	[self reloadList];
}

- (void)setupNavigationBar {
	UIColor *barColor = [QQTweakListBuilder capturedBackgroundColor] ?: QQTweakPageBackgroundColor();
	UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
	[appearance configureWithOpaqueBackground];
	appearance.backgroundColor = barColor;
	appearance.shadowColor = [UIColor clearColor];
	appearance.titleTextAttributes = @{
		NSForegroundColorAttributeName : QQTweakPrimaryTextColor(),
		NSFontAttributeName : [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium],
	};
	self.navigationItem.standardAppearance = appearance;
	self.navigationItem.scrollEdgeAppearance = appearance;
	self.navigationItem.compactAppearance = appearance;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightMedium];
	UIImage *backImage = [[UIImage systemImageNamed:@"chevron.left" withConfiguration:config]
	    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:backImage
								    style:UIBarButtonItemStylePlain
								   target:self
								   action:@selector(handleBack)];
	backItem.tintColor = QQTweakPrimaryTextColor();
	self.navigationItem.leftBarButtonItem = backItem;
}

- (void)setupListView {
	_listView = [QQTweakListBuilder makeListViewWithFrame:self.view.bounds];
	if (!_listView)
		return;

	_listView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:_listView];

	if (self.showsBrandHeader) {
		UITableView *table = [self listTableView];
		if (table) {
			table.tableHeaderView = [self makeBrandHeaderView];
		}
	}
}

// 取 QUIListView 内部的 QUITableView
- (UITableView *)listTableView {
	if (![_listView respondsToSelector:@selector(tableView)])
		return nil;
	UITableView *table = [(id<QQTweakQUIListView>)_listView tableView];
	return [table isKindOfClass:[UITableView class]] ? table : nil;
}

- (void)reloadList {
	if (!_listView)
		return;

	[_switchBridges removeAllObjects];

	NSArray *dataArray = [QQTweakListBuilder buildDataArrayWithSections:self.sections host:self switchBridges:_switchBridges];
	[QQTweakListBuilder reloadListView:_listView withData:dataArray];
}

- (UIView *)makeBrandHeaderView {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, UIScreen.mainScreen.bounds.size.width, 168.0)];
	header.backgroundColor = [UIColor clearColor];

	CGFloat iconSize = 66.0;
	UIView *iconWrapper = [[UIView alloc] initWithFrame:CGRectMake((header.bounds.size.width - iconSize) / 2.0, 32.0, iconSize, iconSize)];
	iconWrapper.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	iconWrapper.backgroundColor = QQTweakAccentColor();
	iconWrapper.layer.cornerRadius = 15.0;
	iconWrapper.layer.cornerCurve = kCACornerCurveContinuous;
	[header addSubview:iconWrapper];

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:32.0 weight:UIImageSymbolWeightMedium];
	UIImageView *glyph = [[UIImageView alloc]
	    initWithImage:[[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
	glyph.tintColor = [UIColor whiteColor];
	glyph.contentMode = UIViewContentModeScaleAspectFit;
	glyph.frame = iconWrapper.bounds;
	[iconWrapper addSubview:glyph];

	UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, CGRectGetMaxY(iconWrapper.frame) + 14.0, header.bounds.size.width, 24.0)];
	nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	nameLabel.text = @"QQLite";
	nameLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightSemibold];
	nameLabel.textColor = QQTweakPrimaryTextColor();
	nameLabel.textAlignment = NSTextAlignmentCenter;
	[header addSubview:nameLabel];

	UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, CGRectGetMaxY(nameLabel.frame) + 4.0, header.bounds.size.width, 18.0)];
	versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	versionLabel.text = [NSString stringWithFormat:@"Version %@", QQTWEAK_VERSION];
	versionLabel.font = [UIFont systemFontOfSize:13.0];
	versionLabel.textColor = QQTweakSecondaryTextColor();
	versionLabel.textAlignment = NSTextAlignmentCenter;
	[header addSubview:versionLabel];

	return header;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	UINavigationController *nav = self.navigationController;
	if (!nav)
		return;

	if (!_didCaptureNavigationState) {
		_didCaptureNavigationState = YES;
		_previousNavigationBarHidden = nav.navigationBarHidden;
		if (nav.interactivePopGestureRecognizer) {
			_previousPopGestureDelegate = nav.interactivePopGestureRecognizer.delegate;
		}
	}

	if (nav.navigationBarHidden) {
		[nav setNavigationBarHidden:NO animated:animated];
	}

	if (nav.interactivePopGestureRecognizer) {
		nav.interactivePopGestureRecognizer.delegate = nil;
		nav.interactivePopGestureRecognizer.enabled = YES;
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	UINavigationController *nav = self.navigationController;
	if (!nav)
		return;

	if (self.isMovingFromParentViewController || self.isBeingDismissed) {
		if (nav.interactivePopGestureRecognizer && _previousPopGestureDelegate) {
			nav.interactivePopGestureRecognizer.delegate = _previousPopGestureDelegate;
		}
		if (_previousNavigationBarHidden) {
			[nav setNavigationBarHidden:YES animated:animated];
		}
		_didCaptureNavigationState = NO;
	}
}

- (UIStatusBarStyle)preferredStatusBarStyle {
	return UIStatusBarStyleDefault;
}

#pragma mark - 交互

- (void)handleBack {
	if (self.navigationController && self.navigationController.viewControllers.count > 1) {
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

- (void)pushViewController:(UIViewController *)viewController {
	if (!viewController)
		return;
	if (self.navigationController) {
		viewController.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:viewController animated:YES];
	} else {
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:viewController];
		nav.modalPresentationStyle = UIModalPresentationFullScreen;
		[self presentViewController:nav animated:YES completion:nil];
	}
}

- (void)confirmReset {
	// 用QQ自带的弹窗组件（QUIAlertView，内部经 QUIBaseAlertViewController 弹出）
	__weak typeof(self) weakSelf = self;
	[QQTweakAlert showWithTitle:@"恢复默认设置"
			    message:@"确定要将所有QQLite设置恢复为默认值吗？"
		       confirmTitle:@"恢复"
			destructive:YES
			cancelTitle:@"取消"
		 fromViewController:self
			  onConfirm:^{
			    __strong typeof(weakSelf) strongSelf = weakSelf;
			    if (!strongSelf)
				    return;
			    [QQTweakPrefs resetAll];
			    [strongSelf reloadList];
			    [strongSelf showToast:@"已恢复默认设置"];
			  }];
}

- (void)showToast:(NSString *)text {
	UILabel *toast = [[UILabel alloc] init];
	toast.text = text;
	toast.font = [UIFont systemFontOfSize:15.0];
	toast.textColor = [UIColor whiteColor];
	toast.textAlignment = NSTextAlignmentCenter;
	toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
	toast.layer.cornerRadius = 10.0;
	toast.layer.cornerCurve = kCACornerCurveContinuous;
	toast.layer.masksToBounds = YES;
	toast.alpha = 0.0;

	CGSize size = [toast sizeThatFits:CGSizeMake(self.view.bounds.size.width - 80.0, CGFLOAT_MAX)];
	CGFloat width = size.width + 32.0;
	CGFloat height = 40.0;
	toast.frame = CGRectMake((self.view.bounds.size.width - width) / 2.0, (self.view.bounds.size.height - height) / 2.0, width, height);
	[self.view addSubview:toast];

	[UIView animateWithDuration:0.2
	    animations:^{
	      toast.alpha = 1.0;
	    }
	    completion:^(BOOL finished) {
	      [UIView animateWithDuration:0.25
		  delay:1.2
		  options:UIViewAnimationOptionCurveEaseOut
		  animations:^{
		    toast.alpha = 0.0;
		  }
		  completion:^(BOOL done) {
		    [toast removeFromSuperview];
		  }];
	    }];
}

#pragma mark - 入口：从QQ设置页跳转过来

static UIViewController *QQTweakTopViewController(void) {
	UIWindow *keyWindow = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]])
			continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.isKeyWindow) {
				keyWindow = window;
				break;
			}
			if (!keyWindow && !window.hidden) {
				keyWindow = window;
			}
		}
		if (keyWindow && keyWindow.isKeyWindow)
			break;
	}
	if (!keyWindow) {
		keyWindow = UIApplication.sharedApplication.windows.firstObject;
	}

	UIViewController *top = keyWindow.rootViewController;
	while (YES) {
		if (top.presentedViewController) {
			top = top.presentedViewController;
		} else if ([top isKindOfClass:[UINavigationController class]]) {
			UIViewController *visible = ((UINavigationController *)top).topViewController;
			if (!visible)
				break;
			top = visible;
		} else if ([top isKindOfClass:[UITabBarController class]]) {
			UIViewController *selected = ((UITabBarController *)top).selectedViewController;
			if (!selected)
				break;
			top = selected;
		} else {
			break;
		}
	}
	return top;
}

+ (void)showSettings {
	dispatch_async(dispatch_get_main_queue(), ^{
	  UIViewController *top = QQTweakTopViewController();

	  [QQTweakListBuilder captureListStyleFromViewController:top];

	  QQTweakSettingsViewController *settings = [self mainSettingsViewController];

	  UINavigationController *nav = top.navigationController;
	  if (!nav && [top isKindOfClass:[UINavigationController class]]) {
		  nav = (UINavigationController *)top;
	  }

	  if (nav) {
		  settings.hidesBottomBarWhenPushed = YES;
		  [nav pushViewController:settings animated:YES];
	  } else if (top) {
		  UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:settings];
		  wrapper.modalPresentationStyle = UIModalPresentationFullScreen;
		  [top presentViewController:wrapper animated:YES completion:nil];
	  }
	});
}

@end
