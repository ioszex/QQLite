//
//  QQTweakAboutViewController.m
//

#import "QQTweakAboutViewController.h"
#import "QQTweakPrefs.h"

@implementation QQTweakAboutViewController

+ (instancetype)aboutViewController {
	QQTweakAboutViewController *vc = [[self alloc] init];
	vc.pageTitle = @"关于";
	vc.showsBrandHeader = YES;

	NSString *hostVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	if (![hostVersion isKindOfClass:[NSString class]])
		hostVersion = @"未知";

	vc.sections = @[
		[QQTweakSection sectionWithHeader:nil
					     rows:@[
						     [QQTweakRow valueRowWithTitle:@"版本号" icon:nil tint:nil detail:QQTWEAK_VERSION],
						     [QQTweakRow valueRowWithTitle:@"开发者" icon:nil tint:nil detail:@"meo"],
						     [QQTweakRow valueRowWithTitle:@"包标识" icon:nil tint:nil detail:QQTWEAK_SUITE_NAME],
					     ]],
		[QQTweakSection sectionWithHeader:nil
					   footer:@"本插件仅用于学习和研究目的，请勿用于任何商业或违规用途。"
					     rows:@[
						     [QQTweakRow valueRowWithTitle:@"宿主版本" icon:nil tint:nil detail:hostVersion],
					     ]],
	];
	return vc;
}

@end
