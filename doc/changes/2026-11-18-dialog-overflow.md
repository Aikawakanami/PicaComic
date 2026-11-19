# 长标题与小屏弹窗溢出修复

## 问题与原因

长按漫画后，长标题占据弹窗的大部分空间，底部操作被截断。Flutter 调试界面会显示黄黑警示条和 `BOTTOM OVERFLOWED`。`lib/components/comic_tile.dart → ComicTile._showLongTapMenu` 原先用同一个 `Column` 堆放可选标题、菜单项和源附加操作。弹窗限制了宽度和可用高度，内容没有垂直滚动。屏幕较短、系统字体放大或键盘弹出时，其他页面的同类布局也可能超出可用高度。

## 修改范围

| 入口 | 处理方式 |
| --- | --- |
| 通用漫画长按菜单和屏蔽选项，`lib/components/comic_tile.dart → _showLongTapMenu / _BlockingPaneState.build` | 将标题、标签和操作放入有高度约束的滚动区域，保留完整可选标题。搜索、分类、排行等使用通用漫画卡片的入口共用此修复。 |
| 搜索选项、切换源、剪贴板链接、本地收藏更新提示和设置表单，`lib/components/message.dart → ContentDialog.build` | 内容可垂直滚动，操作按钮在窄屏上允许换行。 |
| 长消息、确认与更新说明，`message.dart → showDialogMessage / showConfirmDialog`、`lib/pages/main_page.dart`、`lib/pages/settings/app_settings.dart` | 标题与正文可滚动，关闭和确认按钮位于正文滚动区域外。 |
| 已下载漫画详情，`lib/pages/download_page.dart → _DownloadedComicInfoViewState.build` | 漫画标题与章节网格一起滚动，底部查看详情和阅读按钮仍然可用。 |
| EH 下载归档选项，`lib/pages/ehentai/eh_gallery_page.dart` | 普通下载和归档选项可一起滚动，展开归档后可以滚动到确认。 |
| 工具面板，`lib/pages/tools.dart → openTool` | 底部面板采用滚动列表，保留底部安全区。 |

本地收藏长按菜单 `lib/pages/favorites/local_favorites.dart → LocalFavoriteTile.showMenu` 已有纵向滚动结构。通用漫画列表的展示模式和各操作的回调沿用原有规则。

## 验证

【已验证：执行证据】在改动前使用中性长标题、窄屏和放大字体，复现了通用长按菜单、屏蔽选项、共享设置弹窗、已下载漫画详情和工具面板的 `RenderFlex` 底部溢出。共享设置场景模拟了键盘占用屏幕空间。

【已验证：执行证据】`flutter test --no-pub test/dialog_overflow_test.dart` 的 6 项专项测试通过，覆盖最后一个菜单项可点击、屏蔽输入与提交可见、键盘占用空间时设置仍可保存、长下载标题后能看到章节且底部按钮可用、工具列表最后一项可打开、长消息可确认关闭。全套主机回归共 48 项通过。

弹窗修复已随[封面和收藏修复测试版](2026-11-19-detail-cover-fallback.md#验证)覆盖安装到真机。EH 在线归档仍待单独验证。

## 阅读器底栏横向溢出（2026-11-19）

【已实现：静态依据】上轮检查集中在长标题和弹窗内容向下超出可用高度，漏查 `lib/pages/reader/tool_bar.dart → ToolBar.buildBottomToolBar`。阅读器的章节页码、方向、图片收藏、自动翻页、章节、保存和分享等控件原先放在固定单行，宽度不足时右侧按钮被裁切。底栏现使用可自动换行的 `Wrap`，高度随行数增长，并由 `SafeArea` 留出底部导航栏和两侧安全区。

【已验证：执行证据】6215 测试包构建并覆盖安装到真机。安装前已备份数据，安装后核对收藏、历史、阅读统计和设置的文件哈希。按用户要求未运行自动化测试。

【已验证：用户反馈】用户在 6216 真机测试版确认本轮修改通过，底栏修复随逐章进度和收藏角标提交到 `dev`。
