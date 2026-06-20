# 三省小记（sanxing）— 架构说明

时间块记录 + 日记的 iOS App。SwiftUI + SwiftData 原生构建。

- 用户可见名：**三省小记**（`INFOPLIST_KEY_CFBundleDisplayName`，取自曾子「吾日三省吾身」）。工程/scheme/target/bundle 内部标识为 `sanxing`，bundle id `com.xhy.sanxing`。
- 远端：`https://github.com/XhyEax/sanxing_ios`（本地仓库根目录仍名 `rixing`，未随工程改名）。
- 部署目标 iOS 17，版本 1.0。
- 设计范式参考姊妹项目「逍遥居笔记」（xiaoyaoju），但**不共享代码**（不引本地 Swift Package）。

## 构建

工程使用 **文件系统同步组**（`PBXFileSystemSynchronizedRootGroup`）——`sanxing/` 下增删 `.swift` 文件无需改 `project.pbxproj`，直接放进文件夹即可。

本机仅有命令行工具，但装了 **Xcode-beta**，用它编译验证：

```bash
cd /Users/xhy/Documents/git/rixing
export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
xcodebuild -scheme sanxing -destination 'generic/platform=iOS Simulator' build
```

> 编辑器里满屏的 SourceKit「Cannot find type / Ambiguous Query / 找不到宏」是工程外单文件解析的噪音，以真实 `xcodebuild` 结果为准（`** BUILD SUCCEEDED **`）。无法跑模拟器实测，手势类交互需在 Xcode 真机/模拟器手动验证。

## 目录结构

```
sanxing/
  sanxingApp.swift       @main：ModelContainer([TimeBlock, DiaryEntry, CustomCategory]) + 主题 preferredColorScheme
  ContentView.swift      MainTabView（4 个 Tab）；ContentView 仅作模板兼容壳
  Models/
    TimeBlock.swift        时间块 @Model + BlockCategory（内置分类枚举：颜色/图标/名称）
    DiaryEntry.swift       日记 @Model + Mood（心情 emoji）
    CustomCategory.swift   用户自定义分类 @Model（id/name/colorHex/icon/sortOrder）
    CategoryStyle.swift    分类样式统一解析（CatStyle/catStyle/allCatStyles）+ Color↔hex + 色板/图标库
    DateExt.swift          Date 扩展（startOfDay/addingDays/isSameDay/hm/dayTitle）+ formatDuration
  Views/
    TimelineView.swift       今日：整点时间轴（核心交互最复杂）
    TimeBlockEditorView.swift  时间块 新建/编辑（init(day:hour:) / init(block:)）
    CategoryPicker.swift     可复用分类网格 CategoryGrid + 自定义标签编辑器 CustomCategoryEditor
    ClockDialPicker.swift    24 小时表盘（拖两个把手改 start/end，0 在正上、顺时针）
    DiaryView.swift          日记：按天分组倒序
    DiaryEditorView.swift    日记 新建/编辑（init() / init(entry:)）
    StatsView.swift          统计：今日各分类时长占比
    SettingsView.swift       设置：主题切换 + 关于
```

## 数据模型

**TimeBlock**（SwiftData @Model）
- `start: Date` / `end: Date` / `title: String` / `category: String` / `note: String`
- 计算属性：`duration`（秒）、`cat: BlockCategory`（旧的内置解析，新代码一律走 `catStyle`，勿再用）
- `category` 存**分类 key**：内置 = `BlockCategory.rawValue`；自定义 = `CustomCategory.id`（UUID 串，不会撞内置）。时间块「计划/记录」通用，无独立状态字段。

**BlockCategory**（enum String）：`work/study/rest/exercise/life/fun/phone/reading/code/writing/other`，各带 `name`（中文）、`color`、`icon`（SF Symbol）。内置一组（颜色已用满，再加会撞色——所以加了自定义分类）。

**CustomCategory**（SwiftData @Model）：用户自定义分类。`id`（=存进 TimeBlock.category 的 key）/`name`/`colorHex`（`#RRGGBB`）/`icon`（SF Symbol）/`sortOrder`。删除后旧块解析时兜底「其他」。

**分类样式解析（`CategoryStyle.swift`）**：内置与自定义统一成 `CatStyle{key,name,icon,color}`。所有展示分类的地方（卡片/统计/选择器）都用 `catStyle(for: key, custom: customCats)` 解析单个 key、`allCatStyles(custom:)` 列全部可选项（内置 allCases 在前、自定义按 sortOrder 排在 `other` 右边）。视图各自 `@Query var customCats: [CustomCategory]`。`Color(hex:)`/`toHexString()` 给 ColorPicker 存取色值。

