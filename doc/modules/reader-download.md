# 阅读、图片与下载

- 范围：`lib/pages/reader/`、下载 manager／任务模型、图片 manager 与下载页读取入口。架构依赖见[架构](../architecture.md)，数据 ID／索引约束见[数据模型](../data-model.md)。
- 分析状态：已分析章节选择、本地／网络分支、历史写回、队列与任务生命周期；手势、全部图片算法、平台交互仍为部分覆盖。
- 证据类型：以下为【已实现：静态依据】，没有运行应用、下载图片或操作用户数据。

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

本轮未运行 Flutter／Dart（PATH 不可发现），仓库没有有效业务测试。待验证：无章节自定义源、下载期间切换页面、暂停／取消／重试竞态、队列中断写入、源禁用后离线阅读、缺图文件、双页边界与资源释放。相关候选问题仅记录在[技术债](../technical-debt.md)，本轮没有实施修复。
