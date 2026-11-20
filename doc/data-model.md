# 数据模型与持久化

[返回知识库](README.md)。以下结构以当前建表、序列化与调用代码的【已实现：静态依据】为主；后续中性夹具验证及按用户请求执行的本机数据恢复另有显式记录，不将单次恢复推广为全部历史格式迁移已验证。

## 领域对象与身份

| 对象／用途 | 结构及身份约束 | 源码锚点 |
| --- | --- | --- |
| 列表条目 | `BaseComic` 提供标题、封面、ID、标签；`CustomComic` 另携带 `sourceKey`，不是完整漫画或数据库行 | `lib/network/base_comic.dart → BaseComic / CustomComic.fromJson` |
| 通用详情 | `ComicInfoData` 含 `comicId`、`sourceKey`、标签及可空 `chapters`；章节 Map 是“源章节 ID → 显示名”，顺序被阅读／下载按位置使用 | `lib/comic_source/comic_source.dart → ComicInfoData`；`lib/pages/reader/reading_data.dart → CustomReadingData` |
| 历史 | `History` 含类型、时间、目标、章节、页码、已读章节集合和最大页数；`HistoryMixin.target` 对接各源模型 | `lib/foundation/history.dart → HistoryMixin / History / HistoryManager` |
| 本地收藏 | `FavoriteItem` 保存类型、target、标题、作者、封面、标签；同一项可属于多个收藏夹 | `lib/foundation/local_favorites.dart → FavoriteItem / LocalFavoritesManager.find` |
| 下载 | `DownloadedItem` 是已完成漫画，`DownloadingItem` 是可恢复任务；下载 ID 和原始漫画 ID 不总是相同 | `lib/network/download_model.dart → DownloadedItem / DownloadingItem` |
| 源状态 | `ComicSource.data` 是任意 JSON Map；`isLogin` 只检查 `data['account'] != null`，不是实时服务端会话校验 | `lib/comic_source/comic_source.dart → data / isLogin / saveData` |

内置源的类型编码并不统一，不能直接把某个 enum 的索引存入另一种模型：

| 源 | `HistoryType.value` | `FavoriteType.key` | `DownloadType.index` |
| --- | --- | --- | --- |
| picacg | 0 | 0 | 0 |
| ehentai | 1 | 1 | 1 |
| jm | 2 | 2 | 2 |
| hitomi | 3 | 3 | 3 |
| htmanga | 4 | 4 | 4 |
| nhentai | 5 | 6 | 5 |

依据：`lib/foundation/history.dart → HistoryType`、`lib/foundation/local_favorites.dart → FavoriteType`、`lib/network/download_model.dart → DownloadType`；`lib/foundation/def.dart → ComicType` 还保留 `htFavorite`。自定义源历史／收藏使用 `sourceKey.hashCode`（`ComicInfoData.historyType`、`FavoriteItem.custom`），跨进程和跨平台的持久稳定性尚未验证。

## 文件与数据库

路径基准来自 `lib/foundation/app.dart → App.init`：`App.dataPath` 为 application support directory，`App.cachePath` 为 application cache directory；本页不假设某台机器的绝对运行路径。

