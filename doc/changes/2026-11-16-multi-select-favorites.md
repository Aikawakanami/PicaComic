# 通用浏览列表多选本地收藏

- 级别：Level 1
- 状态：已实现并完成本轮验证
- 确认依据：2026-11-16，用户确认页面范围、目标为本地收藏夹、分页切页清空选择，并明确授权按讨论方案实现及当前真机验证。

## 1. 背景与目标

通用漫画列表当前只有单项长按操作。新增“多选”，一次将所选漫画加入同一本地收藏夹。

## 2. 需求与验收

- AC-01：五源（JM、EH/EX、哔咔、HT、NHentai）的通用搜索、现有分类/排行，以及 JM 最新、EH 主页/热门可从长按菜单进入多选，自动选中当前项。
- AC-02：点击卡片切换选择，不打开详情；已选数准确；连续模式全选已加载，分页模式全选当前页；清空后仍可继续选择。
- AC-03（首版，翻页清空已被后续跨页需求替代）：连续加载保留选择，新项不自动选中；上一页、下一页、跳页、刷新、关键词/排序/源改变时清空选择。退出多选保留滚动位置；返回键优先退出多选。
- AC-04：一次选择目标本地收藏夹，取消不写入且保留选择；没有收藏夹时给出提示；未选项目不可提交。
- AC-05：按来源类型和漫画身份去重；已存在的条目跳过，展示新增/已存在/失败数。执行中不可重复提交，部分失败保留失败项，全部处理成功后退出。
- 范围外：Hitomi、分区/混合主页、额外专题页、网络收藏列表及其他批量操作；不迁移现有数据库。

## 3. 现有实现分析

实施前，`lib/components/comics_list.dart → ComicsPage / ComicsPageLogic` 共用连续和分页布局；`comic_tile.dart → ComicTile` 提供源专用卡片及 `favoriteItem`；`LocalFavoritesManager.addComic` 为 async void，无法可靠等待写入结果，且封面下载与写库耦合。现有收藏表以 `(target, type)` 为主键。

## 4. 技术方案

只在确认的浏览入口启用多选区域，提供列表级选择上下文；卡片复用已有 FavoriteItem 转换，进入选择后拦截卡片内的详情/阅读操作。收藏批量写入与封面缓存分开，报告数据库写入结果，后台顺序缓存封面；沿用原收藏排序及同步行为。新增 Flutter SDK 的 integration_test 开发依赖及其 5 项传递依赖，原有依赖版本未升级。使用独立真机测试包和临时条目/收藏夹验证。

## 5. 实施计划

- [x] 实现选择状态、工具栏、卡片入口和页面边界。
- [x] 实现可报告结果的批量本地收藏。
- [x] 回归测试、静态检查、构建及当前 Android 真机验证。
- [x] 同步覆盖索引、存储/业务文档与实际验收证据。

## 6. 验证结果

| 验收项／检查 | 实际命令或操作、环境 | 结果与证据／限制 |
| --- | --- | --- |
| 选择状态、异常处理、布局与滚动 | `flutter test --no-pub test/comic_selection_test.dart` | 8 项通过：复合身份去重、空选择、禁止重复提交、失败重试、异常恢复、常量列表连续追加及刷新竞态、模式切换、小屏 2 倍字号与滚动位置保持 |
| AC-01、02、03（分页）、04、05 | 当前 PHZ110 / Android 14；`flutter test integration_test/multi_select_favorites_test.dart -d` 指定当前设备，`--no-pub --reporter expanded` | 5 组通过；生产 SearchResultPage 分别以五个源标识和中性临时数据运行，另检查生产分类/排行/探索页面及网络收藏/Hitomi 不显示入口；验证连续追加、取消收藏、重复跳过、实际 SQLite 的复合身份及部分失败重试。无收藏夹提示分支已静态核对，未单独真机触发 |
| 静态检查 | 针对实现及测试文件执行 `flutter analyze --no-pub --no-fatal-infos` | 无 error/warning；保留 8 条原有 info（弃用 API、tmp_db 命名）。新增集成测试文件的单独检查为 No issues found |
| AC-03（关键词/排序/源切换） | 在同一真机单独运行 `--plain-name "query, sorting and source changes reset the selection"` | 1 组通过；改变搜索词、确认新排序、切换漫画源均退出并清空选择，切换后能重新选择。测试兼容宽屏图标和窄屏“更多”菜单；此前对菜单布局的错误假设已修正 |
| 正常应用入口构建和启动 | `flutter build apk --debug --target lib/main.dart --target-platform android-arm64 --no-pub`；随后 ADB 安装更新并启动 | 构建退出码 0，安装 Success，启动 Status: ok，冷启动约 1.8 秒；进程及前台 Activity 正常，启动日志无初始化失败/Flutter 错误/崩溃标记，截图确认进入首次设置界面 |

