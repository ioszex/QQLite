//
//  QQTweakAntiRecall.xm
//  防撤回
//
//  QQ NT 的撤回机制：内核不发独立的撤回事件，而是把消息记录改掉
//  （OCMsgRecord.recallTime 置成撤回时间戳，elements 换成灰条元素，
//  msgType 改成 5/4），再通过监听器推给 UI。
//
//  所以这里做两件事：
//    1. 消息到达时把原始内容按 msgId 缓存下来
//    2. 发现撤回时把原文写回记录对象
//
//  两个层面都要拦：
//    - 监听器回调：救当前会话里那个内存对象
//    - OCMsgRecord 取值方法：退出重进时 AIO 会从数据库重新加载，
//      拿到的是全新对象，只能在读取时还原
//
//  已知限制：缓存在内存里，杀掉 QQ 进程后失效，之前撤回的消息会变回灰条。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "QQTweakPrefs.h"

static BOOL QQTweakAntiRecallEnabled(void) {
	return [QQTweakPrefs boolForKey:QQTweakKeyAntiRecall];
}

#pragma mark - NT 消息模型

// 字段取自 QQHeaders/OCMsgRecord.h
@protocol QQTweakOCMsgRecord <NSObject>
@property(nonatomic) long long msgId;
@property(nonatomic) int msgType;
@property(nonatomic) int subMsgType;
@property(nonatomic) long long recallTime; // 非0 表示这条已被撤回
@property(nonatomic, retain) NSArray *elements;
@end

// 字段取自 QQHeaders/OCMsgElement.h
@protocol QQTweakOCMsgElement <NSObject>
@property(nonatomic, retain) id grayTipElement;
@end

// 安全取值：属性不存在或类型对不上就返回默认值，不同QQ版本字段有出入也不会崩
static long long QQTweakLongLongValue(id object, SEL selector, long long fallback) {
	if (![object respondsToSelector:selector])
		return fallback;
	NSMethodSignature *signature = [object methodSignatureForSelector:selector];
	if (!signature || strcmp(signature.methodReturnType, @encode(long long)) != 0)
		return fallback;
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	invocation.selector = selector;
	[invocation invokeWithTarget:object];
	long long result = fallback;
	[invocation getReturnValue:&result];
	return result;
}

static int QQTweakIntValue(id object, SEL selector, int fallback) {
	if (![object respondsToSelector:selector])
		return fallback;
	NSMethodSignature *signature = [object methodSignatureForSelector:selector];
	if (!signature || strcmp(signature.methodReturnType, @encode(int)) != 0)
		return fallback;
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	invocation.selector = selector;
	[invocation invokeWithTarget:object];
	int result = fallback;
	[invocation getReturnValue:&result];
	return result;
}

#pragma mark - 原始内容缓存

// 内核是在通知我们之前就把记录改脏的，所以必须提前存一份原文，
// 撤回时才有东西可还原。按 msgId 索引，上限 500 条 FIFO 淘汰。

static NSMutableDictionary<NSNumber *, NSDictionary *> *QQTweakOriginalCache(void) {
	static NSMutableDictionary *cache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
	  cache = [NSMutableDictionary dictionary];
	});
	return cache;
}

static NSMutableArray<NSNumber *> *QQTweakCacheOrder(void) {
	static NSMutableArray *order = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
	  order = [NSMutableArray array];
	});
	return order;
}

static const NSUInteger kQQTweakCacheLimit = 500;

static void QQTweakCacheOriginal(id record) {
	if (![record respondsToSelector:@selector(msgId)] || ![record respondsToSelector:@selector(elements)])
		return;

	// 已经是撤回态的不缓存，否则会把灰条当成"原始内容"存进去
	if (QQTweakLongLongValue(record, @selector(recallTime), 0) != 0)
		return;

	NSArray *elements = [(id<QQTweakOCMsgRecord>)record elements];
	if (![elements isKindOfClass:[NSArray class]] || elements.count == 0)
		return;

	NSNumber *key = @(QQTweakLongLongValue(record, @selector(msgId), 0));
	if (key.longLongValue == 0)
		return;

	@synchronized(QQTweakOriginalCache()) {
		NSMutableDictionary *cache = QQTweakOriginalCache();
		NSMutableArray *order = QQTweakCacheOrder();

		if (!cache[key])
			[order addObject:key];

		cache[key] = @{
			@"elements" : elements,
			@"msgType" : @(QQTweakIntValue(record, @selector(msgType), 0)),
			@"subMsgType" : @(QQTweakIntValue(record, @selector(subMsgType), 0)),
		};

		while (order.count > kQQTweakCacheLimit) {
			[cache removeObjectForKey:order.firstObject];
			[order removeObjectAtIndex:0];
		}
	}
}

