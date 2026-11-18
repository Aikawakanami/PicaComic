# 接口与外部集成

[返回知识库](README.md)。本项目主要消费外部服务；本页记录客户端契约和边界，不代表全部站点当前可访问。除单独标注的执行记录外，结论均为【已实现：静态依据】。

## 漫画源能力契约

`lib/comic_source/comic_source.dart → ComicSource` 是页面发现能力的入口。搜索为 `SearchPageData.loadPage(keyword, page, searchOption)`，返回 `Res<List<BaseComic>>`；详情为 `loadComicInfo(id)`，章节为 `loadComicPages(id, ep)`；收藏为 `FavoriteData`；图片请求可通过 `getImageLoadingConfig` 调整。这些能力允许为空，并不保证每个源都走通用详情回调；六个内置源均配置专用 `comicPageBuilder`。

`lib/network/res.dart → Res<T>` 以 `errorMessage != null` 判断错误，访问空 `data` 会抛异常；`Res(false)` 本身不等于错误。`subData` 是动态附加值，列表分页约定主要为最大页数，不能跨接口假定它总是同一种类型。依据：`ComicListBuilder`、`CategoryComicsData.load`、`FavoriteData.loadFolders`。

自定义源现有指南见[comic_source.md](comic_source.md)，实际 API 见 [assets/init.js](../assets/init.js)；本知识库不再复制整份 API。Dart／JS 参数差异和安装约束见[漫画源模块](modules/comic-sources.md)。

## 公共网络栈

| 能力 | 契约与边界 | 源码锚点 |
| --- | --- | --- |
| Dio 工厂与重试 | `logDio` 添加日志拦截器并使用 `AppHttpAdapter`；请求超时主要由拦截器设为 15 秒；适配器失败最多尝试 2 次，遇到带 4xx 响应的 DioException 不重试。各源／下载还可能有自己的重试 | `lib/network/app_dio.dart → logDio / MyLogInterceptor.onRequest / AppHttpAdapter.fetch` |
| GET 缓存 | `CachedNetwork.get` 按 URL 查缓存，可选 CookieJar；命中返回合成状态 200，不能当作本轮服务器响应或原响应头 | `lib/network/cache_network.dart → CachedNetwork.get / CachedNetworkRes` |
| Cookie | `CookieManagerSql` 自动填充 Cookie 请求头并保存 Set-Cookie；数据库主键及 JM 内存 Cookie 的例外见[数据模型](data-model.md) | `lib/network/cookie_jar.dart → CookieManagerSql / CookieJarSql` |
| Cloudflare | 状态 403 且 `cf-mitigated: challenge` 转为 `CloudflareException`；`passCloudflare` 通过桌面／移动 WebView 保存 Cookie 和 UA，再回调重试 | `lib/network/cloudflare.dart → CloudflareInterceptor / passCloudflare` |
| 代理与 hosts | `settings[8]` 为代理选择，`settings[58]` 启用 hosts；本地 TCP 代理绑定 loopback，使用 `rule.json → port / rule / sni`；原说明见 [hosts.md](hosts.md)，当前默认还含 `s.exhentai.org` | `lib/network/http_client.dart → getProxy / setNetworkProxy`；`http_proxy.dart → HttpProxyServer` |
| TLS 例外 | `ProxyHttpOverrides.createHttpClient` 的 badCertificateCallback 对含 `cdn` 的 host 及 IPv4 地址放行。不能把 hosts 功能描述为保留所有证书校验；这里仅记录实现，未验证实际连接 | `lib/network/http_client.dart → ProxyHttpOverrides.createHttpClient`；`app_dio.dart → changeHost` |

【推测／待核实】各客户端并不必然装有相同拦截器。`JsEngine.init` 配置 CloudflareInterceptor，但不能据此推断每个内置源都自动弹 WebView；缓存 key 是否需要包含账户／请求头也尚未验证。

## 内置源定位

本轮深读 JM 的代表性搜索、详情、章节及图片调用；其余源仅核对注册、客户端入口和部分调用者，协议完整性仍为部分覆盖。

