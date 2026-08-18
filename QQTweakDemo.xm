#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "QQTweakPrefs.h"
#import "QQTweakSettingsViewController.h"

@interface QQNewSettingsViewProvider : NSObject
- (id)setupDataSource;
@end

@interface QUIListSectionModel : NSObject
@property(nonatomic, strong) NSArray *rowModelArray;
@end

@interface QUIListCellBaseModel : NSObject
@property(nonatomic, assign) NSInteger tag;
@property(nonatomic, strong) id bizData;
@property(nonatomic, assign) BOOL canEdit;
@property(nonatomic, assign) BOOL isEditing;
@property(nonatomic, copy) id didSelectBlock;
@property(nonatomic, copy) id willDisplayBlock;
@end

@interface QUIListCellConfig : QUIListCellBaseModel
@property(nonatomic, assign) NSInteger lineStyle;
@property(nonatomic, strong) id leftStyle;
@property(nonatomic, strong) id rightStyle;
@property(nonatomic, copy) NSString *cellReuseIdentifier;
@property(nonatomic, weak) id hostCell;
@property(nonatomic, weak) id actionDelegate;
@end

@interface QUIListSingleLineConfig : QUIListCellConfig
@end

@interface QUILeftTextIconStyle : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) UIImage *icon;
@end

@interface QUIRightTextStyle : NSObject
@property(nonatomic, copy) NSString *text;
@end

NSString *dumpObjectProperties(id obj);
NSString *dumpClassInfo(Class cls);

// Hook QQNewSettingsViewProvider类
%hook QQNewSettingsViewProvider
- (id)setupDataSource {
	id originalDataSource = %orig;

	// 检查返回值是否为NSArray
	if ([originalDataSource isKindOfClass:[NSArray class]]) {
		NSArray *sectionsArray = (NSArray *)originalDataSource;
		if (sectionsArray.count > 1) {
			// 获取第二项(索引为1)
			id secondSection = sectionsArray[1];

			// 检查这个section是否为QUIListSectionModel类型
			if ([secondSection isKindOfClass:%c(QUIListSectionModel)]) {
				QUIListSectionModel *sectionModel = (QUIListSectionModel *)secondSection;

				// 检查rowModelArray是否存在且至少有一项
				if (sectionModel.rowModelArray && sectionModel.rowModelArray.count > 0) {
					// setupDataSource 可能被多次调用，避免重复插入同一项
					for (id existingRow in sectionModel.rowModelArray) {
						NSString *existingTitle = nil;
						@try {
							// 行模型的类型不确定，KVC 取不到 key 时会抛异常
							id existingLeftStyle = [existingRow valueForKey:@"leftStyle"];
							existingTitle = [existingLeftStyle valueForKey:@"title"];
						} @catch (NSException *e) {
							continue;
						}
						if ([existingTitle isKindOfClass:[NSString class]] && [existingTitle isEqualToString:@"QQLite"]) {
							return originalDataSource;
						}
					}

					id QQTweakModel = nil;
					// 明确使用QUIListSingleLineConfig类
					Class modelClass = %c(QUIListSingleLineConfig);
					if (modelClass) {
						QQTweakModel = [[modelClass alloc] init];

						// 设置didSelectBlock：进入QQTweak二级设置页面
						if ([QQTweakModel respondsToSelector:@selector(setDidSelectBlock:)]) {
							id didSelectBlock = ^(id sender) {
							  [QQTweakSettingsViewController showSettings];
							};
							[QQTweakModel setValue:didSelectBlock forKey:@"didSelectBlock"];
						}

						// 添加左侧样式配置
						Class leftStyleClass = %c(QUILeftTextIconStyle);
						Class rightStyleClass = %c(QUIRightTextStyle);

						if (leftStyleClass && rightStyleClass) {
							// 创建左侧样式
							id leftStyle = [[leftStyleClass alloc] init];
							[leftStyle setValue:@"QQLite" forKey:@"title"];
							UIImage *icon = [[UIImage systemImageNamed:@"gear"] imageWithTintColor:[UIColor colorWithRed:33.0 / 255.0
																	       green:33.0 / 255.0
																		blue:33.0 / 255.0
																	       alpha:1.0]
														 renderingMode:UIImageRenderingModeAlwaysOriginal];
							[leftStyle setValue:icon forKey:@"image"];

							// 设置leftStyle
							[QQTweakModel setValue:leftStyle forKey:@"leftStyle"];

							// 创建右侧样式
							id rightStyle = [[rightStyleClass alloc] init];

							// 设置箭头
							[rightStyle setValue:@(YES) forKey:@"showArrow"];

							// 设置详细文本
							[rightStyle setValue:QQTWEAK_VERSION forKey:@"detailText"];

							// 设置rightStyle
							[QQTweakModel setValue:rightStyle forKey:@"rightStyle"];
						}

						// 设置willDisplayBlock
						if ([QQTweakModel respondsToSelector:@selector(setWillDisplayBlock:)]) {
							id willDisplayBlock = ^(id cell) {
							};
							[QQTweakModel setValue:willDisplayBlock forKey:@"willDisplayBlock"];
						}
					}

					if (QQTweakModel) {
						NSMutableArray *updatedRowModelArray = [sectionModel.rowModelArray mutableCopy];
						[updatedRowModelArray insertObject:QQTweakModel atIndex:0];
						sectionModel.rowModelArray = [updatedRowModelArray copy];
					}

					// 返回修改后的原始数组
					return originalDataSource;
				}
			}
		}
	}

	return originalDataSource;
}