本机日志在 `E:\Program Files\AndroidDev\logs\multi-select-device-test.log`、`multi-select-query-reset-test.log`；实际多选画面截图为 `multi-select-device.png`。正常入口验证记录为 `multi-select-normal-device.json`、`multi-select-normal-launch.log` 和 `multi-select-normal-launch.png`。测试使用新独立包及临时漫画/收藏夹，关闭远程同步；测试结束删除临时收藏夹及故障注入触发器，没有读取或修改个人账户、原应用数据。真实网站的加载、登录、阅读/下载不属于这些夹具测试的执行证据。

首次真机运行发现连续追加直接修改只读 List 的问题，已改为 `List<T>.of(res.data)`；刷新时用请求代次丢弃过期结果，避免旧分页数据追加到新列表。对应回归已通过。构建输出包含 NDK 版本建议及 SDK XML 版本警告，但成功构建并执行测试；未新增安装 NDK 或修改仓库 Android 版本配置。

## 7. 最终变更摘要

已实现列表级选择、长按入口、勾选和工具栏、批量本地收藏及结果反馈，新增简繁/英文文案和回归测试。8 项本地回归、5 组完整真机集成及 1 组补充真机场景通过；正常入口也已构建、安装和启动。APK 位于 `build/app/outputs/multiselect/PicaComic-multiselect-debug.apk`，名称“Pica 多选测试”，包名 `com.github.pacalini.pica_comic.devtest.multiselect`；名称及后缀仅由本机 E 盘 Debug 配置设置，不影响仓库的 Release 包名/名称。此前 JM limit 实测文档的未提交改动保留，不混为本功能验证结果；本次没有提交、推送或创建 PR。

后续用户反馈的数据包导入卡顿与测试版恢复已另行处理，当前正常 APK 路径已更新为修复版；对应修改、个人数据保护及执行证据见[导入恢复变更](2026-11-16-data-import-recovery.md)，不混为上述最初多选验收记录。

## 相邻选中边框修正（2026-11-16）

【已实现：静态依据】`lib/components/comic_tile.dart → ComicTile.build` 原来让选中遮罩铺满网格单元，列表没有额外单元间距时，相邻选中边框会贴在一起。现将选中遮罩四边各内缩 4 个逻辑像素，相邻单元之间保留 8 个逻辑像素的边框间隔；卡片布局、点击区域和选择状态不变，连续与分页共用此修正。

用户指定更新应用后自行验收，本轮只进行静态检查、正常入口构建与保留数据的安装更新；边框实际显示效果已由用户随后确认通过（相邻选中边框不再重叠）。不运行真机集成测试，不自动提交、推送或创建 PR。

【已验证：执行证据】本轮 `flutter analyze --no-pub --no-fatal-infos lib/components/comic_tile.dart` 无 error/warning，保留 4 条既有弃用 API info；正常入口 APK 构建成功，校验 `.devtest.multiselect` 包名后通过 ADB `install -r` 更新成功，启动请求返回 `Status: ok`。更新前另存完整数据快照；未执行显示效果验收。安装记录为本机 `logs/selection-border-install.json`，APK 为 `build/app/outputs/multiselect/PicaComic-multiselect-border-fix-debug.apk`。

## 多选长按快速收藏（2026-11-16）

用户确认边框修正通过，并要求多选模式长按收藏按钮时，将选中项直接加入既有“快速收藏”目标，更新后仍由用户验收。

【已实现：静态依据】`lib/components/comic_selection.dart → ComicSelectionRegion._quickSave` 读取 `settings[51]`，与 `lib/pages/settings/local_favorite_settings.dart → LocalFavoritesSettings` 及详情页快速收藏使用同一配置。工具栏“本地收藏”按钮短按保留选择收藏夹，长按直接提交；目标未配置或已删除时提示前往设置，保留当前选择且不写入其他收藏夹。

两种入口共用 `_saveToFolder → ComicSelectionController.save → LocalFavoritesManager.addComicsToFolder`，沿用复合身份去重、忙碌时禁止提交、结果计数、成功后退出和部分失败保留重试的行为。无选中项时短按/长按均禁用，连续与分页共用此功能；补充简繁/英文提示。静态检查、正常入口构建和保留数据更新后交给用户测试，不运行真机自动验收，不提交、推送或创建 PR。