**DiaryEntry**（SwiftData @Model）
- `createdAt: Date` / `text: String` / `mood: Int`（0=未设，1…5）
- 一天可多条。`Mood.emoji(_:)` 把 1…5 映射到 😣😕😐🙂😄。

> **CloudKit 同步约束**：三个 @Model（含 `CustomCategory`）的**每个存储属性都带默认值**（`var x: T = ...`）。这是 SwiftData↔CloudKit 镜像的硬性要求（属性必须可选或有默认值），实际值仍由 `init` 覆盖，别删默认值。不能用 `@Attribute(.unique)`、关系必须可选（目前无关系）。

## iCloud / CloudKit 同步

数据「**本地存一份 + 云端存一份**」：`sanxingApp` 用 `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.xhy.sanxing"))`，底层 `NSPersistentCloudKitContainer` 始终保留本地 SQLite 副本并镜像到 iCloud 私有库——**切 iCloud 账号本地数据不会丢**。云容器初始化失败（未登录/未配好）时**兜底退回纯本地** `.none`，保证 App 不崩、本地那份永远在。

- 容器 ID：`iCloud.com.xhy.sanxing`（`sanxing/sanxing.entitlements` 的 `icloud-container-identifiers`）。
- 后台同步推送：`UIBackgroundModes = [remote-notification]`，放在**仓库根** `Info.plist`（`INFOPLIST_FILE = Info.plist`）。**不能放进 `sanxing/` 同步组**——文件系统同步组会把它自动加进 Copy Bundle Resources，与生成的 Info.plist 冲突（"Multiple commands produce Info.plist"）。其余 plist 键仍由 `GENERATE_INFOPLIST_FILE` 合并注入。
- **首次真机联调**：CloudKit 开发环境会按 schema 自动建记录类型（含新增的 `CustomCategory`）；**上架前**须在 CloudKit Dashboard 把 schema 部署到 Production。命令行只能 `xcodebuild` 验证编译，实际同步/双账号需真机手测。

## 关键约定与范式

- **TabView + 每 Tab 各自 NavigationStack**（同逍遥居）。
- 编辑器统一用 `.sheet(item:)`（编辑已有）+ `.sheet(isPresented:)`/`.sheet(item:)`（新建），编辑器内含 `init` 区分新建/编辑。日记编辑器仍用底部「删除」段；**时间块编辑器**已把删除挪到右上角「保存」**左侧**的垃圾桶图标（仅编辑态）。
- **时间块编辑器**（`TimeBlockEditorView`）表单顺序：标题 → 备注 → 分类 → 时间。时间区含 时长预设 + 开始/结束 DatePicker + **24 小时表盘** `ClockDialPicker`（拖把手改起止，仿健康 App）。三者互不牵连：改开始不再平移整段（去掉了 `onChange(of:start)`），只有时长预设会 `end = start + 时长`。表盘逻辑见下。
- 主题：`@AppStorage("appColorScheme")`（0 跟随系统 / 1 浅 / 2 深），在 `sanxingApp` 用 `preferredColorScheme` 应用。
- 列表查询用 `@Query`，**按天过滤在内存里做**（`allBlocks.filter { $0.start.isSameDay(as: day) }`），数据量小不建动态谓词。

## 今日时间轴（TimelineView）— 交互重点

默认把一天切成 **24 个整点 1 小时槽**（0:00–23:00），是产品核心形态。

- 用 `ScrollView + LazyVStack`（**不是 List**）——List 内拖拽选择会与滚动冲突。
- 每个整点一行：左侧钟点（`lineLimit(1)+fixedSize`，任意 Dynamic Type 都单行）；右侧若该整点有块（按 `start` 的小时归类）则展示块卡片，否则显示「空闲 ＋」。
- 看「今天」时 `ScrollViewReader` 自动滚到当前钟点并高亮。
- 左侧整点时间务必保持单行：`Text(...).lineLimit(1).fixedSize(horizontal: true, vertical: false)`，列宽用 `minWidth` 不用固定 `width`（大字号会截断）。
- 顶栏（非多选态）：左上**日历按钮** → sheet 里的 graphical `DatePicker`（zh_CN，含「今天」）跳转 `selectedDay`；中间日期前后导航 `dayNav`；右上「选择」进多选。

### 分类选择（编辑器 & 填充 共用 CategoryGrid）