| 源 | 适配／协议入口 | 本轮确认的边界 |
| --- | --- | --- |
| picacg | `lib/comic_source/built_in/picacg.dart → picacg`；`lib/network/picacg_network/methods.dart → PicacgNetwork` | 搜索／详情／阅读走内置模型和页面；请求构造另依赖 `headers.dart`，本轮不复制协议常量或认证值 |
| EH／EX | `lib/comic_source/built_in/ehentai.dart → ehentai`；`lib/network/eh_network/eh_main_network.dart → EhNetwork` | 专用 gallery 页面与图片加载；站点选择及账户 Cookie 需独立核对 |
| JM | `lib/comic_source/built_in/jm.dart → jm`；`lib/network/jm_network/jm_network.dart → JmNetwork.searchNew / getComicInfo / getChapter` | `/search`、`/album`、`/chapter`；API 域名列表来自 `_Settings.jmApiDomains`，索引为 `settings[17]`；图片加载另有重组 |
| Hitomi | `lib/comic_source/built_in/hitomi.dart → hitomi`；`lib/network/hitomi_network/hitomi_main_network.dart → HiNetwork` | 自定义搜索／详情、文件 hash 与专用图片获取；未深读索引格式和 CDN 算法 |
| HT | `lib/comic_source/built_in/ht_manga.dart → htManga`；`lib/network/htmanga_network/htmanga_main_network.dart → HtmangaNetwork` | 域名来自 `settings[31]`，独立 HTML／账户及图片处理 |
| NHentai | `lib/comic_source/built_in/nhentai.dart → nhentai`；`lib/network/nhentai_network/nhentai_main_network.dart → NhentaiNetwork` | 独立 session Cookie、`search / getComicInfo / getImages`；不能把废弃 `settings[48]` 当作当前域名配置 |

## JM 搜索的 limit 参数实测（2026-11-16）

【已实现：静态依据】`lib/network/jm_network/jm_network.dart → JmNetwork.searchNew` 请求 `/search?&search_query=...&o=...`，第一页省略 `page`，后续页增加 `page`；现有代码未传 `limit`。域名更新遵循 `getApiDomains / tryFetchAndDecrypt`，请求头及响应解密分别依据 `headers.dart → getApiOptions` 和 `JmNetwork.convertData`。

【已验证：执行证据】用独立临时脚本执行真实 HTTP 对照请求，没有登录或使用个人 Cookie、应用缓存；按项目现有公开域名更新流程获得测试地址 `https://www.cdnbtd.cc/search`。保持 TLS 校验，复用电脑现有 HTTP 代理；压缩声明使用 gzip／deflate／br，省略 zstd。测试关键词为“漫画”，排序 `mr`，请求版本为源码默认的 2.0.11；响应解密后 `total=2866`，所有下列请求均为 HTTP 200：

| 页码 | limit 参数 | content 条数 | 与同页不传 limit 的结果比较 |
| --- | --- | --- | --- |
| 1（省略 page） | 不传 | 80 | 基准 |
| 1（省略 page） | 分别为 1、5、10、50、100 | 均为 80 | 漫画 ID 及顺序全部一致 |
| 2 | 不传 | 80 | 基准；与第一页的 ID 无交集 |
| 2 | 5 | 80 | 漫画 ID 及顺序与第二页基准一致 |

【已验证：执行证据】因此，在上述域名、匿名请求和版本条件下，`limit` 未改变每页数量或结果内容，不能用它控制每页返回条数；`page` 确实改变结果。辅助关键词 `test` 的总结果只有 48 条，超出末页仍重复返回，故未将它作为分页正向控制；关键词 `a` 返回空结果，也未用于判断每页数量。源码旧默认域名返回 HTML／404，未当作 API 搜索成功。

本机证据：`E:\Program Files\AndroidDev\logs\jm-limit-results.md`、`jm-limit-comparison.json` 和三份 `jm-limit-probe*.json`；临时脚本在同一安装根目录的 `setup/jm-limit-probe*.ps1`。摘要仅保留数量、ID 和请求元数据，不保存漫画正文、图片或个人凭据。业务源码和依赖未改。本次未测试登录态、其他有效域名或其他分页参数，也未验证应用内阅读、下载等功能。

## WebDAV 与数据包

`lib/network/webdav.dart → Webdav` 使用 `settings[45]` 的四段配置：服务 URL、用户名、密码、远程目录，以分号拼接；默认空值表示不启用。版本保存在 `settings[46]`，上传时设置为 Unix 秒时间戳，不是业务 Schema 版本。