| 位置 | 内容及主要约束 | 当前源码锚点 |
| --- | --- | --- |
| dataPath 下 `settings` | JSON 字符串列表；读取优先于旧 SharedPreferences 的 `settings`，按现有列表长度拷贝，缺失尾项沿用默认值 | `lib/base.dart → Appdata.settings / readSettings / updateSettings` |
| SharedPreferences | `search`、`searchSources`、`favoriteTags`、`blockingKeyword`、`firstUse`、`implicitData` 等；搜索历史和 `implicitData` 为本机数据 | `lib/base.dart → readData / writeHistory / readImplicitData / toJson` |
| `comic_source/<key>.data`、`comic_source/*.js` | 源状态 JSON 与用户安装的脚本；状态可能包含账户信息 | `lib/comic_source/comic_source.dart → loadData / saveData / init`；`parser.dart → _loadAccountConfig` |
| `history.db → history` | `target TEXT PRIMARY KEY`；另含 title、subtitle、cover、time、type、ep、page、readEpisode、max_page。`readEpisode` 写成逗号分隔字符串 | `lib/foundation/history.dart → init / addHistory / saveReadHistory` |
| `history.db → image_favorites` | 主键 `(id, ep, page)`；title、cover、other 等，`other` 是 JSON；与历史共用数据库 | `lib/foundation/image_favorites.dart → ImageFavoriteManager.init / add` |
| `local_favorite.db` | 每个收藏夹直接作为一张表，主键 `(target, type)`；另有 `folder_order(folder_name PK, order_value)`、`folder_sync(folder_name PK, time, key, sync_data)` | `lib/foundation/local_favorites.dart → _checkAndCreate / createFolder` |
| `cookies.db → cookies` | 主键 `(name, domain, path)`；value、expires、secure、httpOnly 等字段；普通 Cookie 单例与 JM 的短期内存 CookieJar 不同 | `lib/network/cookie_jar.dart → CookieJarSql.init`；`lib/network/jm_network/jm_network.dart → cookieJar` |
| `cache.db → cache` | `key` 主键及 dir、name、expires、type，旧表缺 type 时补列，并建立 `cache_expires` 索引。内容位于 `App.cachePath/cache/` 下，容量按文件字节计量，设置键为 `settings[35]` | `lib/foundation/cache_manager.dart → CacheManager._ / _scanExistingFiles / _evictBatches` |
| 下载目录下 `download.db → download` | `id` 主键，title、subtitle、time、directory、size、json；json 保存各源特有已下载模型 | `lib/network/download.dart → _DownloadDb._createTable / _addToDb` |
| 下载目录下 `newDownload.json` | 队列与任务进度，包含 type、links、章节位置、图片位置、finishedTasks 等；每张图片完成可写入 | `lib/network/download.dart → _getInfo / _saveInfo`；`download_model.dart → toBaseMap / fromMap` |
| 下载目录下漫画文件夹 | `cover.jpg`，有章节时使用从 1 开始的章节目录，图片文件 basename 从 0 开始 | `lib/network/download_model.dart → _addDownloading / getLinks`；`download.dart → getImage` |
| `favoritesCover/`、`rule.json`、`log.txt` | 收藏封面副本、hosts 代理配置与运行日志；Android 日志可放 external storage，iOS 不设置日志文件 | `lib/foundation/local_favorites.dart → addComic / getCover`；`lib/network/http_proxy.dart → createConfigFile`；`lib/init.dart → init` |

【已实现：静态依据】`Appdata.settings[90]` 控制多选收藏的数量结果提示，默认 `"1"`（开启）；由“设置 → 本地收藏”保存，沿用 settings 文件及导出/同步机制。旧配置缺少末尾字段时保留默认值；关闭提示不影响收藏数据库写入。

## 兼容性与合并语义

- 历史查找、更新和缓存均按 `target`，SQL 主键没有 `type`。本地收藏的单项及批量新增现在共用 `LocalFavoritesManager._insertComic → comicExists`，按 `(target, type)` 查重，与收藏表主键一致；列表收藏徽标使用的 `isExist / _cachedFavoritedTargets` 仍只按 `target`，不能把写入修正推广为所有身份处理均已统一。风险记录见[技术债](technical-debt.md)。
- 下载 ID：哔咔为原 ID，EH 为 `getGalleryId(link)`，JM 为 `jm<ID>`，Hitomi 为 `hitomi<ID>`，HT 为 `Ht<ID>`，NHentai 为 `nhentai<ID>`；通用自定义源为 `<sourceKey>-<id>`，还可能应用 `matchBriefIdReg`。依据：`lib/network/download.dart → AddDownloadExt / generateId`，消费者见 `lib/pages/reader/reading_data.dart → downloadId`。
- 章节约定：已下载章节列表和下载选择值从 0 开始；阅读 `ep/order` 和文件夹从 1 开始；图片页参数从 0 开始，阅读 UI 的有效 `index` 从 1 开始。依据：`ReadingData.checkEpDownloaded / loadImage`、`DownloadingItem.getLinks`、`ComicReadingPageLogic.index / order`。转换发生在多处，修改时逐处核对。
- 迁移是启动时的条件处理，没有集中版本迁移器：历史增加 `max_page` 并导入旧 `history.json`；收藏重建旧主键表、导入旧 JSON／临时数据库；下载从旧 `info.json` 建库。依据：`HistoryManager.init`、`LocalFavoritesManager._checkAndCreate / readData`、`DownloadManager._initDb`；SQLite 导入的事务失败和历史暂存恢复已验证，其他旧格式迁移与下载中断仍未验证。
- SQLite 导入由 `lib/foundation/import_database.dart → mergeFavoriteDatabases / mergeHistoryDatabases` 在后台以单库事务合并，成功后删除暂存文件；`HistoryManager.init` 也会尝试恢复 `history_temp.db`，失败保留暂存库并记录日志。WebDAV 导入的历史／图片收藏及本地收藏临时库以“已有则跳过、缺失则新增”为主；不是按每条记录时间合并进度。脚本和 Cookie 文件会被替换；如包里包含下载目录，该目录也会替换。依据：`HistoryManager.tryUpdateDb`、`LocalFavoritesManager.readData`、`lib/tools/io_tools.dart → importData`。
- `Appdata.readDataFromJson` 现在等待设置、屏蔽词、首次使用标记及合并后的收藏标签落盘后返回；`writeData(false)` 不再通过 `updateSettings` 间接触发同步。它保留本机下载路径 `settings[22]` 与生物识别开关 `settings[13]`，屏蔽词及收藏标签合并；`toJson` 不包含搜索历史和 implicitData。完整同步边界见[接口与集成](api-integrations.md)。

