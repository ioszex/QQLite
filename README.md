# QQTweak设置界面演示

## 项目概述

该项目演示了如何通过Hook技术向QQ设置界面中添加自定义设置项。通过分析和Hook QQ的UI组件层级与数据流，实现在不修改原始应用代码的情况下插入新的功能入口。

## 功能特点

- 在QQ设置界面添加"QQTweak"选项
- 点击后 push 进入二级设置页面（不是弹窗）
- 二级页面直接用QQ自己的 `QUIListView` 渲染，不是模仿——换肤、深色模式、字号都跟随QQ
- 弹窗用QQ自己的 `QUIAlertView`（经 `QUIBaseAlertViewController` 弹出）
- 开关状态持久化到独立的偏好文件，不污染QQ自身的 NSUserDefaults
- 支持继续 push 三级页面（示例：关于页）

## 文件结构

| 文件 | 作用 |
| --- | --- |
| `QQTweakDemo.xm` | Hook `QQNewSettingsViewProvider`，插入入口行并绑定跳转 |
| `QQTweakQUI.h` | QQ私有UI组件（QUIKit）的接口声明，全部用 `@protocol` 声明 |
| `QQTweakListBuilder.h/.m` | 把自己的行/分组模型翻译成 `QUIListSectionModel` / `QUIListSingleLineConfig` |
| `QQTweakSettingsViewController.h/.m` | 二级设置页面本体：模型定义、导航栏、跳转入口 |
| `QQTweakAboutViewController.h/.m` | 三级关于页面：品牌头部 + 版本/开发者/包标识/宿主版本（继承设置页复用列表渲染） |
| `QQTweakAlert.h/.m` | 封装QQ的 `QUIAlertView`，带系统弹窗回退 |
| `QQTweakPrefs.h/.m` | 偏好读写，存于 `com.meo.qqlite` |

列表本体全部由QQ的 `QUIListView` 渲染，没有任何自绘的 cell / 分割线 / 分组卡片。
只有导航栏、Toast、关于页顶部这三处仍是自绘，配色兜底直接内联在
`QQTweakSettingsViewController.m` 顶部（底色优先用从QQ设置页抄来的）。

## 用到的QQ私有类

从 `QQHeaders` 分析得到，全部经 `NSClassFromString` 取用：

| 类 | 用途 | 关键接口 |
| --- | --- | --- |
| `QUIListView` | 列表容器 | `initWithFrame:style:`、`reloadWithData:` |
| `QUIListSectionModel` | 分组 | `+sectionWithHeaderTitle:footerTitle:rowModelArray:` |
| `QUIListSingleLineConfig` | 单行配置 | `+configWithLeftStyle:rightStyle:` |
| `QUILeftTextIconStyle` | 左侧图标+标题 | `+styleWithTitle:image:`（继承自 `QUILeftTextAvatarStyle`） |
| `QUILeftTextStyle` | 左侧纯标题 | `+styleWithTitle:`、`+styleWithAttributedStrTitle:` |
| `QUIRightTextStyle` | 右侧详情+箭头 | `+styleWithDetailText:showRedPoint:showArrow:` |
| `QUIRightSwitchStyle` | 右侧开关 | `+styleWithSwitchOn:` |
| `QUIAlertView` | 弹窗 | `initWithTitle:message:delegate:cancelButtonTitle:otherButtonTitleArray:`、`show` |

### 两个坑

1. **开关回调**：`QUIListCellConfig.switchValueChangedBlock` 的 block 签名从头文件里看不出来，
   猜错会读到野指针。改走 `actionDelegate`，协议方法 `onSwitchValueChanged:switchValue:`
   在19个业务类里都能对上，签名是确定的。因为 `actionDelegate` 是 weak 且回调不带行标识，
   每个开关行单独配一个桥接对象直接捕获 row，页面用数组保活。