static void QQTweakCacheRecords(id payload) {
	if ([payload isKindOfClass:[NSArray class]]) {
		for (id record in (NSArray *)payload)
			QQTweakCacheOriginal(record);
	} else if (payload) {
		QQTweakCacheOriginal(payload);
	}
}

// 按 msgId 取缓存条目
static NSDictionary *QQTweakCachedEntry(id record) {
	if (![record respondsToSelector:@selector(msgId)])
		return nil;
	long long msgId = QQTweakLongLongValue(record, @selector(msgId), 0);
	if (msgId == 0)
		return nil;

	NSDictionary *entry = nil;
	@synchronized(QQTweakOriginalCache()) {
		entry = QQTweakOriginalCache()[@(msgId)];
	}
	return entry;
}

// 当前 elements 是不是灰条（廉价判断，不加锁）
static BOOL QQTweakElementsAreGrayTip(NSArray *elements) {
	if (![elements isKindOfClass:[NSArray class]] || elements.count == 0)
		return NO;
	id first = elements.firstObject;
	if (![first respondsToSelector:@selector(grayTipElement)])
		return NO;
	return [(id<QQTweakOCMsgElement>)first grayTipElement] != nil;
}

// 把撤回后的记录就地还原成原样。成功返回 YES。
static BOOL QQTweakRestoreOriginal(id record) {
	NSDictionary *saved = QQTweakCachedEntry(record);
	if (!saved)
		return NO;

	id<QQTweakOCMsgRecord> rec = record;
	if ([record respondsToSelector:@selector(setElements:)])
		rec.elements = saved[@"elements"];
	if ([record respondsToSelector:@selector(setMsgType:)])
		rec.msgType = [saved[@"msgType"] intValue];
	if ([record respondsToSelector:@selector(setSubMsgType:)])
		rec.subMsgType = [saved[@"subMsgType"] intValue];
	if ([record respondsToSelector:@selector(setRecallTime:)])
		rec.recallTime = 0;

	return YES;
}

#pragma mark - 更新列表处理

// 正常消息进缓存，撤回记录就地还原。
// 返回还原失败（缓存里没有原文）的记录，这些只能从列表里剔掉。
static NSArray *QQTweakProcessRecords(NSArray *records) {
	if (![records isKindOfClass:[NSArray class]] || records.count == 0)
		return nil;

	NSMutableArray *unrecoverable = nil;
	for (id record in records) {
		if (QQTweakLongLongValue(record, @selector(recallTime), 0) == 0) {
			QQTweakCacheOriginal(record);
			continue;
		}

		if (QQTweakRestoreOriginal(record))
			continue;

		// 缓存里没有原文（插件生效前收到的消息），只能剔除，
		// 至少不让 UI 收到"变灰条"的通知
		if ([record respondsToSelector:@selector(setRecallTime:)])
			[(id<QQTweakOCMsgRecord>)record setRecallTime:0];
		if (!unrecoverable)
			unrecoverable = [NSMutableArray array];
		[unrecoverable addObject:record];
	}
	return unrecoverable;
}

// 各个 onMsgInfoListUpdate: 共用。返回 YES 表示整批吞掉、调用方不要走 %orig。
static BOOL QQTweakHandleListUpdate(id msgList, NSArray **replacement) {
	*replacement = nil;
	if (!QQTweakAntiRecallEnabled() || ![msgList isKindOfClass:[NSArray class]])
		return NO;

	NSArray *records = (NSArray *)msgList;
	NSArray *unrecoverable = QQTweakProcessRecords(records);
	if (!unrecoverable)
		return NO; // 全部就地还原，原样放行让 UI 正常刷新

	NSMutableArray *kept = [records mutableCopy];
	for (id record in unrecoverable)
		[kept removeObjectIdenticalTo:record];

	if (kept.count == 0)
		return YES;
	*replacement = kept;
	return NO;
}

#pragma mark - 读取层还原：退出重进时数据从数据库来，对象是全新的

