# 代表性业务调用链

[返回知识库](README.md)。本轮按入口、实现、存储／外部边界核对下列流程。调用链说明以【已实现：静态依据】为主；后续中性夹具验证、按用户请求执行的数据恢复及用户验收分别在对应变更中标注，不将它们推广为全源或全部流程通过。启动全链路在[架构页](architecture.md#启动顺序)维护，存储约束在[数据页](data-model.md)维护。

## 通用浏览列表 → 多选本地收藏

【已实现：静态依据】`lib/components/comics_list.dart → ComicsPage.enableMultiSelect` 默认为关闭，仅搜索、分类结果、排行榜及通用探索长列表入口开启，并限定为五个已确认的内置源。网络收藏列表保持默认关闭；分区/混合主页和 Hitomi 不在该接入路径内。需求与验收记录见[本轮变更](changes/2026-11-16-multi-select-favorites.md)。

1. `ComicTile._onLongTap / _showLongTapMenu` 在列表选择上下文中显示“多选”，使用已有 `favoriteItem` 进入列表级 `ComicSelectionController`。
2. `ComicSelectionRegion / ComicSelectionScope` 管理工具栏、返回键和卡片勾选；`ComicTile.build` 在选择期间拦截详情/阅读等卡片内操作。选择键为 `(FavoriteType.key, target)`，全选只使用当前页/已加载的未屏蔽条目。
3. `ComicsPageLogic.refresh / updateMode` 清理选择；`ComicsPage.nextPage / prevPage / selectPage → changePage` 现在跨页保留集合，连续加载也保留选择。分页显示总已选/本页已选，可用“查看已选”图标移除跨页项目；全选和查看使用 32 像素纯图标，全不选图标清空所有页面累计的选择但保留多选状态。当前页计数和全选均按身份去重。
4. 一次选择目标文件夹后，`ComicSelectionController.save → LocalFavoritesManager.addComicsToFolder` 按条目写入并收集新增、已存在、失败；成功项不因其他项失败回滚，失败项保留以重试。收藏表结构不变。
5. 写库完成后更新收藏 UI 并沿用已有 `saveData` 同步行为；封面通过 `_cacheBatchCovers / _cacheComicCover` 后台顺序缓存，不将封面获取失败计为收藏失败。

## 1. JM 搜索 → 详情 → 阅读

1. `lib/pages/search_result_page.dart → SearchResultPage.build` 查找 `sourceKey`，选项数量不匹配时取各选项默认值；通用 `_SearchPageComicList.getComics` 调用 `searchPageData.loadPage`。
2. `lib/comic_source/built_in/jm.dart → jm.searchPageData` 转到 `JmNetwork.searchNew`；后者整理关键词、记录搜索历史并请求 `/search`，返回列表及分页 `subData`。`lib/components/comics_list.dart → ComicsPageLogic.get / loadNextPage` 消费结果、显示错误并控制分页。
3. JM 的 `_JmComicTile.onTap_` 打开 `ComicPage(sourceKey: 'jm', ...)`；`lib/pages/comic_page.dart → ComicPage.build` 发现 `comicPageBuilder` 后使用 `JmComicPage`，不是通用 `_ComicPageImpl`。
4. `lib/pages/jm/jm_comic_page.dart → JmComicPage.loadData` 请求 `JmNetwork.getComicInfo` 的 `/album`，解析章节、作者和收藏等信息。`read` 先 `History.createIfNull`，再构造 `ComicReadingPage.jmComic`；指定章节入口 `eps` 把 0 基索引转为 1 基章节号。
5. `lib/pages/reader/reading_data.dart → JmReadingData.loadEpNetwork` 通过章节 ID 调 `JmNetwork.getChapter` 的 `/chapter`；已下载章节会在 `ReadingData.loadEp` 更早走本地分支。网络图片进入 `ImageManager.getJmImage`，下载、重组后缓存。
6. `ComicReadingPageLogic.index` 变化回调 `_updateHistory`，写章节、页码和最大页数；阅读器退出时保存历史、执行本地收藏的阅读后排序、恢复屏幕设置。源码分别位于 `reading_logic.dart → index`、`comic_reading_page.dart → _updateHistory / build`。

失败边界：普通网络／解析错误通常转换为 `Res.error`；但 `JmNetwork.getComicInfo` 在部分“Empty data”路径显式抛异常，不能说所有失败都由 `Res` 表达。章节 `Res.error` 被 `ComicReadingPage.loadInfo` 写入 `logic.errorMessage`；图片失败由图片 provider／控件处理。实际重试、失效会话及图片错误 UI 尚未验证。

### 远程列表变化与分页一致性

【已实现：静态依据】通用列表没有为整次浏览固定远端数据快照。`lib/components/comics_list.dart → ComicsPageLogic.loadNextPage` 请求下一逻辑页后直接 `comics.addAll(res.data)`，未做列表身份去重，也不回头核对已加载条目。分页模式在 `dividedComics` 缓存已访问的应用页，合并 2／3 个源页时还在 `_sourcePages` 缓存每个成功的源页。分组失败后重试复用本组缓存，显式刷新清除缓存。详见[源页合并](changes/2026-11-19-source-page-grouping.md)。

| 模式 | 当前客户端行为 | 远端变化时的条件性影响 |
| --- | --- | --- |
| 连续 | 保留旧条目，追加新响应 | 页码边界变化可造成重复/漏项；远端删除的旧条目不会自动从当前列表移除 |
| 分页 | 已访问页复用缓存，未访问页向源适配器请求 | 缓存页和后加载页可能来自不同时点；翻回旧页不保证重新请求，边界变化同样可能重复/漏项 |

【推演／待核实】假设源按当前排序和固定每页 3 条进行偏移分页：首次为 `A B C | D E F`。看过第一页后若顶部插入 X，新第二页变为 `C D E`，C 会重复，X 不会自动插回已看过的第一页；若删除已看过的 B，第二页变为 `E F G`，D 可能被跳过。按热度等排序重新排列也会产生类似边界变化。该例是分页算法推演，未向真实站点执行增删测试，不表示每个源都有相同服务端实现。

【已实现：静态依据】搜索适配器中，JM 的 `JmNetwork.searchNew`、哔咔 `PicacgNetwork.search`、HT `HtmangaNetwork.getComicList`、NHentai `NhentaiNetwork.search` 都发送页码参数或页码 URL。EH 经 `lib/network/eh_network/eh_gallery_page_loader.dart → EhGalleryPageLoader` 缓存结果，并跟随 `EhNetwork.getGalleries` 从网页 `dnext` 提取的下一页链接。应用页号先换算为源页组，再由 EH 适配器按链接解析个别源页。EH 的游标在服务端动态变化时的表现仍待在线核对。

多选键仍是 `(FavoriteType.key, target)`，收藏写入也按 `(target,type)` 查重，所以列表出现重复卡片不代表同一收藏夹会重复写入。已加载元数据不会因远端删除而主动失效，仍可能保存为本地收藏，之后详情/阅读可能不可用。分页切页与连续追加均保留选择；显式刷新/切换范围等边界仍清空。

其他静态边界：`loadNextPage` 在返回 `Res.error` 后仍执行 `current++`，失败页可能被跳过；连续与分页的后续成功响应现在都会更新 `maxPage`，但已缓存页及已判定结束的列表不会主动探测远端新增页。连续追加错误递增页号这一问题尚未修改；跨页选择实施已调整分页缓存响应归属、当前页重试和总页数更新，详见[跨页变更](changes/2026-11-16-cross-page-selection.md)。

<a id="分页跨页多选的可行性待确认方案"></a>

### 分页跨页多选

用户已明确要求实施，现已替代首版翻页清空规则。需求、源码依据和验证范围见[跨页变更](changes/2026-11-16-cross-page-selection.md)。

【已实现：静态依据】`ComicSelectionController` 按 `(FavoriteType.key,target)` 保存选中时的 FavoriteItem 副本，重复条目不覆盖原资料；`ComicsPageLogic.changePage` 保留选择，`get` 按请求时页号缓存响应，`retry` 重试当前页并保留集合。分页空页和错误页也提供翻页入口，远端总页数缩小时可返回先前页。

同一列表会话内，上一页/下一页/跳页保留；全选仅追加当前页；工具栏显示总已选和本页已选，“查看已选”可移除任意已选项目。普通收藏和长按快速收藏提交整个集合；刷新、换源、改关键词/筛选/排序、切换显示模式、退出多选或关闭列表会话清空，不跨重启持久化。

远端新增不自动选中，重排或跨页重复按来源+ID识别；新页没有出现某项不等于远端已删除，因此不自动取消该项。仍可用选中时元数据保存本地收藏，后续详情/阅读可能失效，不默认逐条远程校验。跨页选择保持集合稳定，不保证页码源遍历无漏项，也不改变 EH 服务端下一页规则。

## 2. 安装自定义源 → 通用详情与图片

1. `lib/pages/settings/comic_source_settings.dart → chooseFile / handleAddSource` 从本地 `.js` 或 URL 获取文本，统一进入 `addSource`。
2. `lib/comic_source/parser.dart → createAndParse` 把内容写入应用 `comic_source/`；解析失败删除本次创建的文件并重新抛错。`parse` 要求首个非空行以 `class ` 开头且包含 `extends ComicSource`，执行脚本后读取元信息，检查最低版本、重复 key 和 key 字符集。
3. `ComicSourceParser.parse` 将 JS 实例登记到 `ComicSource.sources.<key>`，把搜索、详情、章节、收藏等转换成 Dart 回调，读取源 `.data`，延迟调用源 `init()`。安装成功后设置页 `addSource` 将 Dart 实例加入 registry、添加页面配置、保存设置并刷新应用。
4. 通用搜索经过 `_loadSearchData` 调 JS `search.load(keyword, options, page)`，结果 `{comics, maxPage}` 转成 `CustomComic` 列表；通用详情 `ComicPage → _ComicPageImpl.loadData` 调 `comic.loadInfo(id)` 转成 `ComicInfoData`。
5. `_ComicPageImpl.read / eps` 创建历史并构造 `CustomReadingData`；其 `loadEpNetwork` 调 `comic.loadEp(id, ep)`，解析 `{images}`。`ImageManager.getCustomImage` 应用 `comic.onImageLoad` 返回的 URL／method／headers／data，以及可选 `onResponse` 字节转换。

失败边界：元信息非法或版本过低导致安装失败；单个已安装源启动解析失败会由 `ComicSource.init` 记录后继续其他源。回调异常通常转换成 `Res.error`；收藏和发评论的部分路径识别含 `Login expired` 的错误并尝试重新登录一次，不能推广到全部请求。已保存的账户状态和实际 Cookie 有效性也不同，见[漫画源模块](modules/comic-sources.md)。

## 3. 下载 → 重启恢复 → 本地阅读

```mermaid
sequenceDiagram
    participant UI as 漫画详情页
    participant DM as DownloadManager
    participant Task as DownloadingItem
    participant IM as ImageManager
    participant Store as 文件与SQLite
    UI->>DM: addJmDownload / addCustomDownload 等
    DM->>Store: newDownload.json
    DM->>Task: 队首 start
    Task->>Task: getLinks / downloadCover
    Task->>IM: 下载图片并接收进度
    Task->>Store: 图片文件与进度
    Task->>DM: onFinish
    DM->>Store: download.db 与队列
    DM->>Task: 下一队首 start
```

入口依据：`lib/pages/jm/jm_comic_page.dart → download`、`lib/pages/comic_page.dart → _ComicPageImpl.download`，最终进入 `lib/network/download.dart → AddDownloadExt`。详情页先检查重复／已下载并选择章节；不能假设 manager 对所有直接调用也强制完成同等去重。

核心依据：`DownloadManager._saveInfo / _onFinish / start`、`lib/network/download_model.dart → DownloadingItem.start / _scheduleTasks / toBaseMap`。队列按漫画串行，任务内按 `settings[79]` 并发图片，默认 6；任务出错采用延迟重试，超过 4 次重试后调用 manager `_onError` 暂停并保留错误状态。

恢复依据：启动 `DownloadManager.init → _getInfo` 从 JSON 重建任务；`lib/pages/main_page.dart → _checkDownload` 询问是否继续，不是自动无条件恢复。队列 JSON 损坏时记录日志、删除该 JSON 并重建，不能承诺保留所有未完成任务。

本地阅读依据：`lib/pages/download_page.dart → ReadComic.read` 根据下载类型重建源对应阅读数据与历史；`ReadingData.loadEp / createImageProvider` 根据已下载章节选择 `FileImageProvider`，否则走网络。下载文件缺失、源被禁用以及自定义源丢失时的兼容表现仍待验证，详见[阅读与下载模块](modules/reader-download.md)。

【已实现：静态依据】多选工具栏的“本地收藏”短按选择收藏夹，长按由 `ComicSelectionRegion._quickSave` 直接使用设置中的快速收藏夹 `settings[51]`；未配置/目标失效时仅提示并保留选择。两种操作复用批量写入与结果反馈，见[多选收藏变更](changes/2026-11-16-multi-select-favorites.md#多选长按快速收藏2026-11-16)。

## 4. 本地收藏 → 备份与同步导入

1. 以 JM 为代表，`JmComicPage.openFavoritePanel` 区分平台收藏和本地收藏：平台操作调用 `JmNetwork.favorite`，本地操作进入 `LocalFavoritesManager.addComic`。平台收藏可用性受源登录状态影响，本地收藏有独立数据表。
2. `lib/foundation/local_favorites.dart → addComic` 查重、插入目标收藏夹表，通知 UI、请求 WebDAV 上传，并尝试把封面复制到 `favoritesCover/`；封面复制失败会被忽略，不等于插入回滚。
3. `lib/network/webdav.dart → uploadData` 调用 `lib/tools/io_tools.dart → exportDataToFile(false, ...)` 生成不含下载目录的包，按版本名上传。配置与包内容仅在[接口页](api-integrations.md#webdav-与数据包)维护。
4. `Webdav.downloadData → importData / importDataFromFile` 在独立目录解包校验；旧／相同 WebDAV 版本整包跳过，手工选择文件绕过版本限制。`LocalFavoritesManager.readData` 与 `HistoryManager.tryUpdateDb` 调用后台事务合并缺少的记录，每库一次提交后刷新缓存；历史启动也恢复暂存库。源文件和 Cookie 的替换语义与收藏合并不同，不能笼统说“全部合并”或“全部覆盖”。

失败边界：`addComic` 是 `async void`，调用方显示成功不代表封面和同步已完成；WebDAV 上传返回值也未被所有写调用等待。大库与暂存恢复已有[独立真机回归及本机恢复记录](changes/2026-11-16-data-import-recovery.md)，但远端失败后的 UI、并发本地变更和跨多个数据库/文件的整包原子性仍未验证。

## 未覆盖的流程

【推测／待核实】其他五源登录、搜索边界、网络收藏夹与本地文件夹持续关联同步、批量导出／PDF、全部阅读手势与双页模式、后台签到、所有深链接路径没有完成端到端分析或执行。继续入口与优先级在[索引](README.md#快照与继续入口)。
