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
    DataTransfer.swift     导入导出：DTO + BackupData(version) + ISO8601 JSON + 覆盖/跳过分流 + JSONDocument
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

- 容器 ID：`iCloud.com.xhy.sanxing`（**仓库根** `sanxing.entitlements` 的 `icloud-container-identifiers`，`CODE_SIGN_ENTITLEMENTS = sanxing.entitlements`）。**不能放进 `sanxing/` 同步组**——文件系统同步组会把它当 target 成员加进 Copy Bundle Resources，真机签名时改写它 → 报「Entitlements file was modified during the build」。和 `Info.plist` 一样要放在仓库根。
- 后台同步推送：`UIBackgroundModes = [remote-notification]`，放在**仓库根** `Info.plist`（`INFOPLIST_FILE = Info.plist`）。**不能放进 `sanxing/` 同步组**——文件系统同步组会把它自动加进 Copy Bundle Resources，与生成的 Info.plist 冲突（"Multiple commands produce Info.plist"）。其余 plist 键仍由 `GENERATE_INFOPLIST_FILE` 合并注入。
- **首次真机联调**：CloudKit 开发环境会按 schema 自动建记录类型（含新增的 `CustomCategory`）；**上架前**须在 CloudKit Dashboard 把 schema 部署到 Production。命令行只能 `xcodebuild` 验证编译，实际同步/双账号需真机手测。

## 关键约定与范式

- **TabView + 每 Tab 各自 NavigationStack**（同逍遥居）。
- 编辑器统一用 `.sheet(item:)`（编辑已有）+ `.sheet(isPresented:)`/`.sheet(item:)`（新建），编辑器内含 `init` 区分新建/编辑。日记编辑器仍用底部「删除」段；**时间块编辑器**已把删除挪到右上角「保存」**左侧**的「删除」文字按钮（红色，仅编辑态）。
- **时间块编辑器**（`TimeBlockEditorView`）表单顺序：标题 → 备注 → 分类 → 时间。时间区含 时长预设 + 开始/结束 DatePicker + **24 小时表盘** `ClockDialPicker`（拖把手改起止，仿健康 App）。三者互不牵连：改开始不再平移整段（去掉了 `onChange(of:start)`），只有时长预设会 `end = start + 时长`。表盘逻辑见下。
- 主题：`@AppStorage("appColorScheme")`（0 跟随系统 / 1 浅 / 2 深），在 `sanxingApp` 用 `preferredColorScheme` 应用。
- 列表查询用 `@Query`，**按天过滤在内存里做**（`allBlocks.filter { $0.start.isSameDay(as: day) }`），数据量小不建动态谓词。

## 今日时间轴（TimelineView）— 交互重点

把每天切成 **24 个整点 1 小时槽**（0:00–23:00），**多天纵向无缝滚动**连续浏览，是产品核心形态。

