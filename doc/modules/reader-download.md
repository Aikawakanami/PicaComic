# 阅读、图片与下载

- 范围：`lib/pages/reader/`、下载 manager／任务模型、图片 manager 与下载页读取入口。架构依赖见[架构](../architecture.md)，数据 ID／索引约束见[数据模型](../data-model.md)。
- 分析状态：已分析章节选择、本地／网络分支、历史写回、队列与任务生命周期；手势、全部图片算法、平台交互仍为部分覆盖。
- 证据类型：实现依据和验证范围分别标注。

## 阅读主路径

| 内部机制 | 当前源码锚点 |
| --- | --- |
| `ComicReadingPage` 接收通用 `ReadingData` 或源专用构造参数，在构造时注册控制器 | `lib/pages/reader/comic_reading_page.dart → ComicReadingPage / picacg / jmComic` |
| 阅读状态含 1 基章节 order、带边界空白页的 index、图片 URL 列表、加载／错误、翻页与缩放控制器 | `lib/pages/reader/reading_logic.dart → ComicReadingPageLogic / index / jumpToChapter` |
| 六种阅读方式由 `settings[9]` 转换成 enum，包括连续纵向与双页；触摸、键盘、音量及工具栏分别位于 part 文件 | `lib/pages/reader/reading_type.dart → ReadingMethod`；`reading_logic.dart → readingMethod` |
| 章节下载状态决定 `loadEp` 返回占位链接列表还是实际源链接；已下载图片使用 `FileImageProvider` | `lib/pages/reader/reading_data.dart → ReadingData.loadEp / loadImage / createImageProvider` |
| 未下载章节委托对应 ReadingData 的 `loadEpNetwork / loadImageNetwork`，自定义源委托 `loadComicPages` 与 `ImageManager.getCustomImage` | `reading_data.dart → JmReadingData / CustomReadingData` |
| 位置变化及退出会调用历史写回；开始／结束位置可能存 ep=0、page=0，而非保留边界页 | `comic_reading_page.dart → _updateHistory`；`lib/foundation/history.dart → saveReadHistory` |
| 进入／退出阅读器调整图像缓存限额、系统 UI 与方向，退出调用本地收藏 onReadEnd 并清理控制器 | `comic_reading_page.dart → build` 的 StateBuilder initState／dispose |

`ComicReadingPage.loadInfo` 将章节 `Res.error` 写到 `logic.errorMessage`；成功时更新 urls。阅读器假定正常入口已经创建 History，其 `_updateHistory` 使用 `history!`；详情页及下载页分别在进入前调用 `History.createIfNull / findOrCreate`。新增入口必须检查这个前提。

## 图片与缓存边界

`lib/foundation/image_manager.dart → ImageManager` 是阅读和下载共用的图片获取层，`loadingItems` 跟踪正在加载的 key，`CacheManager` 管理磁盘缓存，ImageProvider 另有内存缓存。`getImage`、`getJmImage`、`getEhImageNew`、`getHitomiImage`、`getCustomImage` 是不同路径，不应将其中一个的请求头、重组或缓存 key 规则推广到全部来源。

【已实现：静态依据】磁盘缓存以 `settings[35]` 的容量为上限，封面、阅读图片和部分网络响应共用。`lib/foundation/cache_manager.dart → _scanExistingFiles / _publish / _evictBatches` 按实际字节计量，超限分批淘汰，在没有进展时结束本轮。过期清理仍独立生效。固定 2,000 条门槛已取消。

【已验证：执行证据】Android 14 将上限临时设为 16 MiB 后，真实 EH 单页在线阅读从第 1 页翻到第 99 页。早期图片的磁盘缓存被淘汰后，前翻、回翻以及重启后的重新加载均通过。原因复现、测试步骤和边界见[缓存修复记录](../changes/2026-11-18-disk-cache-capacity.md)。

已核对 JM 的 `getJmImage` 会去掉 URL 查询参数作为 key，非 GIF 经过 `startRecombineAndWriteImage` 再落盘；重组算法内部仍未分析。自定义在线图片支持请求改写及 JS `onResponse` 转换，其结果必须是 Uint8List；下载路径的能力差异见[技术债](../technical-debt.md)。

预加载入口为 `lib/pages/reader/image_view.dart → precacheComicImage`，使用 `settings[28]`，无活动图片任务时再多预加载部分页面。双页布局、连续滚动和 cache 释放效果需要设备运行验证，本轮不承诺内存或性能指标。

## 下载任务状态与落盘

