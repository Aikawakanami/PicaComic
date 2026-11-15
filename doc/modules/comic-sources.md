# 漫画源注册与 JS 扩展

- 范围：`lib/comic_source/`、`lib/foundation/js_engine.dart`、`assets/init.js`，以及设置、搜索、详情和图片消费者。宏观依赖见[架构](../architecture.md)。
- 分析状态：已分析注册、安装、搜索／详情／章节适配与桥接主路径；各内置协议、全部 JS API 分支和源更新行为仍为部分覆盖。
- 证据类型：以下均为【已实现：静态依据】，未执行任何外部脚本或站点调用。

## 实现与依据

| 规则 | 当前源码锚点 |
| --- | --- |
| 六个内置源按启用位加入 registry，并读取状态；自定义源来自应用数据目录的 `.js` 文件 | `lib/comic_source/comic_source.dart → ComicSource.builtIn / init`；`lib/base.dart → _Settings.isComicSourceEnabled / settings[82]` |
| `find` 使用字符串 key；`fromIntKey` 和 `intKey` 使用 `key.hashCode`；禁用源可能不在 registry 中 | `lib/comic_source/comic_source.dart → find / fromIntKey / intKey` |
| 源能力可选，含搜索、分类、探索、收藏、评论、详情、章节和图片配置；内置源可覆盖列表块、搜索页或详情页 | `ComicSource`、`SearchPageData`、`FavoriteData`；`lib/comic_source/built_in/` 各源配置 |
| 安装解析检查首个非空行、name／key／version、minAppVersion、重复 key 和字母数字下划线字符集 | `lib/comic_source/parser.dart → ComicSourceParser.parse / _checkKeyValidation` |
| 解析前创建文件，失败删除本次文件；成功后由设置页加入 Dart registry | `ComicSourceParser.createAndParse`；`lib/pages/settings/comic_source_settings.dart → addSource` |
| 桥接初始化加载 `assets/init.js`，将 Dart `_messageReceiver` 注册为 JS `sendMessage` | `lib/foundation/js_engine.dart → JsEngine.init / _messageReceiver` |
| 源数据保存为 JSON；JS loadData／saveData／deleteData 转发给源 `data` 和持久化方法 | `assets/init.js → ComicSource`；`JsEngine._messageReceiver`；`ComicSource.saveData` |

## Dart 与 JS 契约对应

| Dart 消费者 | JS 方法／结果 | 适配器 |
| --- | --- | --- |
| `SearchPageData.loadPage(keyword, page, options)` | `search.load(keyword, options, page)`，结果含 `comics`、`maxPage`；注意参数顺序不同 | `ComicSourceParser._loadSearchData` |
| `loadComicInfo(id)` | `comic.loadInfo(id)`，含 title、cover、可空 chapters／tags 等；chapters 为 ID→名称 | `ComicSourceParser._parseLoadComicFunc` |
| `loadComicPages(id, ep)` | `comic.loadEp(id, ep)`，结果含 `images` | `ComicSourceParser._parseLoadComicPagesFunc` |
| `getImageLoadingConfig(imageKey, comicId, epId)` | `comic.onImageLoad(...)`，可返回 URL、headers、method、data、onResponse | `ComicSourceParser._parseImageLoadingConfigFunc`；`lib/foundation/image_manager.dart → getCustomImage` |
| 账户登录 | `account.login(account, pwd)` 完成后，Dart 将账户列表写入 `source.data['account']` | `ComicSourceParser._loadAccountConfig` |
| 网络 | `Network.sendRequest / fetchBytes` 经 `sendMessage` 调 Dart HTTP，返回 status、headers、body、error；API 全量定义见上游文件 | `assets/init.js → Network`；`JsEngine._http` |

原始指南见 [comic_source.md](../comic_source.md)，完整 JS API 见 [assets/init.js](../../assets/init.js)。解析器没有统一的独立 Schema 校验层；未提供的能力以及不正确的返回字段会在不同适配／消费点暴露，不能把安装成功当作所有功能兼容。

## 状态、错误与信任边界

- `ComicSource.isLogin` 只判断本地 account 字段存在。`reLogin` 假设账户是含用户名／密码的 List；不同内置源可能只用标记，调用方必须尊重 `AccountConfig.allowReLogin` 等能力。
- JS 收藏与发评论的部分适配器在错误文本包含 `Login expired` 时重登一次。详情、章节等适配器通常只返回 `Res.error`，本页不承诺统一重登。
- 启动读取某个 JS 文件失败时，`ComicSource.init` 记录日志继续其他文件；整体 JS 引擎初始化异常也会被内部捕获。启动就绪风险见[技术债](../technical-debt.md)。
- 外部 JS 在解析时执行，桥接可使用 HTTP、Cookie、HTML、转换和源数据 API。`key`／版本检查是兼容性检查，不是已经证明的安全隔离。本轮没有审计所有桥接能力或运行第三方脚本。
- `ComicSource.reload` 清空 Dart registry 与 JS `ComicSource.sources` 后重新加载。它不等于销毁重建整个引擎；`JsEngine.reset` 是另一条路径，其完整生命周期未验证。

## 后续修改入口

【建议】增加源能力时同时核对四处：`assets/init.js` 的外部契约、`parser.dart` 的类型／异常适配、`ComicSource` 的 Dart 字段、页面与图片／下载消费者；不要只新增 JS 方法。内置源修复优先进入对应 `built_in/`、`network/*_network/` 和专用详情页，而不是假设它们使用通用详情。

【建议】涉及源 key 或类型编码时核对[数据模型](../data-model.md)，涉及图片 hook 时比对在线 `ImageManager.getCustomImage` 与下载 `CustomDownloadingItem._getImage`；后者当前只使用 URL／headers，并非同一处理路径。

## 验证与未知项

测试入口只有空的 `test/widget_test.dart`；PATH 无 Flutter／Dart，因此未运行解析器、桥接或 UI 测试。尚未覆盖源更新列表、全部账号／评论／分类契约、重载中并发请求、无章节自定义源和不同平台 JS 资源释放。跨模块代表性流程见[业务流程](../business-flows.md#2-安装自定义源--通用详情与图片)。