- **行的 key 是 hour-start `Date`**（某天某整点 = `day.startOfDay + h 小时`），不再是单纯 `Int` 小时。渲染一个**天的窗口** `days: [Date]`（初始 today±14）；首/末天 `onAppear` 往前/后各拼 7 天，前插后用 `ScrollViewReader.scrollTo(旧首天 header, .top)` **重锚避免跳动**。
- 用 `ScrollView + LazyVStack`（**不是 List**）——List 内拖拽选择会与滚动冲突。
- 结构：`ForEach(days){ dayHeader(day); ForEach(visibleHourStarts(of:day)){ hourRow(hs).id(hs) } }`。`dayHeader` = **分割线**（`Rectangle().fill(Color(.separator))`，自适应深浅色）+ 日期（今天高亮）+ 当天小结。
- **整点内按条目渲染**（`hourItems(hs)` → `[HourItem]`）：保留整点网格的同时，把整点里「块 / 块之间任意长度的空闲段」按时间排开。空整点 → `.empty`（可多选/填充的「空闲 ＋」）；有块的整点 → 块 + 块前/块后到整点末的 `.idle` 段（如块 3:00–3:50、下个块 4:00 → 渲染 3:50 的空闲段）。每行左侧标**该条目的真实起始时间**（`clock` = HH:mm，块用 `b.start`、空闲段用段起点），不再统一用整点。空闲段点按按其精确起止建块（`TimeBlockEditorView(start:end:)`）。当前行高亮用 `isNowIn(s,e)`。
- **覆盖/重叠处理**：`visibleHourStarts` —— 有块**起始**于该整点就显示（即使被前一个多小时块覆盖，否则那个块会消失）；覆盖块在整点内结束、留有空闲也显示（渲染剩余空闲段）；只有「整段被覆盖且无块」才隐藏。`hourItems` 的游标会跳过被前块占用的开头。
- **单块操作走底部「操作」菜单**（多选态、恰好选中 1 个块 `singleBlock` 时出现的 `Menu`，不是每块的 contextMenu——之前误做成 contextMenu 已撤回）：`开始改为现在`（`now<end`）/ `结束改为现在`（`now>start`）/ `并入选中空闲`（同时选了空闲整点 → `mergeSelected`）/ `合并前面空闲`（`hasGapBefore`→`mergeGapBefore` 提前 start）/ `合并后面空闲`（`hasGapAfter`→`mergeGapAfter` 延后 end）。长按进多选仍是 `selectDragGesture`（未改）。
- **编辑后重叠弹窗**：`afterEdit` = `normalize()` + `checkOverlap()`。若不同分类的相邻块时间重叠（同类已被 coalesce 合并），弹 `confirmationDialog` 让用户选：把后块开始改到前块结束 / 把前块结束改到后块开始 / 保持重叠。解决后再 `afterEdit` 递归检测下一处。
- **按天独立**：`coveringBlock`/`visibleHourStarts` 都加同天守卫，跨午夜的块不会覆盖到下一天；`coalesceAdjacent` 只合并**同一自然日内**相邻同类块（`isSameDay` 守卫），跨天不并。
- `focusedDay` 由滚动推导（`updateFocusedDay`：取贴近视口顶部那行的天），驱动顶部标题、全选范围、新建默认天。
- 看「今天」时 `ScrollViewReader` 自动滚到当前钟点并高亮；当前时刻所在行左侧钟点加粗+下划线（`rowContainsNow`，含被多小时块覆盖的情形）。
- 左侧整点时间务必单行：`Text(...).lineLimit(1).fixedSize(...)`，列宽用 `minWidth`。
- 顶栏（非多选态）：左上**日历按钮** → graphical `DatePicker`（zh_CN）→「完成」`goToDay`；中间 `dayNav` ‹ 焦点天 ›；点击都走 `goToDay`（目标在窗口外则以它为中心重建窗口）→ `scrollTarget` → `proxy.scrollTo(dayHeaderID, .top)`。右上「选择」进多选。

### 分类选择（编辑器 & 填充 共用 CategoryGrid）

- `CategoryGrid`（`Views/CategoryPicker.swift`）渲染 `allCatStyles`：内置 + 自定义 + 末尾「＋ 自定义」格。自定义格**长按**出 contextMenu 可编辑/删除。编辑器传 `selectedKey` 做高亮、填充菜单传 `nil`。
- 「＋ 自定义」开 `CustomCategoryEditor`（名称 + 色板/`ColorPicker` + 图标网格），保存即 insert `CustomCategory` 并通过 `onSave` 回调让调用方直接选中/使用。
- 填充菜单从旧的 `confirmationDialog`（纯文字）改成 `.sheet` 内嵌 `CategoryGrid`，与编辑器视觉一致。

### 时间块编辑器表盘（ClockDialPicker）

- 24 小时环：**0 在正上方、顺时针**（6 右 / 12 下 / 18 左，同健康 App）。坐标 `point(t)`：`x=c.x+r·sin(t/24·2π)`、`y=c.y−r·cos(t/24·2π)`；反向命中 `atan2(dx, −dy)`。
- 刻度 0/6/12/18 高亮（主色、字号略大，**不加粗**）、其余次要；午夜 `sparkles`(cyan)、正午 `sun.max.fill`(yellow) 两枚图标贴在刻度内侧。
- 选中弧用单段 `Circle().trim(from:0,to:时长/24)` + `.rotationEffect(开始/24·360−90°)` 旋到位——避免跨 0 点的圆弧接缝。
- 两把手按 category 色显示（start 用分类图标）。拖拽时按触点就近锁定把手；**拖 start 保持 end、拖 end 保持 start**，时长锁在 0…24h，end 可取 start 之后最近时刻 → 天然支持跨午夜。snap 到 5 分钟。
- **防误触**：`.contentShape(RingShape(radius:r,width:ringWidth+16))` 把命中区限定在「圆环带」——只有点在两圆之间的环带才触发拖拽；点中心/外侧不拦手势，落给外层 ScrollView 滚动。`RingShape` = 外圆 + 反向内圆，nonzero 填出环带。
- 与 `TimelineView.normalize`（splitCrossDay）配合：表盘把块拖成跨午夜后，回到今日 `afterEdit` 会按 0 点拆成按天独立的块。

### 跨天拆分（splitCrossDay，按 0 点）+ 统一收尾 normalize

