# 有源码依据的风险与待核实项

[返回知识库](README.md)。这是首轮分析形成的候选清单，不代表每项均已复现或获授权修复。每项将静态事实、潜在影响和执行证据分开；首轮未修改业务代码，后续独立授权的实施进度在对应条目维护。

## KB-01：有效业务测试与自动检查缺口

- 【已实现：静态依据】原 `test/widget_test.dart → main` 仍为空；多选功能新增 `test/comic_selection_test.dart` 、`integration_test/multi_select_favorites_test.dart` 和 `integration_test/data_import_test.dart`。已读 `.github/workflows/main.yml / linux.yml / ios_simulator.yml` 仍仅手动构建与上传，没有 `flutter analyze / flutter test`。
- 【推测／待核实】阅读位置、下载恢复和源契约改动目前缺少仓库内自动回归证据；不能据此推断项目无法运行。
- 【已验证：执行证据】多选状态/布局的 8 项回归通过；当前 Android 真机已通过五源通用搜索、翻页、分类/排行/探索入口、连续追加及实际收藏 SQLite 的 5 组集成场景，另有 1 组关键词/排序/漫画源切换场景通过。范围、命令和验证限制见[多选变更](changes/2026-11-16-multi-select-favorites.md)。另有大库 SQLite 导入/历史暂存恢复的 4 组真机回归通过，见[导入恢复](changes/2026-11-16-data-import-recovery.md)。这些证据不覆盖阅读、下载或全部旧格式迁移。
- 【建议】后续实际修改时继续补相应回归；无章节源与图片 hook 仍需独立验证。

## KB-02：跨源身份及收藏查重规则不一致

- 【已实现：静态依据】`lib/foundation/history.dart → HistoryManager.init / addHistory / findSync` 以 `target` 单独建主键和查询；本地收藏表使用 `(target,type)` 主键。本轮[多选收藏](changes/2026-11-16-multi-select-favorites.md)将单项及批量新增共用的 `_insertComic` 改为调用 `comicExists(folder, target, type)`，收藏写入的前置查重已与主键一致；`isExist / _cachedFavoritedTargets` 的徽标缓存仍只用 target。两个模型的类型编码还不同，见[数据模型](data-model.md)。
- 【推测／待核实】两个来源返回相同 target 时，历史可能复用另一来源记录，收藏徽标也可能跨源误判；收藏写入修正不代表这些路径已经统一。没有使用真实收藏数据验证这些剩余影响。
- 【已验证：执行证据】多选真机测试使用临时 SQLite，确认同 target 的 EH 类型与 JM 类型可分别新增；通过临时触发器注入部分失败，确认成功项保留、失败项可单独重试。未迁移数据库，也未使用个人收藏数据。
- 【建议】用两个不同源但相同 target 的最小数据核对创建、读取、列表状态和备份合并，再决定是否需要一致的复合身份和迁移；不要只改建表语句。

## KB-03：无章节自定义源的可空契约不一致

- 【已实现：静态依据】`lib/pages/reader/reading_data.dart → CustomReadingData.hasEp / loadEpNetwork` 接受 `eps == null`，但同类 `buildImageKey` 使用 `eps!`；网络路径 `ReadingData.createImageProvider` 会调用该方法。`lib/comic_source/comic_source.dart → ComicInfoData.fromJson` 与 `lib/network/custom_download_model.dart → CustomDownloadedItem.fromJson` 也把可空 chapters 直接交给 `Map.from`。
- 【推测／待核实】无章节源在线创建图片 key、队列重载或下载记录读取可能出现空值异常。当前环境未运行，因此没有声称已复现某个 UI 错误。
- 【建议】准备不含 chapters 的最小 JS 源及其序列化数据，分别核对在线阅读、持久化往返、重启恢复与离线阅读。

## KB-04：在线图片与自定义下载 hook 能力不同

- 【已实现：静态依据】`lib/foundation/image_manager.dart → getCustomImage` 使用 URL、method、data、headers 和 onResponse；`lib/network/custom_download_model.dart → CustomDownloadingItem.downloadImage / _getImage` 只将 URL 和 headers 转给 `ImageManager.getImage`。
- 【推测／待核实】依赖 POST、请求体或响应解码的源可能在线可读而下载失败／保存非预期内容。尚未运行使用这些 hook 的样本。
- 【建议】用相同图片配置对照在线与下载输出，再决定共享处理路径或明确能力边界；验收需覆盖实际字节结果，不能只检查 HTTP 成功。

## KB-05：旧 Cookie 迁移读取后缺少可见的保存步骤

- 【已实现：静态依据】`lib/init.dart → _checkOldData` 从旧 PersistCookieJar 读取并收集 `cookies`，随后删除旧 Cookie 目录；该函数内未找到把列表写入 `SingleInstanceCookieJar` 的调用。新 Cookie 库已在此前 `init` 中创建。
- 【推测／待核实】满足迁移条件的旧安装可能不能保留会话；从零安装不会验证这条路径。未对用户应用数据执行迁移。
- 【建议】在独立临时目录准备旧格式 Cookie fixture，核对新库内容及删除时序；再确认是否存在其他补偿路径和历史兼容要求。

## KB-06：启动返回与服务就绪并不等价

- 【已实现：静态依据】`lib/init.dart → init` 捕获初始化异常后仅写日志；`lib/foundation/js_engine.dart → JsEngine.init` 也捕获异常；`lib/main.dart → main` 随后仍进入 runApp。多个消费者使用 late 字段或单例非空断言。
- 【推测／待核实】文件／数据库／JS 初始化失败可能在更晚页面表现为另一异常。没有进行故障注入，也未证明每种失败都会崩溃。
- 【建议】下一轮运行验证先观察最小启动，再对一个明确初始化失败点验证可见错误与恢复；不要同时重构全部单例。