| 阶段 | 当前实现／错误边界 | 源码锚点 |
| --- | --- | --- |
| 初始化 | 默认 `${App.dataPath}/download`，可用 `settings[22]` 指定；加载 JSON 队列和 SQLite 已完成条目 | `lib/network/download.dart → _getPath / _getInfo / _initDb` |
| 入队 | `AddDownloadExt.add*Download` 添加任务、保存队列、在空闲时启动队首；重复检查主要位于各详情 UI | `download.dart → AddDownloadExt`；`lib/pages/comic_page.dart → download` |
| 执行 | 漫画任务串行；任务内图片按 `settings[79]` 并发，默认 6；runtimeKey 用于使旧一轮执行失效 | `lib/network/download_model.dart → DownloadingItem.start / _scheduleTasks / _runtimeKey` |
| 进度 | `toBaseMap` 保存章节／图片索引、链接、目录及已完成预取任务；每张图完成及章节切换更新 JSON | `DownloadingItem.toBaseMap / fromMap`；`DownloadManager._saveInfo` |
| 暂停／取消 | `pause` 使执行失效并停止活动任务；`stop` 还会删除当前任务文件／章节，不能把取消当作只暂停 | `DownloadingItem.pause / stop`；`DownloadManager.pause / cancel` |
| 错误 | `retry` 指数延迟，前 4 次重试后仍失败则 onError，manager 暂停并通知；不自动跳过错误漫画 | `DownloadingItem.retry`；`DownloadManager._onError` |
| 完成 | 移除队首，`toDownloadedItem` 写入或替换 download.db，保存队列并启动下一项 | `DownloadManager._onFinish / _DownloadDb._addToDb` |
| 重启 | 重建任务后由主页面 `_checkDownload` 提示继续；JSON 读坏会删除重建，未保证崩溃时原子恢复 | `DownloadManager._getInfo`；`lib/pages/main_page.dart → _checkDownload` |

`lib/network/jm_network/jm_download.dart → JmDownloadingItem` 是已读的内置任务实例：按用户选择获取章节、重试链接、复用 JM 图片重组。`lib/network/custom_download_model.dart → CustomDownloadingItem` 是自定义任务实例：有章节时用源章节 ID 获取链接，无章节时用 key=0；当前 `_getImage` 只把改写后的 URL 与 headers 交给 `getImage`。

## 修改入口与约束

【建议】改翻页／阅读位置先读 `reading_logic.dart`、`reading_data.dart` 和 `_updateHistory`；改断点恢复先读 `DownloadingItem.toBaseMap / fromMap` 与 `_getInfo`；改 ID 或章节索引同时核对详情页、下载页、SQLite 和文件目录，不直接复用其他 enum 索引。

【建议】改图片逻辑同时核对在线阅读、下载、本地文件 provider 和封面加载。`DownloadManager.updatePath` 涉及数据复制与删除，应作为独立数据操作验证，不能用常规启动检查代替。

## 验证与未知项

首轮分析时未运行 Flutter／Dart（当时 PATH 不可发现），当时仓库没有有效业务测试；缓存验证见上文，其他增量验证见下节。仍待验证：无章节自定义源、下载期间切换页面、暂停／取消／重试竞态、队列中断写入、源禁用后离线阅读、缺图文件、双页边界与资源释放。相关候选问题仅记录在[技术债](../technical-debt.md)。

## 阅读统计与图片数量（2026-11-17）

【已实现：静态依据】`ComicReadingPage` 使用 `ReadingStatisticsBoundary` 管理路由可见性和应用生命周期；`ComicReadingPageLogic.observeImage / _updateReadingActivity` 仅在正文当前页成功解码、前台可见且不在加载/错误状态时启动计时。预加载或仅取得 URL 不启动计时；双页可用任一正文页。`ReadingSessionTracker` 用单调时钟，10 秒周期检查点及暂停/退出结算，有效累计满 10 秒记一次。每个阅读器路由一个会话，换章/后台恢复沿用该会话，各章有效时长合计；退出再进入是新会话。强杀可能丢失末次尚未保存的不足 10 秒。

`loadInfo → ReadingData.loadEp` 在线和离线统一记录章节长度；`statisticsChapter / statisticsCatalog` 区分源章节 ID、单章、Pc 章序，避免重复相加。`recordReadingMetadata` 复用详情/直接阅读/更新信息中已有的可信整本总数；加入收藏也保留列表自带数量。没有主动抓取全库。部分章显示 `30+`，全部覆盖或得到可信总数才显示完整数值；完全没有数量显示未获取。原 `History.maxPage` 仍是当前章节长度，不充当整本总数。

来源、存储和备份边界见[数据模型](../data-model.md#阅读统计与收藏分页排序2026-11-17)；需求和验证见[实施记录](../changes/2026-11-17-reading-statistics-favorites.md)。

【已验证：执行证据】电脑端测试覆盖当前页成功解码、相邻页不误计、换章暂停及累加，实际 Flutter 生命周期事件和覆盖路由暂停/恢复；2026-11-18 已更新真机正常包并确认启动；统计业务交互仍待验收。真实源全部入口、锁屏、离线缺图、双页、强杀及平台差异仍需后续真机验收，不能把主机模拟当作 Android 验证。