2. **弹窗生命周期**：`QUIBaseAlertViewController` 对 `alertView` 是 weak 持有，弹窗自身也没人 retain，
   ARC 会在方法返回时就把它释放掉。所以 `QQTweakAlert` 里用一个静态数组强引用住，
   `didDismissWithButtonIndex:` 回调时再放掉。

### 样式对齐

`QUIListView` 的 `style` / `seperatorStyle` / `topSpacing` / `sectionSpacing` 是枚举和数值，
头文件里查不到具体取值。做法是在跳转的瞬间从QQ设置页自己的 `listView`（`QQSettingsBaseViewController.listView`）
上把这几个值连同底色一起读出来照抄，这样间距和分割线跟QQ完全一致，不用猜。

`QQTweakSettingsViewController` 是数据驱动的：改 `buildMainSections` 里的
`QQTweakSection` / `QQTweakRow` 数组即可增删设置项，不需要动 UI 代码。

## 技术原理

整个数据流结构如下：
```
QQNewSettingsViewController
 └── viewProvider (QQNewSettingsViewProvider)
      └── setupDataSource() → NSArray<QUIListSectionModel>
           └── rowModelArray → NSArray<QUIListSingleLineConfig>
QUIListView
 └── dataArray 绑定 SectionModel
```

通过Hook `QQNewSettingsViewProvider` 的 `setupDataSource` 方法，该方法返回了设置页面所有选项的数据模型。项目在原始数据源基础上添加了自定义配置，修改返回值后UI自动更新。

### 核心类解析

- **QQNewSettingsViewController**: 设置页面主控制器
- **QQNewSettingsViewProvider**: 负责提供设置页面的数据源
- **QUIListView**: 列表视图组件，用于展示设置选项
- **QUIListSectionModel**: 列表分区模型
- **QUIListSingleLineConfig**: 单行列表项配置
- **QUIListItemStyle**: 列表项样式配置

## 实现细节

关键部分实现代码：

```objc
// Hook QQNewSettingsViewProvider类
%hook QQNewSettingsViewProvider
- (id)setupDataSource {
    id originalDataSource = %orig;
    
    // 在原有数据源基础上修改
    if ([originalDataSource isKindOfClass:[NSArray class]]) {
        NSArray *sectionsArray = (NSArray *)originalDataSource;
        if (sectionsArray.count > 1) {
            // 获取第二个分区
            id secondSection = sectionsArray[1];
            
            // 创建自定义配置
            id QQTweakModel = [[%c(QUIListSingleLineConfig) alloc] init];
            
            // 设置左侧样式
            id leftStyle = [[leftStyleClass alloc] init];
            [leftStyle setValue:@"QQTweak设置" forKey:@"title"];
            UIImage *icon = [UIImage systemImageNamed:@"gear"]; 
            [leftStyle setValue:icon forKey:@"image"];
            [QQTweakModel setValue:leftStyle forKey:@"leftStyle"];
            
            // 设置右侧样式
            id rightStyle = [[rightStyleClass alloc] init];
            [rightStyle setValue:@(YES) forKey:@"showArrow"];
            [rightStyle setValue:@"1.0.0" forKey:@"detailText"];
            [QQTweakModel setValue:rightStyle forKey:@"rightStyle"];
            
            // 将新配置添加到列表中
            QUIListSectionModel *sectionModel = (QUIListSectionModel *)secondSection;
            NSMutableArray *updatedRowModelArray = [sectionModel.rowModelArray mutableCopy];
            [updatedRowModelArray insertObject:QQTweakModel atIndex:0];
            sectionModel.rowModelArray = [updatedRowModelArray copy];
        }
    }
    
    return originalDataSource;
}
%end
```

## 工具函数

项目包含两个实用工具函数：

1. `dumpObjectProperties`: 通过运行时获取对象的所有属性及其值
2. `dumpClassInfo`: 提取类的完整接口定义，包括属性和方法

## 注意事项

- 本项目仅用于学习和研究目的
