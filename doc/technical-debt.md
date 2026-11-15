# 有源码依据的风险与待核实项

[返回知识库](README.md)。这是首轮分析的候选清单，不是已运行复现的缺陷报告，也不代表已经授权实施修复。每项将静态事实、潜在影响和建议验证分开；本轮未修改业务代码。

## KB-01：有效业务测试与自动检查缺口

- 【已实现：静态依据】`test/widget_test.dart → main` 为空；已读 `.github/workflows/main.yml / linux.yml / ios_simulator.yml` 仅手动构建与上传，没有 `flutter analyze / flutter test`。仓库未发现其他已跟踪的测试文件。
- 【推测／待核实】阅读位置、下载恢复、数据导入和源契约改动目前缺少仓库内自动回归证据；不能据此推断项目无法运行。
- 【建议】后续实际修改时，为该行为补最小有效验证；优先覆盖下面的身份冲突、无章节源与图片 hook，不为本轮文档任务新增业务测试。

## KB-02：跨源身份及收藏查重规则不一致

- 【已实现：静态依据】`lib/foundation/history.dart → HistoryManager.init / addHistory / findSync` 以 `target` 单独建主键和查询；`lib/foundation/local_favorites.dart → createFolder` 使用 `(target,type)` 主键，但 `addComic` 前置检查只用 target。两个模型的类型编码还不同，见[数据模型](data-model.md)。
- 【推测／待核实】两个来源返回相同 target 时，历史可能复用另一来源记录；收藏可能在进入复合主键写入前被错误判重。没有使用真实收藏数据验证这一影响。
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

## 开发前需消除的环境不确定性

【已实现：静态依据】SDK 下限的清单／锁文件差异、浮动 stable CI、Android 未入库配置、会写文件的打包／翻译脚本，详见[开发指南](development.md)。这些是本轮开发准备的限制，不是已证明的构建失败。

【建议】下一轮先获得可运行的独立 Flutter 环境，再优先核对 KB-03／KB-04 的自定义源阅读与下载边界；需要变更持久化身份时，应单独确认兼容与迁移方案。其他源完整协议、所有平台与大规模数据性能仍保持未验证状态。