// 这几个 getter 在列表滚动时调用极频繁，所以每个都先做一次无锁的廉价判断，
// 普通消息在第一行就返回，不会去查缓存加锁。
//
// 注意：这四个方法之间不能互相调用，否则会绕回自己被 hook 的实现。

%hook OCMsgRecord

- (NSArray *)elements {
	NSArray *current = %orig;
	if (!QQTweakAntiRecallEnabled() || !QQTweakElementsAreGrayTip(current))
		return current;

	NSArray *original = QQTweakCachedEntry(self)[@"elements"];
	return [original isKindOfClass:[NSArray class]] && original.count > 0 ? original : current;
}

- (long long)recallTime {
	long long value = %orig;
	if (value == 0 || !QQTweakAntiRecallEnabled())
		return value;
	return QQTweakCachedEntry(self) ? 0 : value;
}

- (int)msgType {
	int value = %orig;
	if (value != 5 || !QQTweakAntiRecallEnabled()) // 5 = 灰条
		return value;
	NSDictionary *entry = QQTweakCachedEntry(self);
	return entry ? [entry[@"msgType"] intValue] : value;
}

- (int)subMsgType {
	int value = %orig;
	if (value != 4 || !QQTweakAntiRecallEnabled()) // 4 = 撤回灰条子类型
		return value;
	NSDictionary *entry = QQTweakCachedEntry(self);
	return entry ? [entry[@"subMsgType"] intValue] : value;
}

%end

#pragma mark - 内核消息监听器

// 实测生效的是 NTGuildMsgListener 和 GuildNTKernel.SWIKernelMsgListener，
// 其余几个没触发过，一并挂上兜底。

%hook KTIKernelMsgListener

- (void)onMsgInfoListUpdate:(id)msgList {
	NSArray *replacement = nil;
	if (QQTweakHandleListUpdate(msgList, &replacement))
		return;
	if (replacement) {
		%orig(replacement);
		return;
	}
	%orig;
}

- (void)onMsgInfoListAdd:(id)msgList {
	if (QQTweakAntiRecallEnabled())
		QQTweakCacheRecords(msgList);
	%orig;
}

- (void)onRecvMsg:(id)msgList {
	if (QQTweakAntiRecallEnabled())
		QQTweakCacheRecords(msgList);
	%orig;
}

- (void)onMsgRecall:(int)chatType peerUid:(id)peerUid seq:(unsigned long long)seq {
	if (QQTweakAntiRecallEnabled())
		return;
	%orig;
}

%end

%hook NTGuildMsgListener

- (void)onMsgInfoListUpdate:(id)msgList {
	NSArray *replacement = nil;
	if (QQTweakHandleListUpdate(msgList, &replacement))
		return;
	if (replacement) {
		%orig(replacement);
		return;
	}
	%orig;
}

- (void)onMsgInfoListAdd:(id)msgList {
	if (QQTweakAntiRecallEnabled())
		QQTweakCacheRecords(msgList);
	%orig;
}

- (void)onRecvMsg:(id)msgList {
	if (QQTweakAntiRecallEnabled())
		QQTweakCacheRecords(msgList);
	%orig;
}

- (void)onMsgRecall:(int)chatType peerUid:(id)peerUid seq:(unsigned long long)seq {
	if (QQTweakAntiRecallEnabled())
		return;
	%orig;
}

%end

%hook NTGameTempAioMsgListener

- (void)onMsgInfoListUpdate:(id)msgList {
	NSArray *replacement = nil;
	if (QQTweakHandleListUpdate(msgList, &replacement))
		return;
	if (replacement) {
		%orig(replacement);
		return;
	}
	%orig;
}

- (void)onMsgRecall:(int)chatType peerUid:(id)peerUid seq:(unsigned long long)seq {
	if (QQTweakAntiRecallEnabled())
		return;
	%orig;
}

%end

%hook ZTPSquareAIOMessageService

- (void)onMsgInfoListUpdate:(id)msgList {
	NSArray *replacement = nil;
	if (QQTweakHandleListUpdate(msgList, &replacement))
		return;
	if (replacement) {
		%orig(replacement);
		return;
	}
	%orig;
}

- (void)onMsgRecall:(int)chatType peerUid:(id)peerUid seq:(unsigned long long)seq {
	if (QQTweakAntiRecallEnabled())
		return;
	%orig;
}