- `uploadData` 通过 `_isOperating / _haveWaitingTask` 合并部分并发请求，调用 `exportDataToFile(false, ...)`，上传 `<timestamp>.picadata`。远程目录中发现同一天的数字版本文件会移除一份，不能把它描述为完整保留策略。
- `downloadData` 列目录取最大数字版本；版本字符串相同且未强制时跳过下载，其他情况交给 `importData`。`syncData` 用 `_retryZone` 最多尝试 3 次，失败后在配置尾部加 `;0`，当前会话借此禁用自动同步并提供重试动作。
- `.picadata` 是由 `ZipFile` 打包的文件集合。`lib/tools/io_tools.dart → _exportData / exportDataToFile` 默认包括 appdata、收藏库、历史库、cookies.db 以及 `comic_source` 内所有普通文件；可选包含下载目录。WebDAV 传入 `false`，所以自动同步不带下载漫画图片。
- 当前打包路径没有显式加密步骤；appdata 内的 `settings[45]` 及源 `.data`／Cookie 文件可能携带认证信息。不得把“未同步下载图片”误写为“不包含账户数据”。这是包内容的静态边界；后续仅按用户明确请求在本机备份和恢复个人数据，记录见[导入恢复](changes/2026-11-16-data-import-recovery.md)，原始备份未入库。
- `importData / importDataFromFile` 显式路径默认启用版本判断，旧／相同 WebDAV 版本现在整包跳过，不再继续覆盖设置；手工选择文件绕过该版本限制。先解包校验，SQLite 数据在后台事务合并，错误统一返回失败并尝试恢复服务。合并规则见[数据模型](data-model.md)，修复与验证边界见[导入恢复](changes/2026-11-16-data-import-recovery.md)。

【推测／待核实】本地夹具已验证旧版本跳过及失败后重试；多设备时钟偏差、同时写入、远端失败重试和整包导入中断一致性尚未实测，未配置或访问任何 WebDAV 账户。

## 其他外部边界

- 更新：`lib/network/update.dart → getLatestVersion / getDownloadUrl` 使用本项目 GitHub Releases API 与 latest 页面；`lib/pages/main_page.dart → _checkUpdates` 受 `settings[2]` 和上次检查时间限制。本轮未把公开仓库元数据读取当成应用更新功能测试。
- 链接／剪贴板：`lib/tools/app_links.dart → canHandle / handleAppLinks` 识别 EH／EX、NHentai、Hitomi host；`lib/main.dart → didChangeAppLifecycleState` 与 `MainPage` 受 `settings[61]` 控制剪贴板检查。JM／哔咔不在该 host 列表内。
- 后台：`lib/tools/background_service.dart → onStart / runBackgroundService` 注册移动端哔咔签到；权限通知、系统调度与会话恢复尚未验证。
- Git 依赖：`pubspec.yaml → photo_view / webdav_client / zip_flutter / flutter_qjs / desktop_webview_window / flutter_inappwebview / flutter_to_arch` 来自 Git 仓库，具体解析提交由 `pubspec.lock → resolved-ref` 记录。后续 Android 环境已按锁文件下载依赖并完成原生 Debug 构建，Git 依赖实现仍未逐项全面审阅。

## 阅读统计备份扩展（2026-11-17）

【已实现：静态依据】`lib/tools/io_tools.dart → _exportData` 在后台通过独立连接和 VACUUM INTO 导出 reading_stats.db 一致性快照，不依赖工作线程中的 App 静态路径。`_extractImport` 校验可选统计库版本/列及 quick_check，`_installImportFiles` 暂存为 reading_stats_temp.db，`ReadingStatistics.mergePending` 在后台单库事务合并，成功后才删暂存文件。旧包缺少统计库正常兼容；统计同会话按累计检查点 max 合并、不同会话汇总，不简单重复相加。文件夹 JSON 的 reading_statistics 只导出对应漫画身份。

普通历史清理不删除统计，应用全部数据清理包含统计；无删除墓碑，旧备份会恢复旧会话。现有收藏/历史导入的固定列和冲突策略未统一改写，也不提供跨库/文件整包事务。统计核心快照/合并已用临时库验证，压缩包/WebDAV/文件夹全通道仍待真机测试；详情见[实施记录](changes/2026-11-17-reading-statistics-favorites.md)。