- 所有改动后统一调 **`normalize()` = `splitCrossDay()` + `coalesceAdjacent()`**；填充 `fillSelectedHours`、长按合并 `mergeSelected`、编辑器关闭 `afterEdit` 都走它，保证跨天处理一致（之前 merge 会留一条跨天块、与填充不一致，已统一）。
- `splitCrossDay`：块跨午夜（`end > start 当天的次日 0 点`）→ **原块裁到当天 24:00**，其后每天的剩余段**另建块**（`insertIntoFreeSlots` 只填空闲、不覆盖已有块）。即跨天一律**按 0 点拆成按天独立的块**，不再保留一条跨天块。
- 幂等：拆出的段都不跨天，重跑不再拆；`coalesceAdjacent` 的同天守卫保证拆开的两段不会又被并回。

### 选择与批量操作

- **进入多选**：右上「选择」按钮，或**长按任意行**（`LongPressGesture(0.3).sequenced(before: DragGesture)`）。长按后不抬手**上下滑动**连续选中（以长按行为锚点，选锚点→当前行的范围）。快速点按（<0.3s）不触发选择，仍是编辑块/新建空闲。
- 拖拽命中靠每行上报 frame（`RowFrameKey: [Date:CGRect]` + `.coordinateSpace(name:"timeline")`），`hourStart(at:)` 按 y 命中；`selectRange` 在 `allVisibleHourStarts`（窗口内全部可见 hour-start，升序）里取子区间，**可跨天**。
- **滚动性能**：逐行 `RowFrameKey` **仅在多选态上报**（普通滚动不上报，避免「preference updated multiple times per frame」卡顿）；`focusedDay` 改由每天 1 个的 `DayFrameKey`（天 header frame）跟踪，比逐行便宜得多。
- 三套选中集：`selected`（真实块）、`selectedHourStarts: Set<Date>`（空闲整点，支持长按拖拽范围选）、`selectedIdle: Set<IdleRange>`（块之间的小空闲段，多选态点按勾选）。「填充」对两类空闲都建块（整点 1h、小空闲按精确起止）；`mergeSelected` 把选中的整点+小空闲并入唯一块；全选覆盖 `focusedDay` 的整点空闲 + 小空闲段。
- 底部工具栏（多选态，`.bottomBar`）按上下文出现：
  - **填充**：选中空闲整点 → 弹 `CategoryGrid` 选分类后各建 1 小时块（`fillSelectedHours(with: key)`）。
  - **合并**：仅当「恰好 1 个块 + 若干空闲」被选中（`canMerge`）→ 把该块拉长覆盖整段（`mergeSelected`，保留块原有更早起/更晚止）。
  - **删除**：删选中的真实块。
- 左上「全选/取消全选」**只覆盖空闲整点**（不动用户手动选中的块），`allSelected`/`toggleSelectAll` 都只看 `emptyHours`。

## 数据导入导出（参考 xiaoyaoju）

设置「数据」段：导出到文件 / 复制到剪贴板 / 从文件导入 / 从剪贴板导入。

- `DataTransfer.swift`：三类 `@Model` ↔ DTO（`TimeBlockDTO/DiaryEntryDTO/CustomCategoryDTO`），打包成 `BackupData{version, blocks, diaries, categories}`。JSON 用 **ISO8601** 日期、pretty-print。`@Model` 加了 `dto` 属性与 `convenience init(dto:)`（`CustomCategory(dto:)` 会**保留原 id**，否则时间块的 `category` 引用会断）。
- 导出：`DataTransfer.encode` → 剪贴板（`UIPasteboard`）或 `.fileExporter`（`JSONDocument: FileDocument`，默认名 `三省小记备份_yyyyMMdd_HHmm`）。
- 导入：剪贴板 / `.fileImporter`（安全作用域 `startAccessingSecurityScopedResource`）→ `decode` → `DataTransfer.plan` 按 key 判重（**时间块按 start、日记按 createdAt、分类按 id**）：不冲突的直接 insert，冲突的弹「覆盖/跳过」对话框统一处理。覆盖 = 删旧 insert 新。

## App 图标

文字图标「三省」（横排两字，App 名「三省小记」的缩写）：1024×1024，靛蓝竖向渐变 + 白色宋体（STSongti-SC-Bold），全幅无圆角。由 `/tmp/makeicon.swift`（AppKit 渲染脚本）生成，输出到 `sanxing/Assets.xcassets/AppIcon.appiconset/icon.png`，light/dark/tinted 三外观共用。

## 工作约定

- **git push 仅在用户明确指示时执行**，不自动推送。本地 commit 可按需。

## 后续可能方向（未做）

- 时间块比例可视化（按时长拉高）/ 周视图；时间块计划态与打卡；统计周/月汇总与趋势。
