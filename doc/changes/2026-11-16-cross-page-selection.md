# 分页多选跨页继承

- 级别：Level 1
- 状态：实现、验证及安装交付完成；用户已确认当前测试版测试通过
- 确认依据：用户在已讨论的来源+ID集合方案后明确要求“往上移50个逻辑像素，然后实施跨页选择”。该要求替代首版“翻页清空”的验收条件。

## 1. 背景与目标

分页选择跨上一页、下一页和跳页保留，累计收藏所有已选漫画。远端增删/重排不应让选择按位置错套到其他漫画。收藏结果提示同时上移 50 个逻辑像素。

## 2. 需求与验收

- AC-01：上一页、下一页、跳页保留多选状态及已选集合；返回缓存页恢复对应勾选。
- AC-02：按来源+ID去重，保留选中时的元数据副本；同一条跨页重复只计一次，远端新增项不自动选中，未再出现的已选项不自动取消。
- AC-03：分页显示总已选和本页已选；全选只加入当前页；“查看已选”可查看/移除所有页面累计的项目。
- AC-04：普通收藏及长按快速收藏提交整个集合；沿用去重、忙碌保护及部分失败保留重试。
- AC-05：刷新、换源、改搜索/筛选/排序、切换列表显示模式、退出多选/离开列表清空会话选择；页面加载失败保留已选，重试当前页。
- AC-06：提示偏移由顶部安全区域下 278 改为 228 个逻辑像素；保留已有提示开关和用户数据。

## 3. 现有实现分析

`lib/components/comics_list.dart → nextPage / prevPage / selectPage` 当前调用 `selection.exit()`；`ComicSelectionController` 已按 `(FavoriteType.key,target)` 保存选择。分页数据保存在 `dividedComics`。现有错误页重试调用全量 refresh，会清空选择并回到第一页；分页异步请求应使用请求时的页号缓存，避免翻页期间响应写入其他页。

## 4. 技术方案

复用当前列表级选择控制器，导航时保留集合。选中时复制 FavoriteItem，重复条目不覆盖已选元数据；全选和本页计数按身份去重。增加查看已选对话框及移除入口。页面切换与同页重试由逻辑控制器处理，保存请求页号并按该页缓存响应；后续响应可更新总页数。范围切换沿用刷新/组件重建边界。

不逐条在线验证已选项目，不自动补抓远端所有页，不迁移数据库或跨重启保存选择。远端删除后仍可按已有信息保存本地收藏，详情/阅读可能失效；跨页选择不能解决页码源固有的漏项风险。

## 5. 实施计划

- [x] 修改选择快照、分页导航/重试和已选查看/移除。
- [x] 本地中性夹具回归、静态检查、更新已有集成测试期望。
- [x] 同步知识库、构建正常入口、备份并保留数据更新真机。

## 6. 验证结果

【已验证：执行证据】`flutter test --no-pub test/comic_selection_test.dart test/cross_page_selection_test.dart --reporter expanded` 共 14 项通过（原有 8 项、新增 6 项）。中性夹具验证跨页身份/资料副本、重复/新增/已选项缺席的模拟、跳页/缓存回访、错误重试、总页数缩小后的空页返回、异步响应页号归属、全部选择提交及已选列表移除，以及 320×640 小屏 2 倍字号布局。首轮发现错误页分页栏宽度溢出，修正为撑满宽度后回归通过。

定向静态检查 `comic_selection.dart / comics_list.dart / message.dart / cross_page_selection_test.dart / multi_select_favorites_test.dart` 为 No issues found。已有集成测试期望已更新为翻页保留，但本轮未运行真机集成目标。本机证据为 `logs/cross-page-selection-test.log`、`cross-page-selection-analyze.log`。真机保留用户自行验收的方式，不向含个人数据的应用运行集成测试。

【已验证：执行证据】正常入口 `flutter build apk --debug --target lib/main.dart --target-platform android-arm64 --no-pub` 成功；核对 `.devtest.multiselect` 包名后 ADB `install -r` 返回 Success，启动请求返回 Status: ok。更新前完整数据快照保存在本机 E 盘，未运行真机自动功能测试。安装证据为 `logs/cross-page-selection-install.json`；构建仍有既有 NDK 建议和 SDK XML 警告，不影响本轮构建成功。

## 7. 最终变更摘要

分页多选现支持前后翻页/跳页保留、来源+ID去重并保存资料副本、总数和本页计数、查看及移除全部已选、当前页失败重试，以及空页/错误页返回。普通和快速收藏复用整个集合提交，范围变更/刷新仍清空；提示上移 50，当前偏移 228。14 项本地回归和定向分析通过，保留数据更新真机完成，显示及实际网站使用效果交由用户验收。APK 为 `build/app/outputs/multiselect/PicaComic-cross-page-selection-debug.apk`，常用多选 APK 路径也同步更新。未提交、推送或创建 PR。

## 工具栏图标与全不选（2026-11-16）

按用户要求，`ComicSelectionRegion.build` 的“全选当前页/全选已加载”与“查看已选”改为纯 IconButton，使用 32 个逻辑像素图标、至少 48×48 点击范围并保留 tooltip/无障碍名称，参考收藏页的 `Icons.select_all` 样式；新“全不选”使用收藏页相同的 `Icons.deselect`，替代原“清空已选”文字按钮。

全不选调用 `ComicSelectionController.clear`，清空当前列表会话内跨页累计的全部选择，保留多选状态；没有已选项或正在收藏时禁用。全选范围及查看/移除已选的行为不变，收藏按钮保留文字。新增简繁/英文全不选提示。

本地 14 项回归已通过，补充断言按钮不显示文字、三枚图标尺寸、全不选清除页外项目且仍处于多选，以及清空后按钮禁用；已有测试改为按 tooltip 查找图标。真机集成脚本同步更新但未运行；定向静态检查为 No issues found；正常入口构建成功，完整备份后通过 ADB `install -r` 保留数据更新，返回 Success，启动请求返回 Status: ok。用户随后明确回复“测试通过了”，确认当前测试版通过验收。

本轮图标调整的本机证据为 `logs/selection-icons-test.log`、`selection-icons-analyze.log`、`selection-icons-build.log`、`selection-icons-install.json`，APK 为 `build/app/outputs/multiselect/PicaComic-selection-icons-debug.apk`；常用多选 APK 路径已同步更新，未提交、推送或创建 PR。

## 用户验收与仓库交付（2026-11-16）

【已验证：用户反馈】用户确认最新图标/全不选版本测试通过，并明确要求将本次全部功能修改和更新知识库提交到本人仓库 `dev` 分支。该反馈作为当前测试版的用户验收记录，不扩大为所有漫画源协议、所有历史数据格式或其他平台均验证通过。

交付包括多选及跨页继承、快速收藏、提示位置/设置开关、边框/图标/全不选、导入恢复、测试与知识库；汇总提交目标 `Aikawakanami/PicaComic → dev`，不创建 PR。个人备份、日志、APK、本机配置和签名密钥保留于本机，不纳入提交。