## 尚未验证

大库导入与暂存恢复的本轮实现及执行证据见[导入恢复变更](changes/2026-11-16-data-import-recovery.md)。其余跨源历史 ID 冲突、hashCode 长期兼容性、全部历史格式升级、并发导入与整包中断一致性仍属【推测／待核实】。

## 阅读统计与收藏分页排序（2026-11-17）

【已实现：静态依据】`lib/foundation/reading_stats.dart → ReadingStatistics` 使用独立 `reading_stats.db`（user_version=2），收藏文件夹继续保存在 local_favorite.db。统计模型如下。

| 表 | 身份与数据 | 合并规则 |
| --- | --- | --- |
| reading_sessions | session_id 主键；source_key、comic_id、累计 elapsed_ms、counted、updated_at | 同一会话累计取 max；身份冲突回滚，不重复累加 |
| comic_totals | `(source_key,comic_id)`；read_count、elapsed_ms | 从去重后的会话重新汇总，可重建 |
| image_books | 同上；total_hint、chapter_ids、known_count、complete、updated_at | 目录/可信总数按记录时间合并，数量缓存重算 |
| image_chapters | `(source_key,comic_id,chapter_id)`；pages、updated_at | 同章更新而非累加；按目录汇总 |
| chapter_progress | `(source_key,comic_id,chapter_id)`，furthest_page | 每章取最大页码，导入同一份数据幂等 |

`FavoriteType.sourceKey / ReadingData.statisticsIdentity` 统一统计身份：内置 htmanga 统一小写，NH 收藏类型为 6，不使用 HistoryType 的 5；Hitomi 使用收藏链接。自定义源仍需经过既有 intKey 映射，缺源/旧 hashCode 的长期兼容问题未因此解决。

完整数量显示 `90`，已知下限显示 `30+`，完全无数量为“未获取”；下限按 30 参与排序，只有未知永远排末。首次发现目录保留可信整本总数；已知目录变化时使旧总数失效并重算。重复章节不会重复相加。Pc 接口以章序访问，因此使用 `@chapter:N`，源若插入/重排章节仍存在索引身份局限。

`LocalFavoritesManager.onReadEnd` 按 `(target,type)` 更新各夹的 time，复用为最后阅读排序；由阅读器传入最后实际活动时间，未成功显示正文不覆盖。旧 time 保留，其中可能包含初始化时间，不能据此推断旧阅读次数；旧次数/时长从 0 开始。普通“清空历史”保留独立统计，`clearAppdata` 一并清空；重新导入旧统计备份可恢复此前数据，不是带删除标记的同步。

`FavoriteQuery` 只读关联统计汇总，先对全夹排序，保留有序 `(type,target)` 快照，再取当前页元数据，不改 display_order。快照占用与收藏夹条数相关，不是远端快照。settings[11] 为默认连续/分页，settings[91] 默认 60（20/40/60/80/100），settings[92] 保存每夹模式/排序/方向/页大小；改名移动相应配置。

整包导出使用 `VACUUM INTO` 快照纳入 reading_stats.db；导入复制为 reading_stats_temp.db，在后台单库事务合并，失败保留暂存库。收藏夹 JSON 含对应身份的 reading_statistics；缺少新字段的旧包仍可导入。普通备份包含所有会话，清除后再导入可恢复；不宣称跨库/文件整包原子性。源码为 `lib/tools/io_tools.dart / init.dart / local_favorites.dart`，验证范围见[实施记录](changes/2026-11-17-reading-statistics-favorites.md)。

版本 1 统计库导入后保留原有统计，逐章最远页码从后续阅读开始记录。新版数据包可恢复进度，收藏夹 JSON 中的 `progress` 为可选字段。显示和迁移规则见[逐章最远阅读进度](changes/2026-11-19-chapter-reading-progress.md)。

### 旧阅读图片数只读兼容（2026-11-18）

`reading_image_count.dart / FavoriteQuery / ReadingStatistics.metrics` 将同来源旧 history.max_page 作为图片数量的回退；完整新总数优先，其他情况取已有下限最大值，Pc/JM/自定义源仍为 `N+`。统计查询与卡片/菜单统一口径，不把两个可能重叠的章节数相加。NH/Hitomi 按实际历史身份映射，不回写或伪造旧阅读会话。该回退依赖原历史库，文件夹 JSON 仍仅包含已有独立统计；详见[显示修复](changes/2026-11-18-favorites-display-fixes.md)。
