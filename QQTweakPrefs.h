//
//  QQTweakPrefs.h
//  QQLite 偏好设置存储
//
//  所有开关写入 App 沙盒内的独立 plist，不污染 QQ 自己的 NSUserDefaults。
//

#import <Foundation/Foundation.h>

#define QQTWEAK_VERSION @"0.0.1"
#define QQTWEAK_SUITE_NAME @"com.meo.qqlite"

// 功能开关的 key
extern NSString *const QQTweakKeyAntiRecall;	   // 防撤回

@interface QQTweakPrefs : NSObject

+ (NSUserDefaults *)defaults;

// 读取，key 不存在时返回注册的默认值
+ (BOOL)boolForKey:(NSString *)key;
+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

// 恢复全部默认设置
+ (void)resetAll;

@end
