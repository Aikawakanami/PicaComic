# EH 每日奖励与自动签到方案

研究日期 2026-11-21。记录 Picacg、禁漫天堂和 EH 的源码分析、EH 站点文档、Android 后台模拟验证及前台领取首版实施。

【已确认方向】先推进用户打开 Pica 时的前台自动领取。无人值守调度、临时启动 Clash 和内置 Mihomo 暂缓，保留真机证据和重启研究时的验证顺序。

## 项目现状

### Picacg 自动打卡

- 【已实现：静态依据】`lib/pages/settings/picacg_settings.dart → _PicacgSettingsState` 用 `lib/base.dart → Appdata.settings[6]` 保存「自动打卡」，默认开启。移动端切换开关会注册或取消后台任务，桌面端由主页面启动流程处理。
- 【已实现：静态依据】`lib/pages/main_page.dart → MainPageState.initState / _login` 首先更新账号资料。打开开关且资料中的 `isPunched == false` 时，桌面端直接打卡，相同条件下移动端重新注册任务，实际执行由系统调度。资料请求为不缓存的 `GET /users/profile`，打卡为 `POST /users/punch-in`，入口位于 `lib/network/picacg_network/methods.dart → getProfile / punchIn`。
- 【已实现：静态依据】`lib/init.dart → init` 在移动端初始化 Workmanager。`lib/tools/background_service.dart → runBackgroundService / onStart` 注册周期为 1440 分钟、有网络才可运行的任务。回调查询 `isPunched`，仍未打卡时提交，成功后发通知。周期任务的实际运行时间取决于系统约束和调度。 [Android WorkManager 周期任务](https://developer.android.com/reference/androidx/work/PeriodicWorkRequest)
- 【推测／待核实】回调只执行 `App.init` 和 `Appdata.readData`，未显式调用 `ComicSource.init` 或 `picacg.loadData` 恢复源凭据，且用空字符串比较判断 Token，需在独立移动端后台执行中验证登录态。回调未按 `taskName` 分派，注册及取消都调用 `cancelAll`，目前的实现会与新增任务互相影响。失败分支仍返回 `true`，未利用系统任务重试。

### 禁漫天堂每日签到

- 【已实现：静态依据】`lib/pages/settings/jm_settings.dart → _JmSettingsState / JmSettings.daily` 使用 `settings[88]`，默认关闭。已有登录时开启开关会立即尝试，点击设置项可手动执行并显示结果。
- 【已实现：静态依据】应用启动在加载源数据后调用 `lib/network/jm_network/jm_network.dart → JmNetwork.init / loginFromAppdata`。已有保存账号时，`ComicSource.reLogin` 进入 `JmNetwork.login`。自动签到位于 `login` 的 `finally` 中，在图片地址更新后检查开关，因此开关开启时，登录流程可以触发签到，登录失败也可能走到该分支。当前没有 JM 周期任务或客户端每日去重。
- 【已实现：静态依据】`JmNetwork.dailyChk` 先以当前用户 ID 请求 `GET /daily?user_id=<用户 ID>` 获取 `daily_id`，再把两项以表单提交至 `POST /daily_chk`。现有代码把消息以「今天」开头，或含有 `Jcoin` / `EXP` 的响应归入成功。该规则未独立区分新领取与当天已签。本轮没有发起登录或真实签到。

## EH 站点机制及项目边界

- 【站点文档】EH 将每日奖励称为 **Dawn of a New Day**，每天在 **00:00 UTC** 重置，中国标准时间为 **08:00**。登录用户访问主站新闻页或某个画廊即可触发，当天提示显示在页面上部。Credits、EXP 等奖励及其数量由站点按账号情况决定。 [Dawn of a New Day](https://ehwiki.org/wiki/Dawn_of_a_New_Day)
- 【已验证：执行证据】站点文档链接指向 `https://e-hentai.org/news.php`，匿名访问可看到新闻页。站点故障说明列出的触发入口是新闻页和主站画廊，普通列表和 My Home 不在该范围。没有看到奖励提示时仍有可能已发放，Dawn 收入也不列在 Credits 交易记录中。 [EH 新闻页](https://e-hentai.org/news.php) · [EH 故障说明](https://ehwiki.org/wiki/Technical_Issues)
- 【已实现：静态依据】项目 `lib/network/eh_network/eh_main_network.dart → EhNetwork` 通过 `settings[20]` 切换 EH／EX 画廊域名，已有 `SingleInstanceCookieJar` 和 `CookieManagerSql` 处理域名 Cookie。`ehentai.isLogin` 读本地账号标记，`validateCookies` 访问 `/home.php`，当前按 HTTP 200 判断成功并写入占位显示名。源码中尚无 Dawn 领取或状态解析入口。`lib/network/cache_network.dart → CachedNetwork.get` 的普通请求可能读本地缓存，`CacheExpiredTime.no` 可跳过缓存读取与写入。
- 【推测／待核实】需用获授权的测试会话确认登录后单次 HTTP GET 能否触发及解析 Dawn。匿名新闻页不能证明奖励发放，普通页面状态码也不能证明当前会话仍登录。公开站点文档把 Dawn 描述为访问触发事件，尚未找到公开的独立签到接口。HentaiVerse 的规则明确限制无人参与获取游戏收益，公开资料对从画廊网站无人值守触发 Dawn 的适用范围未给出明确说明。 [HentaiVerse 脚本规则](https://ehwiki.org/index.php?title=Scripts_%26_Tools#Forbidden_Actions)

## 打开应用时领取的首版方案

1. 【建议】在「设置 → 漫画源 → E-Hentai」加入「打开应用时自动领取每日奖励」，默认关闭，同处显示最近结果和「立即检查」。开启后，从图标冷启动便可触发，无需进入 EH 源。从后台回到前台也走同一个入口，覆盖进程一直存活、次日再打开的情况。手动检查仍可在开关关闭时使用。应用持续停留在前台跨过日界时，等下一次回到前台或手动检查。
2. 【已实现：静态依据】`lib/main.dart → main` 先等待 `lib/init.dart → init`，其中读取设置、创建 `SingleInstanceCookieJar` 并加载 `ComicSource.init`。`lib/pages/main_page.dart → MainPageState.initState` 已有首次进入主界面时的调用位置。`lib/main.dart → _MyAppState.didChangeAppLifecycleState` 已观察 `resumed`。`lib/pages/auth_page.dart → _AuthPageState.auth` 在验证成功时解除应用锁。
3. 【建议】冷启动在主界面进入后异步检查，回前台在 `resumed` 检查，已启用应用锁时等验证通过。这几处都只调用同一领取入口，并由该入口检查应用是否在前台、开关是否开启、当前是否有可用的 EH 账号会话。请求不阻塞首屏或切源。首版由用户打开应用触发，无需设置无人值守任务或安装原生代理核心。
4. 【建议】沿用应用的网络代理和 EH 主站 Cookie，发送不读写缓存的 `GET https://e-hentai.org/news.php`。浏览设置选 EH 或 EX 都使用主站奖励入口。复用 `CachedNetwork.get` 的代理、CookieJar 和响应元数据，关闭该请求的详细网络日志，核对最终 URL、状态码、登录状态和 Dawn 提示。读取主站 Cookie 时兼容旧数据迁移，避免把 `ehentai.isLogin` 或 HTTP 200 单独当作会话有效的证据。代理或网络失败就显示原因，等下次前台触发或用户手动重试。
5. 【建议】按 EH 账号和 UTC 日持久化「已检查」及「已确认领取」，并合并同时到达的触发。同一账号在 **北京时间 08:00** 后进入新的站点日。看到明确提示时记录「已确认领取」。有效会话下新闻页正常但无提示，记录「已访问，奖励未确认」，本日停止自动重复。登录过期提示重新登录。验证、限流、超时保留失败状态，遵守服务端等待时间或本地退避。请求期间换账号、退出登录或跨日时，结果不得写到另一个账号或覆盖新一天的记录。

## 无人值守领取与 Android 后台可行性

### EH 公开规则

- 【站点文档】Dawn 页面与故障说明确认了新闻页、主站画廊和 UTC 日界。检查主站 ToS 及 EHWiki 后，尚未找到明确允许应用在无人操作时定时访问新闻页领取 Dawn 的站方说明。HentaiVerse 脚本规则明确限制在游戏内用脚本获取无人参与的收益，规则正文没有具体说明通过 Galleries 新闻页定时触发 Dawn 的情形。Dawn 的奖励含游戏收益，发布无人值守功能前建议向站方确认这一具体场景。 [站点 ToS](https://e-hentai.org/tos.php) · [Dawn 说明](https://ehwiki.org/wiki/Dawn_of_a_New_Day) · [HentaiVerse 脚本规则](https://ehwiki.org/index.php?title=Scripts_%26_Tools#Forbidden_Actions)
- 【第三方源码】Mayriad 的浏览器脚本在用户访问 EH 相关页面时可代为访问新闻页来触发 Dawn。源码能佐证新闻页 GET 的实现路径。脚本依赖页面活动，且其公开源码本身没有站方对无人值守场景的明确许可。EHWiki 链接的论坛讨论在本轮公开访问中返回 403，未能进一步核对站方回复。 [Mayriad 脚本源码](https://openuserjs.org/scripts/Mayriad/Mayriads_EH_Master_Script/source)

### Android 调度边界

| 使用场景 | Android 能力与限制 |
| --- | --- |
| 首次启用后数天不打开软件，或进程被系统回收 | Android WorkManager 可把已注册的任务保存在本地，后台条件满足后启动执行。重启手机后可重新调度。 [Android 持久任务](https://developer.android.com/develop/background-work/background-tasks/persistent) |
| 锁屏休眠、省电或无网络 | 需要网络的任务会等待条件。Doze 会推迟 JobScheduler 任务，可能跨过当日窗口，无需用户打开不等于保证每天到账。 [周期任务](https://developer.android.com/reference/androidx/work/PeriodicWorkRequest) · [Doze 与 App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby) |
| 在系统应用信息页点「强行停止」 | 系统会取消应用已注册的任务。通常需再次打开应用解除停止，WorkManager 再恢复调度。 [WorkManager 强行停止处理源码](https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/work/work-runtime/src/main/java/androidx/work/impl/utils/ForceStopRunnable.java) · [Android 应用停止状态](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state) |
| 数月没有与应用交互 | Android 12 及以上可能让应用休眠并禁止后台任务，单靠定时任务自身执行无法维持活跃。 [Android 应用休眠](https://developer.android.com/topic/performance/app-hibernation) |

【已实现：静态依据】项目锁定 `workmanager 0.8.0`，已有移动端入口。插件提供带联网约束的周期任务以及按唯一任务名取消。Flutter 在独立后台 isolate 中执行回调，不能直接使用前台进程中已经初始化的 EH 会话对象。当前 `onStart` 只服务于 Picacg，需增加按任务名分派，分别初始化任务所需的设置和 CookieJar。 [Flutter Workmanager 文档](https://docs.page/fluttercommunity/flutter_workmanager/quickstart)

【建议】若站方确认该场景可用，启用时注册独立的 Android 周期任务，关闭时按名取消。可每 12 小时让系统获得一次调度机会，任务开始后先读取最新开关、主站会话和本机日期记录，当前账号当天已有有效检查时直接结束。因此网络访问仍按每个 UTC 日去重，瞬时失败可按退避处理。前台和后台应共用持久化的去重门闩，避免同一天同时触发。后台状态可在下次打开软件时查看。实施前可先用模拟响应在目标真机检查普通退后台、划掉最近任务、锁屏和重新联网后的执行证据，再核对强行停止后的恢复。

## Android 真机模拟验证

【已验证：执行证据】2026-11-21，在 PHZ110（Android 14，ColorOS 14.1）上安装独立验证包，使用项目 `pubspec.lock` 锁定的 `workmanager 0.8.0` 和 `workmanager_android 0.8.0`。任务由系统自然调度，首次在前台注册，之后从应用私有目录读取前台启动记录和回执。Flutter 后台回调若执行，会从手机本机 `127.0.0.1` 获取模拟 Dawn JSON，并记录 HTTP 200、后台进程编号及起止时间。手机以 USB 连接并充电，测试期间保持现有系统设置。测试包未加载 EH 登录态或访问 EH。

【已验证：执行证据】用插件 Dart 公开接口注册时，即使设置 15 分钟 `flexInterval`，JobScheduler 仍报告约 10 分钟的额外等待。`workmanager_android 0.8.0` 的 `lib/workmanager_android.dart → registerPeriodicTask` 发送 `frequencySeconds`、`flexIntervalSeconds`，而 `android/src/main/kotlin/dev/fluttercommunity/workmanager/Extractor.kt → PeriodicTask` 读取 `frequency`、`flexInterval`，未识别时退回 15 分钟周期、5 分钟弹性窗口。为缩短实测等待，验证包通过同一插件的 Android 通道传入接收端实际读取的键，保留周期调度和联网约束。未改动应用的任务注册。后续正式实现需核对依赖版本及实际生效的周期参数，避免只依赖 Dart 层配置值。

### 首轮沿用原有耗电设置

| 场景 | 真机观察 |
| --- | --- |
| 正常返回退出，屏幕保持点亮 | 03:03:48 退出，应用在后台的进程仍在。前台启动计数保持为 1，约 108 秒内无回执。系统任务查询返回 `ready`，已达到执行时间且联网约束满足。 |
| 退出后进程已结束 | 返回后用 `am kill` 模拟后台进程回收。02:57:57，系统日志报告 `SystemJobService` 的任务已就绪但执行失败。退出后约 105 秒没有回执。为登记下一组任务而打开验证包时，先前任务立即写出模拟 HTTP 200 回执，证实模拟回调本身可运行。 |
| 正常退到后台并锁屏 | 02:59:02 至 03:00:04，系统持续显示锁屏界面，验证包前台启动计数保持为 3，进程仍在。约 62 秒内无回执。观察中 JobScheduler 显示时间与联网约束已满足。 |
| 重启后不打开 | 开机计数从 64 增至 65，系统用户状态为 `RUNNING_UNLOCKED`，验证包无启动进程，前台启动计数仍为 3。开机约 73 秒时只读检查验证包的 WorkManager 数据库，重启测试任务保留为 `ENQUEUED`，JobScheduler 查不到它原来的系统任务 ID。开机约 152 秒内没有回执。 |

本地执行证据保存在工作树的 `build/eh-workmanager-probe/observations.jsonl`、`pre-reboot-jobs.log` 和 `normal-exit-scheduler.log`。以上观察只覆盖该真机与测试窗口。JobScheduler 可合并延迟执行已满足约束的任务，现有证据尚无法确定该机拒绝或延迟调度的具体规则。验证未更改自启动或电池优化设置，也未使用系统强行停止作为测试前提。 [Android JobScheduler 调度源码](https://android.googlesource.com/platform/frameworks/base/+/a4cb64d92cd5/apex/jobscheduler/service/java/com/android/server/job/JobSchedulerService.java)

### 复测开启自启动和后台活动

【已验证：执行证据】仍使用同一台手机及同一个独立验证包身份。ColorOS 的「应用详情 → 耗电管理」中，「允许应用自启动」和「允许完全后台行为」均开启，「允许应用关联启动」关闭，「允许唤醒前台」维持开启。两项许可一起调整，每个场景独立登记周期任务，最长观察 35 分钟，收到本机模拟 HTTP 200 回执后结束该场景。登记后不再打开应用，核对前台启动计数与设备状态。

| 场景 | 真机观察 |
| --- | --- |
| 正常返回退出，屏幕点亮 | 03:12:47 确认退出，03:13:10 写出模拟回执，约 23 秒。前台启动计数保持为 1。 |
| 退出后锁屏 | 03:13:34 确认锁屏，03:14:00 写出模拟回执，约 26 秒。读取回执时仍为锁屏界面，前台启动计数保持为 2。 |
| 重启后不打开 | 03:15:04 确认开机，开机计数从 65 增至 66。03:15:10，系统因广播启动 `androidx.work.impl.background.systemalarm.RescheduleReceiver`，任务重新出现在系统调度队列中。03:16:10 写出模拟回执，距确认开机约 67 秒。前台启动计数保持为 3，未手动解锁或打开验证包。重启场景登记时设置了 115 秒初始延迟，以便任务在关机前保持未执行。 |

【已验证：执行证据】三次均由后台回调取得本机模拟 HTTP 200，读回执时应用均未在前台。执行证据见 `build/eh-workmanager-probe/observations.jsonl` 中的 `run6` 记录和 `permission-retest-reboot.log`。首轮短时未通过，开启上述两项许可后在同机验证通过。两项许可一起调整，未单独验证各自的作用。本轮覆盖 USB 连接并充电时的单次调度，未覆盖拔线后的深度休眠、跨日连续执行或其他机型。

【已验证：执行证据】测试后重新进入耗电管理复查，自启动、完全后台行为及关联启动均已恢复关闭，唤醒前台维持开启。验证包的模拟任务已停止，真机日常测试版仍为构建号 6224。

【建议】若后续接入无人值守功能，可把这两项应用级设置纳入该机的使用说明，并让用户能查看最近一次后台执行结果。每日执行时间仍由系统调度，正式接入前仍需确认 EH 站点规则。

## 应用内代理与后台任务

- 【已实现：静态依据】在「设置 → 网络 → 设置代理」关闭「使用系统代理」，填写手机可访问的 HTTP 代理 `地址:端口` 并确认。`lib/pages/settings/app_settings.dart → setProxy` 将值保存为 `settings[8]`，`lib/base.dart → readSettings / updateSettings` 使用应用数据目录的 `settings` 文件持久化。`lib/network/http_client.dart → getProxy` 直接读取手动地址。系统模式保存为 `0`，留空表示直连。若启用了应用内 Hosts，`settings[58]` 的本地代理分支优先。现有入口作用于共用网络链路，未提供 EH 专用配置或代理订阅导入。
- 【已实现：静态依据】EH 网页请求经 `lib/network/eh_network/eh_main_network.dart → EhNetwork.request` 进入 `CachedNetwork.get`，创建请求客户端前调用 `setNetworkProxy`。手动配置只保存代理地址，代理服务需持续可达。手机上的 `127.0.0.1` 指向手机自身，适用于监听对应 HTTP 端口的手机代理服务。若使用电脑或路由器上的 HTTP 代理，填写手机能访问的地址与端口。代理服务是否可达独立于 Android 是否已唤醒应用任务。
- 【推测／待核实】`lib/tools/background_service.dart → onStart` 已从磁盘读取应用设置。手动代理的解析不需要 Android 页面，因此可供后台入口复用。系统模式则调用仅在 `MainActivity.configureFlutterEngine` 注册的代理通道。WorkManager 独立引擎没有这条页面通道时，`getProxy` 捕获异常并返回空值，可能退为直连。现有真机模拟只访问本机回环地址，未验证后台经代理出站。
- 【建议】未来 EH 后台任务启动后读取最新持久化配置，在创建请求客户端前应用代理并初始化现有 CookieJar。需要代理时，代理未配置、不可达或不支持 HTTPS CONNECT，应记录原因，保留重试资格。先用模拟 HTTPS 响应以及可控的 HTTP 代理验证后台走代理、代理不可达和重启后的配置读取，再评估真实访问。

## 内置 Mihomo 按需代理可行性

【已确认方向】内置 Mihomo 及 EH 无人值守方案暂缓。以下记录保留为后续选项。

- 【已实现：静态依据】Mihomo 的 `hub.Parse / executor.ApplyConfig` 能从配置字节初始化代理和监听入口。Clash Meta for Android 已把 Go 核心构建成 Android 的 `libclash.so`。Pica 的 `android/settings.gradle` 使用 AGP 8.12.0、Kotlin 2.2.10，`android/app/build.gradle` 使用 NDK r28，并输出 `arm64-v8a`、`x86_64` 和通用包。仍须针对所选构建产物验收 ABI 和 16 KB 页兼容性。 [Mihomo 核心源码](https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/hub.go) · [Clash Meta Android 构建源码](https://github.com/MetaCubeX/ClashMetaForAndroid/blob/main/core/build.gradle.kts) · [Android 16 KB 页兼容性](https://developer.android.com/guide/practices/page-sizes)
- 【建议】原型将锁定版本的原生库随 Android APK 打包。WorkManager 按任务名进入 EH 分支，在后台 Flutter 引擎通过插件访问应用内的按需代理模块。由该模块建立短时回环 HTTP 代理，只将 EH 检查客户端指向该地址，保留 HTTPS 证书校验。等待代理真实可用后发请求，成功、异常、超时和取消都关闭客户端与代理入口。为限制 Go 全局状态并可验证资源退出，可将核心放在应用自己的非导出绑定服务进程。此方案只处理该请求的出站连接，无需向系统申请 VPN 或改写设备路由。框架的后台调度仍受机器设置与系统时机影响。 [Android 后台及绑定服务限制](https://developer.android.com/about/versions/oreo/background#services)
- 【建议】先复用 Pica 的文件选择入口导入本地 YAML，并选择一个已包含在 `proxies` 里的节点，生成范围受控的运行配置。绑定本机回环地址，使用临时端口和会话级认证或进程内转发，关闭外部控制面板、LAN 和 TUN。订阅 URL、UUID 和密码写入应用私有存储，排除在日志、常规用户数据导出和 WebDAV 同步之外。`proxy-providers`、`rule-providers`、引用文件和地区数据库会增加兼容工作，订阅刷新有时还需要先连通下载源。若配置本身不包含节点，可先从现有配置提取一份自包含节点配置，或另外实现 provider 导入与缓存。是否能直接复用当前配置，需看脱敏后的结构和节点类型。 [Mihomo 代理集合](https://wiki.metacubex.one/config/proxy-providers/) · [Mihomo 入站端口](https://wiki.metacubex.one/config/inbound/port/)
- 【推测／待核实】按一名开发者估算，独立 arm64 真机原型约 2–4 个工作日。覆盖单节点导入、后台闭环及失败清理的受限 Android 版本累计约 1–2 周。支持常见订阅、规则和多 ABI 发布约 3–5 周，配置兼容范围按实际样本调整。原生库可能增加数十 MB 每 ABI，最终 APK 增量和内存占用需实测。项目 `LICENSE` 为 MIT，所查的 Mihomo 核心版本为 GPL-3.0，公开分发结合后的 APK 需先确认对源码、发行方式和许可说明的要求。 [Android 封装体积参考](https://github.com/oviron/libmihomo-android#whats-inside-the-aar) · [Mihomo v1.19.34 许可证](https://github.com/MetaCubeX/mihomo/blob/v1.19.34/LICENSE)
- 【建议】若恢复这项工作，先做独立 arm64 真机原型，只使用单个测试节点和模拟 HTTPS 目标。真机关闭 Clash 后，依次验证内核能启动、请求确实经所选节点发出、成功或超时取消后监听和连接均关闭，再复测锁屏及重启。原型通过后，再决定是否支持现有订阅配置和多架构发行。现有真机结果覆盖 WorkManager 与本机模拟响应，尚未经过代理。

## 实施验收

- 用模拟响应验证冷启动、次日从后台回来、应用锁解锁后才执行、开关关闭及无主站会话时无自动请求、冷启动与恢复并发时只发一次。网络等待不可延迟主界面显示。
- 验证北京时间 08:00 前后分别属于不同站点日、同账号同日已正常检查后不重发、跨日或换账号时记录归属正确。覆盖有奖励、无提示、过期、验证、限流、代理不可达和超时。前台手动检查可核对状态并按退避条件重试。
- 以后在明确授权的测试会话中核对新闻页访问与 Dawn 提示或可独立确认的奖励变化，保存脱敏的最小页面样本。核对普通浏览及 EH／EX 切换仍按原设置执行。
- 后台可行性研究使用公开站点文档、匿名页面及独立模拟包，未使用个人账户或执行领奖请求。

## 首版实施记录

- 【已实现：静态依据】`lib/base.dart → settings[98] / ehDawnOnOpen` 默认关闭。`lib/pages/settings/eh_settings.dart → EhSettings` 提供自动开关、「立即检查每日奖励」及当前账号最近结果。`MainPageState.initState` 在首帧后触发，`_MyAppState.didChangeAppLifecycleState` 处理恢复前台，`_AuthPageState.auth` 补齐应用锁验证完成后的入口。三处复用 `lib/network/eh_network/eh_dawn.dart → EhDawn.onForeground / check`。
- 【已实现：静态依据】从现有 EH 主站 CookieJar 捕获登录 Cookie，并兼容旧 `ehId`、`ehPassHash`。`EhDawn._fetch` 经 `CachedNetwork.get` 复用现有代理，关闭响应日志、HTTP 重定向和本地缓存。请求先访问主站 `/news.php`，在 `#eventpane` 内识别 Dawn 提示。没有提示时只用带有账号使用量标记的 `/home.php` 佐证会话有效，普通新闻页 HTTP 200 不计作登录成功。 [Dawn 站点说明](https://ehwiki.org/wiki/Dawn_of_a_New_Day) · [事件容器第三方源码](https://sleazyfork.org/en/scripts/533796-hv-utils/code)
- 【已实现：静态依据】`EhDawn.check` 使用主站账号 ID 和 UTC 日期合并并发、按日去重。`SharedPreferences` 的 `ehDawn.<账号 ID>` 保存检查日、确认日、结果时间、可识别的 Credits 和最早重试时间，不保存 Cookie。网络失败采用一分钟退避，登录失效和网页验证采用五分钟，限流默认十五分钟并遵守更长的 `Retry-After`。换账号、退出登录和跨日导致在途结果失效。
- 【已验证：执行证据】`flutter test --no-pub test/eh_dawn_test.dart` 的 13 项通过。测试使用模拟页面、固定时钟和临时存储，覆盖并发、同日重开、UTC 跨日、账号隔离、登录跳转、网页验证、限流、代理超时及从前台离开。另用回环代理验证真实请求客户端对 `e-hentai.org:443` 发出 HTTP CONNECT，模拟代理拒绝隧道，测试期间未发出真实 EH 领取请求。
- 【已验证：执行证据】正常入口 `lib/main.dart` 的 Android arm64 离线 Debug 构建成功。校验 APK 包名、架构及与原安装包一致的签名后，通过 `adb install -r` 将「Pica 多选测试」从构建号 6224 更新至 6225，并读取系统包信息核对。APK 保存在 `build/app/outputs/multiselect/PicaComic-eh-dawn-6225-debug.apk`。真机上的真实登录态、代理和奖励展示交由用户验收。

### 奖励明细与账户余额

- 【已实现：静态依据】`lib/pages/settings/eh_settings.dart → EhSettings` 显示「自动领取每日奖励」和「检查每日奖励」。列表只显示当前站点日的确认结果，已确认时显示本地日期时间及「已领取」，其余显示「未领取」。点检查后在滚动弹窗中显示本次 EXP、GP、Credits 和当前可用 GP、Credits、Hath。
- 【已实现：静态依据】`lib/network/eh_network/eh_dawn.dart → EhDawnResult / EhDawn.checkDetails` 从当前 Dawn 提示提取金额。旧记录保留 Credits，缺失 EXP、GP 和无法解析的值显示「未获取」。手动打开弹窗时对主站 `exchange.php?t=gp` 和 `exchange.php?t=hath` 发只读 GET 以获取最新可用余额，自动领取路径无需这两次查询。保留站点提供的 kGP 单位，余额缺失时仍可显示本次已确认奖励。 [EH GP 交易所说明](https://ehwiki.org/wiki/Gallery_Point_Exchange) · [余额字段第三方源码](https://sleazyfork.org/en/scripts/6565-e-hentai-gallery-overview-how-rich-am-i/code)
- 【站点文档】Dawn 未显示时奖励仍可能已发放，且 Dawn 收入不出现在 Credits 交易记录。若此前由浏览器或其他客户端领取，Pica 只能确认自己收到的奖励提示。当前余额不能证明是哪次领取或复原时间及金额。列表「未领取」表示 Pica 当日未取得确认证据，弹窗会解释无提示的情形。 [EH 故障说明](https://ehwiki.org/wiki/Technical_Issues)
- 【已验证：执行证据】`flutter test --no-pub test/eh_dawn_test.dart` 的 16 项模拟验证通过，新增覆盖三种奖励数额、当前站点日状态、余额刷新、旧记录兼容、部分余额失败以及用余额无法确认外部领取。测试未使用真实 EH 账号。
- 【已验证：执行证据】定向静态检查无问题，Android arm64 Debug 离线构建成功。核对与原版相同的测试签名后通过 `adb install -r` 更新「Pica 多选测试」至 6226，系统包信息已核对。APK 为 `build/app/outputs/multiselect/PicaComic-eh-dawn-6226-debug.apk`。用户于 2026-11-21 确认真机验收通过。