【已验证：执行证据】`flutter analyze --no-pub --no-fatal-infos lib/components/comic_selection.dart` 为 No issues found；正常入口 APK 构建成功，校验现用包名后 ADB `install -r` 返回 Success，启动请求返回 Status: ok。更新前完整数据快照保存在本机 E 盘；新增长按功能尚未运行验收，待用户测试。安装记录为 `logs/selection-quick-favorite-install.json`，APK 为 `build/app/outputs/multiselect/PicaComic-multiselect-quick-favorite-debug.apk`。

## 收藏结果提示位置与开关（2026-11-16）

用户反馈多选收藏的数量提示靠近屏幕底部，要求上移，并在“设置 → 本地收藏”增加开关，更新后自行测试。

【已实现：静态依据】`lib/components/message.dart → showToast(atTop: true)` 支持在顶部安全区域下方显示，现由 `ComicSelectionRegion._saveToFolder` 的收藏结果提示使用，短按选择收藏夹与长按快速收藏共用。`lib/base.dart → Appdata.settings[90]` 新增“显示多选收藏结果提示”，默认 `1`，`LocalFavoritesSettings` 使用现有 SwitchSetting 控件保存；旧设置缺少末尾字段时沿用默认值。

关闭开关后不展示“新增/已存在/失败”数量，不改变写入、去重、退出多选和失败项保留逻辑；异常中断时的“收藏失败，请重试”仍在上方提示。新开关和说明已补简繁/英文。功能验收由用户执行，本轮只做静态检查、正常入口构建和保留数据安装更新。

【已验证：执行证据】针对 `base.dart`、`message.dart`、`comic_selection.dart` 和 `local_favorite_settings.dart` 的静态检查为 No issues found；正常入口构建成功，校验现用包名后 `install -r` 返回 Success，启动请求为 Status: ok。更新前已保留完整数据快照，未执行用户验收场景。安装记录为本机 `logs/selection-result-toast-install.json`，APK 为 `build/app/outputs/multiselect/PicaComic-multiselect-result-toast-debug.apk`；未提交、推送或创建 PR。

## 提示再次下移与远端列表变化分析（2026-11-16）

用户反馈上方提示与上一页/下一页工具栏重合，要求再下移并分析远程列表增删后的加载行为。`lib/components/message.dart → _ToastOverlay.build` 将顶部安全区域下的偏移从 64 改为 128 个逻辑像素（下移 64），沿用数量提示开关。显示效果仍待用户验收。

已核对通用列表、五源搜索适配器及 EH 下一页链接缓存，分析与条件性示例见[远程列表变化与分页一致性](../business-flows.md#远程列表变化与分页一致性)。本轮未修改加载、列表去重、分页缓存或失败重试逻辑，未操作远程源增删。

【已验证：执行证据】本轮 `message.dart` 静态检查为 No issues found；正常入口构建成功，校验包名后保留数据安装返回 Success、启动请求返回 Status: ok。更新前完整快照保留于本机 E 盘，提示显示效果待用户测试；安装记录为 `logs/selection-toast-offset-install.json`，APK 为 `build/app/outputs/multiselect/PicaComic-multiselect-toast-offset-debug.apk`。未提交、推送或创建 PR。

## 提示再下移 150 与跨页选择讨论（2026-11-16）

按用户明确要求，`_ToastOverlay.build` 顶部安全区域下的偏移由 128 调整为 278 个逻辑像素，即再下移 150；沿用原数量提示开关并准备保留数据更新。

用户同时询问分页多选与已选项能否跨页继承。已核对当前 `nextPage / prevPage / selectPage` 清空选择及按来源+ID保存选择的实现。当前版本仍翻页清空；跨页继承的可行性和应对远端增删/重排的建议已记入[业务流程](../business-flows.md#分页跨页多选的可行性待确认方案)，本轮未更改该需求边界或实现跨页选择。

【已验证：执行证据】本次为单个位置数值调整，正常入口 APK 构建成功、包名核对通过；保留数据安装返回 Success，冷启动返回 Status: ok（约 2.1 秒）。更新前保留完整快照，未代替用户验收提示效果。记录为本机 `logs/selection-toast-offset150-install.json`，APK 为 `build/app/outputs/multiselect/PicaComic-multiselect-toast-offset150-debug.apk`。跨页选择仍未实现，未提交、推送或创建 PR。

## 跨页规则替代记录（2026-11-16）

用户随后明确要求实施跨页选择，替代首版翻页清空及上述讨论时的“尚未实施”状态。当前实现、14 项本地回归及保留数据交付记录统一见[跨页选择变更](2026-11-16-cross-page-selection.md)；此前执行结果保留其历史时点含义。提示偏移本轮上移 50，现为顶部安全区域下 228 个逻辑像素。
