# 阅读统计与本地收藏分页、排序

- 状态：已实施；2026-11-18 按用户新要求调整页大小，并覆盖更新当前真机、确认启动。具体新功能交互仍待用户验收。
- 实施日期：2026-11-17。开发分支为 `codex/reading-stats-local-favorites`，按用户授权在个人仓库的 `dev` 分支交付。
- [已确认需求](../requirements/reading-statistics-favorites.md)、[实施计划](../plans/reading-statistics-favorites.md)、[授权前讨论](2026-11-17-reading-statistics-favorites-proposal.md)。连续加载重试/去重仍按[另一个方案](2026-11-17-continuous-loading-plan.md)暂缓。

## 使用与口径

【已实现：静态依据】阅读器前台显示正文后累计有效时长，累计满 10 秒计一次阅读。换章延续同一次会话，所有章节时长相加；退出后再次进入为新会话。加载/失败、后台、失焦、覆盖路由暂停；静止看同一页仍计时。用单调时钟计算时长，每 10 秒及暂停/退出保存，强杀可能丢失末次未保存的不足 10 秒。

本地收藏夹顶部有排序、升/降序、连续/分页切换、每页数量和刷新控件；分页可选 20/40/60/80/100，默认 60，底部支持上一页/下一页/点击页码跳页。默认沿用连续模式，在设置的本地收藏中可调整新夹的默认方式/页大小，各夹单独记住选择。

排序支持原手动顺序、最后阅读时间、阅读次数、累计阅读时长、图片数量。指标排序不改手动位置；先全夹排序再分页。浏览期间固定有序身份快照，统计更新只刷新数值，主动刷新/改排序后重排；新增/删除、显式拖动排序后重建快照并校正页号。

收藏详细卡片显示次数、累计时长和图片数，单项操作菜单也显示完整统计，可用于封面模式。图片数量显示完整 `90`、下限 `30+`、未获取；`30+` 按 30 排，完全未获取在两个方向都排末。直接阅读、离线阅读统一采集已取得的当前章节数，不必先打开详情；加入收藏或查看/更新详情时复用已有可信整本总数。不主动联网扫描全部收藏。

分页多选跨页保留，工具栏全选仅作用当前页，可查看/移除页外已选；取消选择清空全会话。原复制、删除、下载等操作仍使用全部已选项。文件夹变化按当前身份清理已不存在的选择。

最后阅读排序按用户要求继续使用收藏行 time，不新增原始加入时间。旧 time 可能来自加入收藏时初始化，不能据此推断旧阅读次数；新次数和时长从 0 开始。阅读未成功显示正文不更新时间；成功后按最后实际活动时间更新，WHERE 同时限制 target 和 type。

## 实现与存储

| 范围 | 源码与职责 |
| --- | --- |
| 计次、时长、幂等合并 | `lib/foundation/reading_stats.dart → ReadingStatistics / ReadingSessionTracker`；独立 reading_stats.db，session_id 检查点取 max、不同会话汇总 |
| 当前正文与生命周期 | `lib/pages/reader/reading_statistics.dart → ReadingStatisticsBoundary`；`reading_logic.dart → observeImage / _updateReadingActivity`；`image_view.dart` 只观察显示 provider |
| 章节与元数据 | `reading_data.dart → statisticsIdentity / statisticsChapter / statisticsCatalog`；`comic_reading_page.dart → loadInfo`；`foundation/reading_metadata.dart → recordReadingMetadata`；`ComicPageLogic.get / LocalFavoriteTile.readComic / FavoriteItem` 复用已有响应 |
| 查询和视图 | `foundation/favorite_query.dart → FavoriteQuery / FavoriteSnapshot / FavoriteViewOptions`；`pages/favorites/main_favorites_page.dart → ComicsPageView`；`favorite_view_controls.dart` |
| 备份与恢复 | `tools/io_tools.dart → _exportData / _extractImport / _installImportFiles`；`ReadingStatistics.snapshotTo / mergePending / mergeData`；`LocalFavoritesManager.folderToJsonString / loadFolderData` |
| 设置与清理 | `base.dart → settings[11/91/92] / clearAppdata`；`pages/settings/local_favorite_settings.dart`；`init.dart → init` 恢复暂存统计库 |

