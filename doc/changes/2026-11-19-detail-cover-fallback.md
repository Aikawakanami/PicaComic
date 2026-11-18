# 详情页封面回退与收藏封面修复

## 原因与范围

Picacg 收藏条目保存的部分封面地址失效。用户验证手动「更新漫画信息」后，收藏列表和详情的封面均恢复显示。`lib/pages/picacg/comic_page.dart` 原来只使用进入详情时传入的地址，未采用详情接口提供的 `thumbUrl`。其他内置源和自定义源也有不同的入口与详情地址选取规则。

## 实现

- 【已实现：静态依据】`lib/pages/comic_page.dart → BaseComicPage.buildCover` 和 `lib/components/comic_detail_cover.dart → ComicDetailCover` 分开接受列表地址和详情地址。列表封面优先，等待图片加载结束，失败后只尝试一个不同的详情封面。入口缺少地址时直接用详情地址。最终失败显示主题底色与居中的圆形感叹号，点击实际成功的封面可按相同加载器打开大图。
- 【已实现：静态依据】`lib/foundation/image_manager.dart → getComicCover / comicCoverCacheKey` 支持复用本地收藏封面文件和内置源的列表图片缓存，保留 EH、JM、Hitomi 的请求头以及自定义源的缩略图请求配置。
- 【已实现：静态依据】新封面成功解码并显示后，`lib/foundation/local_favorites.dart → updateCover` 用 `(target,type)` 定位旧地址匹配或地址为空的本地收藏项，仅写 `cover_path`，避免覆盖等待期间已更新的地址。`ComicsPageView` 用封面修订号刷新当前页，位置快照不重建。收藏卡片的内存封面文件缓存按来源、ID 和封面地址区分。
- 【已实现：静态依据】历史记录有独立的 `history.cover`，收藏封面恢复后还需要更新历史。详情接口的封面显示成功时也调用 `lib/foundation/history.dart → HistoryManager.updateCover`。入口地址与详情地址一致且成功显示也适用，覆盖已手动更新收藏封面后的场景。仅匹配历史记录的 `target`、`HistoryType` 与原封面地址，更新 `cover` 并通知历史页和「我的」历史预览，无新增历史或进度变更。历史封面与详情共用 `StreamImageProvider.comicCover` 的请求与缓存规则。

## 验证

定向入口为 `test/comic_detail_cover_test.dart`、`test/local_favorites_paging_test.dart` 和 `test/dialog_overflow_test.dart`。检查入口成功、入口失败后备用成功、相同地址、一律失败、从无入口封面进入、收藏列表刷新和长标题溢出。正常入口真机测试包合入[弹窗溢出修复](2026-11-18-dialog-overflow.md)及[旧收藏顺序恢复相关代码](2026-11-19-favorite-order-recovery.md)。

【已验证：执行证据】全套 55 项主机测试通过，Android arm64 Debug 正常入口构建成功。安装前备份现有测试版，核验包名及签名后覆盖更新。启动检查通过，收藏库、收藏顺序、阅读记录及阅读统计核对一致。真实漫画源的具体失效封面及真机长按交互由用户验收。

【已验证：执行证据】补充历史修复与感叹号占位后，全套 57 项主机测试通过。新增用例核对相同入口和详情地址只加载一次、成功显示仍可修复旧记录、失败有感叹号，以及历史写入保持来源、章节、页码、阅读时间和已读章节。Android 正常入口构建、覆盖安装和启动检查通过。

【已验证：用户反馈】2026-11-19，用户在真机确认历史记录封面能更新，圆形感叹号占位显示正常，并授权与收藏顺序、弹窗溢出修复一同交付到个人仓库 `dev`。