%end

%hook ThirdAppUploadPicService

- (void)onMsgInfoListUpdate:(id)msgList {
	NSArray *replacement = nil;
	if (QQTweakHandleListUpdate(msgList, &replacement))
		return;
	if (replacement) {
		%orig(replacement);
		return;
	}
	%orig;
}

- (void)onMsgRecall:(int)chatType peerUid:(id)peerUid seq:(unsigned long long)seq {
	if (QQTweakAntiRecallEnabled())
		return;
	%orig;
}

%end

#pragma mark - 带点号的 Swift 类：只能运行时挂

// GuildNTKernel.SWIKernelMsgListener 类名含点号，不是合法标识符，
// Logos 的 %hook 语法上写不了，用 method_setImplementation 换实现。
// 实测这个类确实在处理单聊消息。

static void (*QQTweakOrigSwiftListUpdate)(id, SEL, id) = NULL;
static void (*QQTweakOrigSwiftRecall)(id, SEL, int, id, unsigned long long) = NULL;
static void (*QQTweakOrigSwiftListAdd)(id, SEL, id) = NULL;
static void (*QQTweakOrigSwiftRecvMsg)(id, SEL, id) = NULL;

static void QQTweakSwiftListUpdate(id self, SEL _cmd, id msgList) {
	NSArray *replacement = nil;
	if (QQTweakHandleListUpdate(msgList, &replacement))
		return;
	if (QQTweakOrigSwiftListUpdate)
		QQTweakOrigSwiftListUpdate(self, _cmd, replacement ?: msgList);
}

static void QQTweakSwiftRecall(id self, SEL _cmd, int chatType, id peerUid, unsigned long long seq) {
	if (QQTweakAntiRecallEnabled())
		return;
	if (QQTweakOrigSwiftRecall)
		QQTweakOrigSwiftRecall(self, _cmd, chatType, peerUid, seq);
}

static void QQTweakSwiftListAdd(id self, SEL _cmd, id msgList) {
	if (QQTweakAntiRecallEnabled())
		QQTweakCacheRecords(msgList);
	if (QQTweakOrigSwiftListAdd)
		QQTweakOrigSwiftListAdd(self, _cmd, msgList);
}

static void QQTweakSwiftRecvMsg(id self, SEL _cmd, id msgList) {
	if (QQTweakAntiRecallEnabled())
		QQTweakCacheRecords(msgList);
	if (QQTweakOrigSwiftRecvMsg)
		QQTweakOrigSwiftRecvMsg(self, _cmd, msgList);
}

static void QQTweakInstallSwiftListenerHooks(void) {
	Class cls = NSClassFromString(@"GuildNTKernel.SWIKernelMsgListener");
	if (!cls)
		return;

	// method_getImplementation 返回 IMP，直接转成目标函数指针类型。
	// 不能先转 void* 再赋值——函数指针和对象指针互转是约束违规，clang 会报 error。
	Method update = class_getInstanceMethod(cls, @selector(onMsgInfoListUpdate:));
	if (update) {
		QQTweakOrigSwiftListUpdate = (void (*)(id, SEL, id))method_getImplementation(update);
		method_setImplementation(update, (IMP)QQTweakSwiftListUpdate);
	}

	Method recall = class_getInstanceMethod(cls, NSSelectorFromString(@"onMsgRecall:peerUid:seq:"));
	if (recall) {
		QQTweakOrigSwiftRecall = (void (*)(id, SEL, int, id, unsigned long long))method_getImplementation(recall);
		method_setImplementation(recall, (IMP)QQTweakSwiftRecall);
	}

	Method listAdd = class_getInstanceMethod(cls, @selector(onMsgInfoListAdd:));
	if (listAdd) {
		QQTweakOrigSwiftListAdd = (void (*)(id, SEL, id))method_getImplementation(listAdd);
		method_setImplementation(listAdd, (IMP)QQTweakSwiftListAdd);
	}

	Method recvMsg = class_getInstanceMethod(cls, @selector(onRecvMsg:));
	if (recvMsg) {
		QQTweakOrigSwiftRecvMsg = (void (*)(id, SEL, id))method_getImplementation(recvMsg);
		method_setImplementation(recvMsg, (IMP)QQTweakSwiftRecvMsg);
	}
}

%ctor {
	%init;
	QQTweakInstallSwiftListenerHooks();
}
