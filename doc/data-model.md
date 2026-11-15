# 数据模型与持久化

[返回知识库](README.md)。以下为【已实现：静态依据】，来自当前建表、序列化与调用代码；没有打开真实用户数据库或执行迁移。

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
| SharedPreferences | `search`、`favoriteTags`、`blockingKeyword`、`firstUse`、`implicitData` 等；`implicitData` 被明确排除出同步模型 | `lib/base.dart → readData / writeHistory / readImplicitData / toJson` |
| `comic_source/<key>.data`、`comic_source/*.js` | 源状态 JSON 与用户安装的脚本；状态可能包含账户信息 | `lib/comic_source/comic_source.dart → loadData / saveData / init`；`parser.dart → _loadAccountConfig` |
| `history.db → history` | `target TEXT PRIMARY KEY`；另含 title、subtitle、cover、time、type、ep、page、readEpisode、max_page。`readEpisode` 写成逗号分隔字符串 | `lib/foundation/history.dart → init / addHistory / saveReadHistory` |
| `history.db → image_favorites` | 主键 `(id, ep, page)`；title、cover、other 等，`other` 是 JSON；与历史共用数据库 | `lib/foundation/image_favorites.dart → ImageFavoriteManager.init / add` |
| `local_favorite.db` | 每个收藏夹直接作为一张表，主键 `(target, type)`；另有 `folder_order(folder_name PK, order_value)`、`folder_sync(folder_name PK, time, key, sync_data)` | `lib/foundation/local_favorites.dart → _checkAndCreate / createFolder` |
| `cookies.db → cookies` | 主键 `(name, domain, path)`；value、expires、secure、httpOnly 等字段；普通 Cookie 单例与 JM 的短期内存 CookieJar 不同 | `lib/network/cookie_jar.dart → CookieJarSql.init`；`lib/network/jm_network/jm_network.dart → cookieJar` |
| `cache.db → cache` | `key` 主键及 dir、name、expires、type；内容位于 `App.cachePath/cache/` 下，默认清理由 manager 控制 | `lib/foundation/cache_manager.dart → CacheManager._create / writeCache / checkCache` |
| 下载目录下 `download.db → download` | `id` 主键，title、subtitle、time、directory、size、json；json 保存各源特有已下载模型 | `lib/network/download.dart → _DownloadDb._createTable / _addToDb` |
| 下载目录下 `newDownload.json` | 队列与任务进度，包含 type、links、章节位置、图片位置、finishedTasks 等；每张图片完成可写入 | `lib/network/download.dart → _getInfo / _saveInfo`；`download_model.dart → toBaseMap / fromMap` |
| 下载目录下漫画文件夹 | `cover.jpg`，有章节时使用从 1 开始的章节目录，图片文件 basename 从 0 开始 | `lib/network/download_model.dart → _addDownloading / getLinks`；`download.dart → getImage` |
| `favoritesCover/`、`rule.json`、`log.txt` | 收藏封面副本、hosts 代理配置与运行日志；Android 日志可放 external storage，iOS 不设置日志文件 | `lib/foundation/local_favorites.dart → addComic / getCover`；`lib/network/http_proxy.dart → createConfigFile`；`lib/init.dart → init` |

## 兼容性与合并语义

- 历史查找、更新和缓存均按 `target`，SQL 主键没有 `type`。本地收藏表虽为复合主键，`LocalFavoritesManager.addComic` 的前置查重只查 `target`；不要从建表约束推断所有写路径都能保存同 target 的不同源。风险记录见[技术债](technical-debt.md)。
- 下载 ID：哔咔为原 ID，EH 为 `getGalleryId(link)`，JM 为 `jm<ID>`，Hitomi 为 `hitomi<ID>`，HT 为 `Ht<ID>`，NHentai 为 `nhentai<ID>`；通用自定义源为 `<sourceKey>-<id>`，还可能应用 `matchBriefIdReg`。依据：`lib/network/download.dart → AddDownloadExt / generateId`，消费者见 `lib/pages/reader/reading_data.dart → downloadId`。
- 章节约定：已下载章节列表和下载选择值从 0 开始；阅读 `ep/order` 和文件夹从 1 开始；图片页参数从 0 开始，阅读 UI 的有效 `index` 从 1 开始。依据：`ReadingData.checkEpDownloaded / loadImage`、`DownloadingItem.getLinks`、`ComicReadingPageLogic.index / order`。转换发生在多处，修改时逐处核对。
- 迁移是启动时的条件处理，没有集中版本迁移器：历史增加 `max_page` 并导入旧 `history.json`；收藏重建旧主键表、导入旧 JSON／临时数据库；下载从旧 `info.json` 建库。依据：`HistoryManager.init`、`LocalFavoritesManager._checkAndCreate / readData`、`DownloadManager._initDb`；尚未验证中断或回滚。
- WebDAV 导入的历史／图片收藏及本地收藏临时库以“已有则跳过、缺失则新增”为主；不是按每条记录时间合并进度。脚本和 Cookie 文件会被替换；如包里包含下载目录，该目录也会替换。依据：`HistoryManager.tryUpdateDb`、`LocalFavoritesManager.readData`、`lib/tools/io_tools.dart → importData`。
- `Appdata.readDataFromJson` 保留本机下载路径 `settings[22]` 与生物识别开关 `settings[13]`，屏蔽词及收藏标签合并；`toJson` 不包含搜索历史和 implicitData。完整同步边界见[接口与集成](api-integrations.md)。

## 尚未验证

【推测／待核实】跨源 ID 冲突的实际数据样本、hashCode 长期兼容性、所有历史版本升级、SQLite 并发／事务一致性、损坏包恢复和大库性能。本轮没有执行任何应用数据的导入、清理或迁移。
