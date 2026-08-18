//
//  QQTweakPrefs.m
//

#import "QQTweakPrefs.h"

NSString *const QQTweakKeyAntiRecall = @"antiRecall";

@implementation QQTweakPrefs

+ (NSUserDefaults *)defaults {
	static NSUserDefaults *defaults = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
	  defaults = [[NSUserDefaults alloc] initWithSuiteName:QQTWEAK_SUITE_NAME];
	  // 注册默认值，首次安装时的初始状态
	  [defaults registerDefaults:@{
		  QQTweakKeyAntiRecall : @NO,
	  }];
	});
	return defaults;
}

+ (BOOL)boolForKey:(NSString *)key {
	if (key.length == 0)
		return NO;
	return [[self defaults] boolForKey:key];
}

+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
	if (key.length == 0)
		return defaultValue;
	id value = [[self defaults] objectForKey:key];
	return value ? [value boolValue] : defaultValue;
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
	if (key.length == 0)
		return;
	[[self defaults] setBool:value forKey:key];
	[[self defaults] synchronize];
}

+ (void)resetAll {
	NSUserDefaults *defaults = [self defaults];
	for (NSString *key in @[ QQTweakKeyAntiRecall ]) {
		[defaults removeObjectForKey:key];
	}
	[defaults synchronize];
}

@end