- `CategoryGrid`（`Views/CategoryPicker.swift`）渲染 `allCatStyles`：内置 + 自定义 + 末尾「＋ 自定义」格。自定义格**长按**出 contextMenu 可编辑/删除。编辑器传 `selectedKey` 做高亮、填充菜单传 `nil`。
- 「＋ 自定义」开 `CustomCategoryEditor`（名称 + 色板/`ColorPicker` + 图标网格），保存即 insert `CustomCategory` 并通过 `onSave` 回调让调用方直接选中/使用。
- 填充菜单从旧的 `confirmationDialog`（纯文字）改成 `.sheet` 内嵌 `CategoryGrid`，与编辑器视觉一致。

### 时间块编辑器表盘（ClockDialPicker）

- 24 小时环：**0 在正上方、顺时针**（6 右 / 12 下 / 18 左，同健康 App）。坐标 `point(t)`：`x=c.x+r·sin(t/24·2π)`、`y=c.y−r·cos(t/24·2π)`；反向命中 `atan2(dx, −dy)`。
- 选中弧用单段 `Circle().trim(from:0,to:时长/24)` + `.rotationEffect(开始/24·360−90°)` 旋到位——避免跨 0 点的圆弧接缝。
- 两把手按category色显示（start 用分类图标）。拖拽时按触点就近锁定把手；**拖 start 保持 end、拖 end 保持 start**，时长锁在 0…24h，end 可取 start 之后最近时刻 → 天然支持跨午夜。snap 到 5 分钟。
- 与 `TimelineView.propagateCrossDay` 配合：表盘把块拖成跨午夜后，回到今日 `afterEdit` 会在次日按空闲复制。

### 跨天复制（propagateCrossDay）

- 块跨午夜（`end > start 当天的次日 0 点`）时，在其后每个被覆盖的日子按**空闲时段**复制一份同类块（`title/category/note` 相同），**只填空闲、不覆盖已有块**（`copyIntoFreeSlots` 挖掉与已有块重叠的部分）。**不拆原块**——原块仍按 `start` 归在起始日。
- 幂等：副本本身不跨天，重跑（每次编辑器 `onDismiss` 的 `afterEdit` 都会调）时旧副本已占槽 → 自动跳过、不重复建。
- 已知局限：事后把块改短/删除，之前生成的次日副本不会自动回收（无法区分自动副本与手动块）。

### 选择与批量操作

- **进入多选**：右上「选择」按钮，或**长按任意行**（`LongPressGesture(0.3).sequenced(before: DragGesture)`）。长按后不抬手**上下滑动**连续选中（以长按行为锚点，选锚点→当前行的范围）。快速点按（<0.3s）不触发选择，仍是编辑块/新建空闲。
- 拖拽命中靠每行上报 frame（`RowFrameKey` PreferenceKey + `.coordinateSpace(name:"timeline")`），`hour(at:)` 按 y 命中。
- 两套选中集：`selected: Set<PersistentIdentifier>`（真实块）、`selectedHours: Set<Int>`（空闲整点）。
- 底部工具栏（多选态，`.bottomBar`）按上下文出现：
  - **填充**：选中空闲整点 → 弹 `CategoryGrid` 选分类后各建 1 小时块（`fillSelectedHours(with: key)`）。
  - **合并**：仅当「恰好 1 个块 + 若干空闲」被选中（`canMerge`）→ 把该块拉长覆盖整段（`mergeSelected`，保留块原有更早起/更晚止）。
  - **删除**：删选中的真实块。
- 左上「全选/取消全选」**只覆盖空闲整点**（不动用户手动选中的块），`allSelected`/`toggleSelectAll` 都只看 `emptyHours`。

## App 图标

文字图标「三省」（横排两字，App 名「三省小记」的缩写）：1024×1024，靛蓝竖向渐变 + 白色宋体（STSongti-SC-Bold），全幅无圆角。由 `/tmp/makeicon.swift`（AppKit 渲染脚本）生成，输出到 `sanxing/Assets.xcassets/AppIcon.appiconset/icon.png`，light/dark/tinted 三外观共用。

## 工作约定

- **git push 仅在用户明确指示时执行**，不自动推送。本地 commit 可按需。

## 后续可能方向（未做）

- 时间块比例可视化（按时长拉高）/ 周视图；时间块计划态与打卡；统计周/月汇总与趋势；数据导入导出（可参考逍遥居的 JSON + 剪贴板 + 覆盖/跳过）。
