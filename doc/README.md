# Pica Comic 项目知识库

本知识库沿用上游 `doc/` 目录，服务于后续源码理解和二次开发。产品介绍见[根 README](../README.md)，已有[漫画源说明](comic_source.md)和 [hosts 说明](hosts.md)保留原有职责。

## 按问题查阅

| 想了解什么 | 入口 | 维护边界 |
| --- | --- | --- |
| 启动、分层、导航与状态 | [架构](architecture.md) | 组合根与宏观依赖 |
| 实体、类型编码、SQLite、迁移 | [数据模型](data-model.md) | 身份、持久化与合并约束 |
| 搜索到阅读、安装源、下载恢复、收藏同步 | [业务流程](business-flows.md) | 四条代表性跨模块调用链 |
| JS／Dart 契约、HTTP、Cookie、代理、WebDAV | [接口与集成](api-integrations.md) | 客户端契约与外部边界 |
| 扩展漫画源 | [漫画源模块](modules/comic-sources.md) | 注册、解析、JS 桥接与修改入口 |
| 分页容量 1X／2X／3X | [源页合并](changes/2026-11-19-source-page-grouping.md) | 应用页映射、EH 顺序链接、部分失败与重试 |
| 连续加载失败不跳页与来源/ID去重（暂缓） | [待实施方案](changes/2026-11-17-continuous-loading-plan.md) | 失败暂停、按入口决定手动跳过、无新增保护与验收建议 |
| 阅读次数/时长与本地收藏分页排序 | [需求与实施记录](changes/2026-11-17-reading-statistics-favorites.md) | 有效会话、章节累计、图片下限、全夹排序和本地分页；已更新真机并启动，交互待验收 |
| 收藏未读图片数、旧页数排序与分页底部空白 | [显示修复](changes/2026-11-18-favorites-display-fixes.md) | 旧历史数量只读回退、取消排序恢复手动、去除重复安全区 |
| 导入后的旧收藏顺序与新收藏默认位置 | [收藏顺序恢复](changes/2026-11-19-favorite-order-recovery.md) | 原始导出比对、只校正旧项位置、新收藏默认放最前 |
| 详情封面失效及本地收藏、历史封面更新 | [封面回退与修复](changes/2026-11-19-detail-cover-fallback.md) | 共用回退、感叹号占位、显示成功后回写封面 |
| 长标题或小屏导致弹窗底部操作被截断 | [弹窗溢出修复](changes/2026-11-18-dialog-overflow.md) | 长按菜单、共用弹窗、下载详情与工具面板的滚动和回归 |
| 翻几十页后卡死及磁盘缓存上限 | [缓存容量修复](changes/2026-11-18-disk-cache-capacity.md) | 原因复现、按容量淘汰、合成压力与 EH 真机翻页／回翻 |
| 远程源增删时分页/连续模式的表现 | [列表一致性](business-flows.md#远程列表变化与分页一致性) | 当前追加/缓存行为、页码示例与 EH 边界 |
| 修改阅读、图片或下载 | [阅读与下载模块](modules/reader-download.md) | 生命周期、索引、缓存和队列 |
| 环境、命令、CI 与验证限制 | [开发指南](development.md) | 配置事实、脚本副作用、实际检查 |
| 优先核实的候选问题 | [技术债](technical-debt.md) | 静态依据、待验证影响与建议 |
| 数据包导入卡顿、历史暂存库恢复 | [导入恢复变更](changes/2026-11-16-data-import-recovery.md) | 修复边界、独立大库测试与本机恢复 |
| 分页多选跨页保留、查看已选与远端变化 | [跨页选择变更](changes/2026-11-16-cross-page-selection.md) | 已确认规则、实现及本地验证/真机交付 |
| 通用浏览列表多选加入本地收藏 | [多选收藏变更](changes/2026-11-16-multi-select-favorites.md) | 已确认范围、实现和逐项验收 |

证据约定：**【已实现：静态依据】**指源码支持；**【已验证：执行证据】**指实际执行并记录结果；**【推测／待核实】**指尚无运行证据；**【建议】**指未来动作。首轮分析不把外部站点可用性、应用运行或平台兼容性写成已验证；后续执行证据按具体平台和检查范围补充。

## 模块覆盖

状态：**已分析**只针对“已读范围”列声明的职责、入口、实现、依赖、边界和测试入口；**部分**表示仍有明确实现缺口；**未分析**表示只识别存在；**不适用／排除**见下文。测试入口已检查但没有有效业务用例，不代表任何模块运行通过。

| 模块／路径 | 分析状态 | 已读范围及关键源码锚点 | 文档 | 验证状态 | 缺口／下一步 |
| --- | --- | --- | --- | --- | --- |
| 启动与全局状态：`lib/main.dart`、`init.dart`、`base.dart`、`foundation/app.dart` | 已分析 | `main / init / App.init / Appdata.readData`，主路由、设置读取和异常边界 | [架构](architecture.md)、[数据](data-model.md) | Android 14 独立测试包首次启动通过，显示首次设置界面 | 启动故障注入、平台生命周期仍未验证 |
| 漫画源注册与安装：`lib/comic_source/`、`assets/init.js`、`foundation/js_engine.dart` | 已分析 | `ComicSource.init / ComicSourceParser.parse / JsEngine._messageReceiver`；搜索、详情、章节主适配 | [漫画源](modules/comic-sources.md) | 静态；未运行 | 全部桥接方法、更新列表与重载并发留待后续 |
| 浏览、搜索与详情：`lib/pages/`、`components/comics_list.dart` | 部分 | `MainPageState / SearchResultPage / ComicsPageLogic / ComicPage / JmComicPage`；选择、源页合并与 `EhGalleryPageLoader` | [流程](business-flows.md)、[多选收藏](changes/2026-11-16-multi-select-favorites.md)、[源页合并](changes/2026-11-19-source-page-grouping.md) | 多选已在 Android 真机使用临时数据验证共用入口；分页合并与 EH 链接重试经本机可控响应验证 | 使用真实漫画源验收合并分页；分区/混合主页、Hitomi、专题页未纳入多选 |
| 阅读器：`lib/pages/reader/` | 部分 | `ReadingData / loadInfo / ReadingStatisticsBoundary / observeImage`；在线/离线主分支和阅读统计 | [阅读与下载](modules/reader-download.md) | Android 14 已验证 EH 在线阅读超出磁盘上限后前翻、回翻和重新加载；主机测试验证解码门槛、计时和生命周期/路由暂停；已覆盖更新真机并启动，功能交互待验收 | 其他真实源、长时间运行、双页／连续阅读、锁屏、离线缺图与资源释放待验证 |
| 下载：`lib/network/download.dart`、`download_model.dart`、`custom_download_model.dart` | 已分析 | 队列、任务生命周期、序列化、错误恢复；代表任务 `JmDownloadingItem / CustomDownloadingItem` | [阅读与下载](modules/reader-download.md) | 静态；未运行 | 其他源任务、批量收藏下载、路径迁移和竞态未深读／实测 |
| 历史与本地收藏存储：`lib/foundation/history.dart`、`local_favorites.dart`、`image_favorites.dart` | 已分析 | `init / onReadEnd / ReadingStatistics / FavoriteQuery / ComicsPageView`；统计身份、幂等合并、全夹排序/本地分页 | [数据](data-model.md)、[多选收藏](changes/2026-11-16-multi-select-favorites.md) | 批量写入/失败重试及独立大库导入、历史暂存恢复已在 Android 真机验证；见[导入恢复](changes/2026-11-16-data-import-recovery.md) | 早期 JSON、统计压缩包全通道/中断及其余编辑/搜索 UI 待验证 |
| 网络收藏关联：`lib/network/net_fav_to_local.dart`、`lib/pages/favorites/network_to_local.dart` | 未分析 | 只定位文件；源通用 `FavoriteData` 契约另有阅读 | — | 未运行 | 持续关联、拉取页数、去重与中断恢复 |
| 图片与缓存：`lib/foundation/image_manager.dart`、`cache_manager.dart`、`image_loader/` | 部分 | `getEhImageNew / CacheManager.readCache / _evictBatches / FileImageProvider / ComicDetailCover`，及 JM／自定义图片入口 | [阅读与下载](modules/reader-download.md)、[缓存修复](changes/2026-11-18-disk-cache-capacity.md)、[封面回退](changes/2026-11-19-detail-cover-fallback.md) | Android 14 真实 EH 单页读到第 99 页，验证淘汰、回翻和重新下载；用户真机确认历史封面刷新和感叹号占位 | 真实长列表、其他源与内存压力仍待验证 |
| 网络与会话：`lib/network/app_dio.dart`、`http_client.dart`、`cookie_jar.dart`、`cloudflare.dart`、`http_proxy.dart` | 部分 | `logDio / AppHttpAdapter.fetch / CookieManagerSql / passCloudflare / getProxy` | [接口](api-integrations.md) | 静态；未发站点请求 | 代理转发全实现、TLS 与 Cookie 标准兼容性 |
| JM：`lib/comic_source/built_in/jm.dart`、`lib/network/jm_network/`、`lib/pages/jm/` | 部分 | `searchNew / getComicInfo / getChapter`，详情阅读与下载消费者 | [流程](business-flows.md)、[limit 实测](api-integrations.md#jm-搜索的-limit-参数实测2026-11-16) | 独立脚本已执行匿名搜索 limit 对照；详情、阅读、下载未实测 | 登录态、其他有效域名、评论、签到、全部收藏协议 |
| 其他五源：`built_in/{picacg,ehentai,hitomi,ht_manga,nhentai}.dart`、`lib/network/` 对应目录 | 部分 | 六源注册与专用 builder、网络客户端入口、ReadingData 映射 | [接口定位表](api-integrations.md#内置源定位) | 静态；未运行 | 五源完整协议、账户与全部异常分支 |
| WebDAV／用户数据包：`lib/network/webdav.dart`、`lib/tools/io_tools.dart` | 已分析 | `uploadData / downloadData / importDataFromFile / _exportData`；校验、版本、服务恢复与单库事务边界 | [接口](api-integrations.md)、[数据](data-model.md) | 独立大库/错误重试验证通过；按用户请求完成本机备份恢复和正常界面导入；未连接 WebDAV 服务 | 并发／时钟冲突、整包原子性、可选下载目录导入 |
| 平台工具／更新：`lib/tools/`、`lib/network/update.dart` | 部分 | `handleAppLinks / onStart / getLatestVersion` 与调用者；仅主路径 | [接口](api-integrations.md) | 静态；未运行 | 后台凭据、PDF／图片导出、通知、平台通道 |
| UI 基础设施：`lib/components/`、`lib/foundation/` | 部分 | `StateController / StateBuilder / App`，主导航与控制器消费者 | [架构](architecture.md) | 静态；未运行 | 控件交互、布局、控制器订阅清理与无障碍 |
| 原生工程／打包：各平台目录、`windows/build_windows.py`、`debian/build.py` | 部分 | Android Gradle、Windows runner CMake、两个打包脚本的写入行为 | [开发](development.md) | Android Debug 构建、独立测试包安装及首次启动通过 | 原生通道各功能及其他平台运行、Web 兼容性未确认 |
| CI／测试：`.github/workflows/`、`test/`、`integration_test/` | 已分析 | 工作流配置；多选、阅读统计、收藏、封面、弹窗、源页合并和磁盘缓存的主机回归；多选与大库导入的真机集成 | [开发](development.md)、[源页合并](changes/2026-11-19-source-page-grouping.md#验证) | 60 项主机测试通过，真机集成保留历史验证记录 | 其他业务回归仍不足，未查询 CI 历史 |
| 翻译与辅助资源：`utils/`、`lib/tools/translations.dart`、`assets/` | 部分 | 两个 utils `main` 的写入／下载副作用，资源清单和 JS API | [开发](development.md) | 静态；脚本未运行 | 翻译运行时、标签数据完整性；大型资源见排除项 |

排除项：生成平台插件配置不做内部实现分析；`lib/components/scrollable_list/` 带 Fuchsia／BSD-style 版权声明，除阅读器消费入口外未深读其复制的滚动实现；字体、图标、图片、大型标签／翻译 JSON 不逐字分析。首轮对 Git／Pub 依赖只查清单与锁定引用；后续 Android 环境配置已下载锁定依赖并核对插件原生构建配置，仍未对第三方实现作完整分析。没有自动展开子模块或 LFS 内容。初始目录盘点确认 `lib/` 有 198 个已跟踪 Dart 文件，此数量不作为理解覆盖率。

许可证线索：根 `LICENSE` 为 MIT，包含保留版权和许可声明的要求；上面第三方文件的独立声明仍需在实际二次分发时逐项核对，本轮不作完整许可证审查。

## 快照与继续入口

- 初始分析日期：2026-11-15（Asia/Shanghai）。
- 初始检出来源：`https://github.com/Pacalini/PicaComic`；检出时 `origin` 指向该上游，默认／本地分支为 `master`。后续协作配置见下节。
- 首轮提交基准：`a9c896d73b21495cca41e4acc0e06aca6298f8c5`（该提交日期 2026-05-18）；检出后工作区与暂存区均干净。基准不含本轮新增知识库。
- 检出方式：浅克隆（深度 1），未递归拉取子模块；历史变更频率不在本轮结论范围内。
- 本轮授权：建立首轮知识库，仅写文档和知识库协作规则，不修改业务源码、依赖或锁文件。
- 本轮完成：阶段 A 骨架、B 架构与存储、C 四条代表性流程、D 两个核心模块与开发准备；其余实现盲区保留在上表。已有上游说明未改，未创建或推断 Accepted ADR。
- 环境进度（2026-11-16）：已按授权在 E 盘配置 Android 真机工具链，`flutter doctor -v` 全部通过；更换为 Android 14 的 PHZ110 后，独立 Debug 测试包已构建、安装并启动至首次设置界面，保留手机原版应用及数据。详情见[本机 Android 环境](development.md#本机-android-真机环境2026-11-16)。首轮分析记录中的“未安装／未运行”保留其历史时点含义。
- 后续优先项：在已配置的 Android 环境核对[技术债 KB-03／KB-04](technical-debt.md) 的无章节源及在线／下载图片差异；随后按具体需求补全网络收藏关联、剩余源协议或目标平台。跨源身份改动另需明确迁移与兼容范围。
- 当前继续入口（2026-11-18）：[阅读统计与收藏分页排序](changes/2026-11-17-reading-statistics-favorites.md)及[显示修复](changes/2026-11-18-favorites-display-fixes.md)交付至个人仓库 `dev`。此前已覆盖更新真机并确认启动，具体功能仍待验收。连续加载失败和去重只交付[方案文档](changes/2026-11-17-continuous-loading-plan.md)，实施暂缓。
- 缓存修复（2026-11-18）：[原问题、原因与验证](changes/2026-11-18-disk-cache-capacity.md)记录旧清理死循环、容量回归和 EH 真机在线阅读结果。测试后已恢复真机的原设置与缓存。
- 真机交付（2026-11-19）：[收藏顺序](changes/2026-11-19-favorite-order-recovery.md)、[封面与历史预览](changes/2026-11-19-detail-cover-fallback.md)及[弹窗溢出](changes/2026-11-18-dialog-overflow.md)一并交付至个人仓库 `dev`。用户确认收藏顺序、历史封面更新和感叹号占位正常。
- 真机交付（2026-11-19）：[远程分页合并源页](changes/2026-11-19-source-page-grouping.md)通过 60 项主机测试，已覆盖安装并启动，真实漫画源交互待用户验收。
- 最近巡检：无；本轮为首轮分析。

## 协作仓库与分支

- 配置日期：2026-11-15（Asia/Shanghai），依据用户明确要求创建 Fork、提交并推送知识库到本人仓库的 `dev` 分支，不创建 PR。
- 个人 Fork：[Aikawakanami/PicaComic](https://github.com/Aikawakanami/PicaComic)，父仓库为 `Pacalini/PicaComic`；本地 `origin` 指向该 Fork，`upstream` 指向原仓库。
- 知识库交付分支为 `dev`，从上面的首轮源码基准创建，推送目标为 `origin/dev`；本地 `master` 保留原基准并跟踪 `upstream/master`。
- 首轮提交范围为根 `AGENTS.md` 和本索引导航的 9 份新增知识库文档；该历史时点未改业务源码、依赖、锁文件和上游已有文档。后续功能变更另在上表及变更记录维护，`master` 仍保留首轮上游基线。
- 2026-11-16 用户确认当前测试版通过并授权提交全部功能及知识库到 `origin/dev`，本次交付目标包含 33 个源码/资源/测试/文档及依赖清单文件；不包含个人备份、APK、本机工具配置或签名密钥，不创建 PR。

## 交付检查

以下保留首轮分析完成时、Git 提交前的验证记录；Fork 与分支配置在上节维护。

- 【已验证：执行证据】Python 标准库检查了本轮 10 个新增 Markdown 文件：70 个相对链接（含章节锚点）、93 个不同的源码路径均可定位，190 项“路径＋关键符号”的存在性检查无缺失；没有模板占位、空文件、未闭合代码围栏、行尾空白或缺失末尾换行。
- 【已验证：执行证据】`git diff --check`、工作区及暂存区 `git diff --exit-code` 均通过。未跟踪文件恰为本轮 9 份知识库文档及根 `AGENTS.md`；业务源码、依赖、锁文件和已有上游文档没有修改，无额外临时脚本落库。
- 关键行为还经过对应实现、调用者和相关契约的定向静态核对；上述路径／符号检查只检查可定位性，不替代运行证据。
- Flutter 分析、测试、应用和构建均未运行，原因是当前 PATH 不可发现 Flutter／Dart；没有安装依赖、连接漫画源或 WebDAV 账户、执行应用数据迁移或触发远程工作流。