统计按来源+收藏 ID 共享，不按所在夹重复计数，NH 类型和 Hitomi 链接使用收藏身份；HT 统一为 htmanga。普通清空历史保留统计，清空应用数据才清除。旧包缺少统计库正常兼容；整包导出包含一致性数据库快照，文件夹 JSON 只含相关身份的统计。重复导入不会把同一会话再次相加；失败的统计暂存库保留供重试。没有清除墓碑，旧备份可以恢复旧统计。详情见[数据模型](../data-model.md#阅读统计与收藏分页排序2026-11-17)。

## 执行证据与待验收

【已验证：执行证据】使用临时中性数据库、模拟时钟/图像和 Flutter 控件，未读取个人备份、使用真实账户或请求漫画源：

- 全部主机测试 34 项通过，其中新增 20 项，覆盖会话跨章累加/门槛、加载和后台排除、当前页解码/相邻页不误计、Flutter 生命周期及覆盖路由、来源隔离、Hitomi 详情采用收藏链接身份、完整/部分图片数和重复章节。
- 覆盖同会话较新检查点保留、重复导入、多会话汇总、冲突回滚、数据库快照恢复、未来 Schema 拒绝及清空后重建。
- 覆盖全夹排序、稳定并列、未知排末、统计变化不挪页、10000 条旧收藏身份+50 条元数据分页（一次完整回归测得约 44 ms；不作为设备性能承诺）。
- 实际收藏页面在 320 逻辑像素下验证跨页保留、当前页全选、查看/移除页外选择、末页删除校正、单项菜单统计和显式重排。窄屏控件模式/排序/页大小与边界按钮通过。
- `flutter analyze --no-pub` 无 error；现有未改文件的 22 条 warning 保留，主要为未用 import 和下载类 must_call_super。全库仍有既有 info，不宣称分析器零问题。
- Android arm64 Debug APK 构建通过。构建保留已有 NDK 版本建议和 SDK XML 警告，本轮未改工具链或 Gradle 配置；本机隔离配置仍为多选测试包身份。

主要测试文件：`test/reading_statistics_test.dart`、`favorite_query_test.dart`、`reader_statistics_gate_test.dart`、`local_favorites_paging_test.dart`、`favorite_controls_test.dart`、`reading_metadata_test.dart`。Windows 测试通过 PICA_TEST_SQLITE3 注入本机已有 SQLite DLL，应用无新增依赖。

【待真机功能验收】2026-11-18 已授权安装并完成启动检查；真实源在线/离线、多入口、锁屏、双页、缺图、强杀检查点，以及完整压缩包/WebDAV/文件夹导入导出全通道仍需真机验收。上述统计行为执行证据来自主机，不代表各源真机交互已验证；存储核心快照/合并已测，不代表压缩包全通道已测。

【已知边界】远端图片数/目录可能改变，保存的是上次已知值；Pc 接口以章序定位，中间插章/重排仍有对应风险。不会修复既有历史 target 主键或自定义源 hashCode 身份问题；整包跨数据库/文件不具备统一事务。收藏排序快照仍保留全夹身份，分页只限制元数据读取。

## 2026-11-18 页大小调整与真机交付

【已实现：静态依据】用户将选项调整为 20/40/60/80/100，默认改为 60。`FavoriteQuery` 所在模块集中维护 favoritePageSizes、defaultFavoritePageSize、normalizeFavoritePageSize；收藏页和设置入口复用同一组选项。旧 50 项及非法配置回退 60，Appdata 读取/导入默认值与每夹配置解析均兼容，不改收藏成员和手动顺序。

【已验证：执行证据】34 项主机测试通过，补充五组选项、选择 80、旧 50 回退 60 的断言；定向静态分析无 error/warning，保留既有 info。Android arm64 正常入口构建成功，检查隔离包名后 ADB install -r 覆盖当前“Pica 多选测试”，返回 Success。启动返回 Status: ok，进程存活，系统在启动后 1 秒和 4 秒均确认 MainActivity 位于前台；采集日志未见原生致命异常、未处理 Dart 异常或初始化失败。此处不宣称各源实际阅读/分页已完成真机验收。

更新前已备份实际已安装 APK 和完整私有数据至本机被忽略的 `build/codex-reading-stats/device-backup-2026-11-18/`；覆盖后收藏库和历史库 SHA-256 与备份一致。正常入口 APK 保留于 `build/app/outputs/multiselect/PicaComic-reading-stats-pages-debug.apk`。这次交付验证覆盖安装和启动，其他功能验收范围见上节。