%end

// 添加一个函数来获取对象的属性值
NSString *dumpObjectProperties(id obj) {
	if (!obj)
		return @"对象为空";

	Class cls = object_getClass(obj);
	NSMutableString *result = [NSMutableString stringWithFormat:@"对象类型: %s 的实例数据:\n", class_getName(cls)];

	// 获取所有属性
	unsigned int propertyCount;
	objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);

	for (unsigned int i = 0; i < propertyCount; i++) {
		objc_property_t property = properties[i];
		const char *name = property_getName(property);
		NSString *propertyName = [NSString stringWithUTF8String:name];

		// 尝试通过KVC获取属性值
		id value = nil;
		@try {
			value = [obj valueForKey:propertyName];
			if (value) {
				if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
					[result appendFormat:@"%@ = %@\n", propertyName, value];
				} else {
					[result appendFormat:@"%@ = <%@对象>\n", propertyName, [value class]];
				}
			} else {
				[result appendFormat:@"%@ = nil\n", propertyName];
			}
		} @catch (NSException *e) {
			[result appendFormat:@"%@ = <无法访问>\n", propertyName];
		}
	}

	if (properties)
		free(properties);
	return result;
}

NSString *dumpClassInfo(Class cls) {
	if (!cls)
		return @"类不存在";

	NSMutableString *result = [NSMutableString stringWithFormat:@"@interface %s : %s\n", class_getName(cls), class_getName(class_getSuperclass(cls))];

	// 获取所有属性
	unsigned int propertyCount;
	objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);

	for (unsigned int i = 0; i < propertyCount; i++) {
		objc_property_t property = properties[i];
		const char *name = property_getName(property);
		const char *attributes = property_getAttributes(property);

		NSString *type = @"id";
		if (attributes) {
			NSString *attrStr = [NSString stringWithUTF8String:attributes];
			NSArray *attrComponents = [attrStr componentsSeparatedByString:@","];
			if (attrComponents.count > 0) {
				NSString *typeComponent = attrComponents[0];
				if ([typeComponent hasPrefix:@"T"]) {
					NSString *typeStr = [typeComponent substringFromIndex:1];
					if ([typeStr hasPrefix:@"@\""] && [typeStr hasSuffix:@"\""]) {
						type = [typeStr substringWithRange:NSMakeRange(2, typeStr.length - 3)];
					} else if ([typeStr isEqualToString:@"i"]) {
						type = @"NSInteger";
					} else if ([typeStr isEqualToString:@"f"]) {
						type = @"float";
					} else if ([typeStr isEqualToString:@"d"]) {
						type = @"double";
					} else if ([typeStr isEqualToString:@"B"]) {
						type = @"BOOL";
					} else {
						type = typeStr;
					}
				}
			}
		}

		[result appendFormat:@"@property (nonatomic) %@ %s;\n", type, name];
	}

	if (properties)
		free(properties);

	// 获取所有实例方法
	unsigned int methodCount;
	Method *methods = class_copyMethodList(cls, &methodCount);

	for (unsigned int i = 0; i < methodCount; i++) {
		Method method = methods[i];
		SEL selector = method_getName(method);
		const char *name = sel_getName(selector);
		[result appendFormat:@"- (%@)%s;\n", @"id", name];
	}

	if (methods)
		free(methods);

	// 获取所有类方法
	methodCount = 0;
	methods = class_copyMethodList(object_getClass(cls), &methodCount);

	for (unsigned int i = 0; i < methodCount; i++) {
		Method method = methods[i];
		SEL selector = method_getName(method);
		const char *name = sel_getName(selector);
		// 过滤掉Objective-C运行时自动生成的方法
		if (strncmp(name, ".cxx_", 5) != 0 && strcmp(name, "load") != 0 && strcmp(name, "initialize") != 0) {
			[result appendFormat:@"+ (%@)%s;\n", @"id", name];
		}
	}

	if (methods)
		free(methods);

	[result appendString:@"@end\n"];
	return result;
}

// 修改%ctor块，在初始化时提取QUIListItemStyle类信息
%ctor {
	%init;
}
