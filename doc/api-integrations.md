# 接口与外部集成

[返回知识库](README.md)。本项目主要消费外部服务；本页记录客户端契约和边界，不代表任何站点当前可访问。除明确列出的文档检查外，结论均为【已实现：静态依据】。

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

## WebDAV 与数据包

`lib/network/webdav.dart → Webdav` 使用 `settings[45]` 的四段配置：服务 URL、用户名、密码、远程目录，以分号拼接；默认空值表示不启用。版本保存在 `settings[46]`，上传时设置为 Unix 秒时间戳，不是业务 Schema 版本。

- `uploadData` 通过 `_isOperating / _haveWaitingTask` 合并部分并发请求，调用 `exportDataToFile(false, ...)`，上传 `<timestamp>.picadata`。远程目录中发现同一天的数字版本文件会移除一份，不能把它描述为完整保留策略。
- `downloadData` 列目录取最大数字版本；版本字符串相同且未强制时跳过下载，其他情况交给 `importData`。`syncData` 用 `_retryZone` 最多尝试 3 次，失败后在配置尾部加 `;0`，当前会话借此禁用自动同步并提供重试动作。
- `.picadata` 是由 `ZipFile` 打包的文件集合。`lib/tools/io_tools.dart → _exportData / exportDataToFile` 默认包括 appdata、收藏库、历史库、cookies.db 以及 `comic_source` 内所有普通文件；可选包含下载目录。WebDAV 传入 `false`，所以自动同步不带下载漫画图片。
- 当前打包路径没有显式加密步骤；appdata 内的 `settings[45]` 及源 `.data`／Cookie 文件可能携带认证信息。不得把“未同步下载图片”误写为“不包含账户数据”。这是静态包内容边界，没有读取或生成真实备份。
- `importData` 显式传路径时启用版本判断；对旧／相同版本可跳过部分文件替换，但后续仍执行 `Appdata.readDataFromJson` 和 manager 读取。不是严格的“旧版本整包不导入”，也不是逐字段冲突解决。合并规则见[数据模型](data-model.md)。

【推测／待核实】多设备时钟偏差、同时写入、失败重试、同版本包处理和导入中断一致性尚未实测；未配置或访问任何 WebDAV 账户。

## 其他外部边界

- 更新：`lib/network/update.dart → getLatestVersion / getDownloadUrl` 使用本项目 GitHub Releases API 与 latest 页面；`lib/pages/main_page.dart → _checkUpdates` 受 `settings[2]` 和上次检查时间限制。本轮未把公开仓库元数据读取当成应用更新功能测试。
- 链接／剪贴板：`lib/tools/app_links.dart → canHandle / handleAppLinks` 识别 EH／EX、NHentai、Hitomi host；`lib/main.dart → didChangeAppLifecycleState` 与 `MainPage` 受 `settings[61]` 控制剪贴板检查。JM／哔咔不在该 host 列表内。
- 后台：`lib/tools/background_service.dart → onStart / runBackgroundService` 注册移动端哔咔签到；权限通知、系统调度与会话恢复尚未验证。
- Git 依赖：`pubspec.yaml → photo_view / webdav_client / zip_flutter / flutter_qjs / desktop_webview_window / flutter_inappwebview / flutter_to_arch` 来自 Git 仓库，具体解析提交由 `pubspec.lock → resolved-ref` 记录。下载依赖和原生构建尚未执行。
