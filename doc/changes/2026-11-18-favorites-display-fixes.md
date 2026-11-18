# 本地收藏显示、排序与分页间距修复

- 日期：2026-11-18，用户反馈后的增量修复。
- 前置功能：[阅读统计/收藏分页排序](2026-11-17-reading-statistics-favorites.md)。
- 状态：增量修复当时的 37 项主机回归通过，Android 正常入口构建成功并覆盖更新真机。源码与阅读统计及本地收藏分页一并交付到个人仓库 `dev`，具体真机交互待用户验收。

## 用户反馈与修复

【已实现：静态依据】移除收藏列表上的图片下限说明文字；排序菜单只显示最后阅读时间、次数、时长、图片数量。无指标选中时显示“排序”并采用原 display_order 手动顺序，再次点击已选指标取消排序；手动顺序没有独立菜单项/升降序按钮。分页栏不再额外预留底部安全区，由外层导航统一预留，避免重复空白。

本地收藏卡片未读时，如已知完整总数则显示 `233`；已知部分显示 `233+`，无数量则不制造数字。已读保留原当前章节进度徽标，如 `1/233`。仅有详情产生的 page=0 不再被本地收藏卡片改成 page=1。徽标和菜单中的数量采用与排序一致的有效数量；进度分母仍是当前章节长度，不能据此解释为多章节漫画的整本总数。

## 排序差异的原因和数据规则

【已验证：执行证据】本机只读诊断重现：旧 history.max_page 已有较大章节页数，而新增 image_books 尚无对应记录，之前的排序将其放入未知区；已有新统计的小数值因此排在其前。新统计的 known_count 为 INTEGER，问题来自数据来源脱节，不是字符串字典序。诊断副本只留在被忽略的 build 目录，不记录个人标题、身份或账户。

【已实现：静态依据】`lib/foundation/reading_image_count.dart` 统一旧历史的来源类型和 Hitomi 身份映射、数量组合与 SQL 数值表达式。`FavoriteQuery` 只读关联 history.db，`ReadingStatistics.metrics` 对菜单等非分页路径使用同样规则：

- 新数据已确认完整总数时优先采用；不被旧章节进度覆盖。
- 不完整/缺失时，与同来源旧 max_page 取已知下限的最大值，不能把两个可能重叠的章节数量相加。
- Pc/JM/自定义源的旧章节数量作为下限；已知单章内置源 EH/Hitomi/HT/NH 可直接作为完整数量。
- 按数值升降序，未知始终末尾；NH 收藏 6 对应历史 5，Hitomi 收藏链接对应历史数值 ID，防止同 ID 不同源串入。

回退只读 history.db，不增加会话计次/时长、不改 Schema，不发网络补全请求；全量备份包含原历史库。文件夹 JSON 仍仅携带已存的独立统计，不因只读回退额外导出旧历史进度。快照仍保持本次浏览顺序，刷新或切换排序才重排。

## 源码与验证

关键入口：`lib/pages/favorites/favorite_view_controls.dart → FavoriteViewControls / FavoritePager`、`main_favorites_page.dart → _ComicsPageViewState.build`、`lib/components/comic_tile.dart → _buildCard`、`LocalFavoriteTile.historyComicID / matchesReadingHistory / unreadImageCountLabel`、`FavoriteQuery.snapshot / read`、`ReadingStatistics.metrics`。

【已验证：执行证据】37 项主机测试通过，新增用例覆盖 233 页旧记录排在 28 页之前、TEXT 旧值按数值排序、完整新数据优先、部分数量取 max、同源限制及 NH/Hitomi 映射、未读 233 和已读 1/233 并存、取消指标恢复手动顺序、重复底部安全区。定向分析无 error/warning，保留原有弃用 API 等 info；未运行设备集成测试。

测试入口：`test/reading_image_count_test.dart`、`favorite_controls_test.dart`、`local_favorites_paging_test.dart`；其余阅读统计与多选用例一并回归。

【已验证：执行证据】Android arm64 正常入口 APK 构建通过；更新前保存实际已安装 APK 和完整私有数据至本机被忽略的 `build/codex-reading-stats/device-backup-view-fix-2026-11-18/`。核对隔离包名后 install -r 返回 Success，启动 Status: ok，MainActivity 位于前台；收藏/历史库哈希与事前备份一致。保留产物 `build/app/outputs/multiselect/PicaComic-favorites-display-fix-debug.apk`。未运行会清数据的设备集成测试，未连接漫画源验证真实页数或修改个人收藏。