## KB-07：日志与备份的认证信息边界

- 【已实现：静态依据】`lib/network/app_dio.dart → AppHttpAdapter.fetchOnce` 记录请求 headers／data；`MyLogInterceptor.onResponse` 记录响应头／正文，移除的是 `cookie` 而非所有认证头；`lib/foundation/log.dart → LogManager.addLog / writeLog` 可写文件。`lib/tools/io_tools.dart → _exportData` 还打包源状态、Cookie 和含 WebDAV 配置的 appdata，调用路径没有显式加密步骤。
- 【推测／待核实】日志或同步包可能含认证数据；本轮没有读取真实凭据、检查真实产物或进行安全渗透测试。
- 【建议】未来涉及日志导出／备份时，用合成认证字段核对实际产物，再确认脱敏与备份范围需求。TLS 例外已在[接口页](api-integrations.md#公共网络栈)单独记录，未完成全面网络安全审计。

## KB-08：大库导入的逐条副作用与恢复缺口（本轮修复）

- 【已实现：静态依据】原收藏导入逐条刷新/保存并并发缓存封面；原历史导入逐条重建全量缓存，且启动不恢复 `history_temp.db`。现由 `lib/foundation/import_database.dart` 在后台事务合并，成功后刷新一次，不预缓存整库封面；`HistoryManager.init` 尝试恢复暂存库。导入 UI 在 finally 关闭等待窗口。
- 【已验证：执行证据】独立 Android 包 25,231 条收藏的导入约 533 ms，事件循环仍响应；重复导入、事务回滚、错误重试及 7,028 条历史/6 条图片收藏的启动恢复通过。用户指定的备份也已通过正常界面成功导入，逐条身份核对一致，冷启动进入应用。原导出哈希未改变。
- 【推测／待核实】没有完整复现用户最初的白屏过程；此修复不保证所有异常源、下载载荷、并发同步或跨库/文件的整包原子性，早期 JSON 迁移另需验证。实现和环境隔离事故记录见[导入恢复](changes/2026-11-16-data-import-recovery.md)。

## KB-09：动态远端列表缺少浏览快照与连续追加去重

- 【已实现：静态依据】`ComicsPageLogic.loadNextPage` 直接追加响应，`dividedComics` 缓存已访问页；没有跨页列表去重或远端删除校验。该方法在 `Res.error` 后仍递增 `current`。分页读取的总页数和当前页重试已随[跨页选择](changes/2026-11-16-cross-page-selection.md)调整，缓存页仍不主动刷新。EH 主页/搜索另有下一页链接与页面缓存，不能按普通页码源一概而论。
- 【推演／待核实】页码源实时列表增删/重排可能造成重复、漏项和缓存陈旧；失败页可能被跳过。分析依据与具体示例见[业务流程](business-flows.md#远程列表变化与分页一致性)，未在真实源执行增删测试。
- 【建议／已暂缓】连续失败暂停、手动重试、按入口能力决定是否手动跳过、首批/追加来源+ID去重及无新增保护已记入[2026-11-17 待实施方案](changes/2026-11-17-continuous-loading-plan.md)。用户要求之后再做，业务代码未改；去重不能补回已遗漏条目。

## KB-10：收藏时间与阅读统计的兼容边界

- 【已实现：静态依据】新增独立统计库，按来源+收藏 ID 记录会话；`onReadEnd` 的 UPDATE 已补齐 type 限制。全夹排序/本地分页、跨页选择和图片数量下限已实现，见[实施记录](changes/2026-11-17-reading-statistics-favorites.md)。
- 【保留限制】按用户决定沿用 time，不新增原始收藏时间；旧未读行的初始化 time 不能当作真实阅读证据。次数/时长不从旧历史推测，原历史 target 主键未改。
- 【推测／待核实】Pc 按章序而非稳定源章节 ID，远端中间插章/重排会影响数量对应；可信总数与目录是上次已知数据；跨设备时钟冲突、旧 hashCode 来源映射仍需专项验证。统计清空没有删除墓碑，旧备份可恢复旧会话。没有自动全库补全。
- 【已验证：执行证据】主机临时数据库和 Flutter 测试见实施记录；2026-11-18 已更新真机并确认启动，新功能真实源/生命周期/离线和完整压缩包通道仍待验证。

## KB-11：长列表磁盘缓存清理无响应

- 【已验证：执行证据】旧版 `CacheManager.checkCache` 在 2,001 条且容量未超限时可因旧计数反复查询空表，已复现。历史 Android 触摸超时的栈位于 SQLite，缺少事发时的 SQL、条目数和容量。
- 【已实现：静态依据】移除条目限制，按字节淘汰并在没有进展时退出。主机回归、Android 合成写入和 EH 真机在线阅读的执行证据见[缓存修复记录](changes/2026-11-18-disk-cache-capacity.md)。
- 【推测／待核实】真实长列表的封面解码、内存压力，以及其他来源和更长时间的读图表现仍待验证。

## 开发前需消除的环境不确定性

【已实现：静态依据】SDK 下限的清单／锁文件差异、浮动 stable CI、Android 未入库配置、会写文件的打包／翻译脚本，详见[开发指南](development.md)。这些是本轮开发准备的限制，不是已证明的构建失败。

【建议】下一轮先获得可运行的独立 Flutter 环境，再优先核对 KB-03／KB-04 的自定义源阅读与下载边界；需要变更持久化身份时，应单独确认兼容与迁移方案。其他源完整协议、所有平台与大规模数据性能仍保持未验证状态。
