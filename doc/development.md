# 开发环境与验证

[返回知识库](README.md)。本文只记录已读配置及本轮实际检查；未来操作命令不表示已经执行成功。

## 环境依据

| 项目 | 【已实现：静态依据】及限制 |
| --- | --- |
| Flutter／Dart | 根 `README.md` 徽章为 Flutter `3.41.6`；`pubspec.yaml → environment.sdk` 为 `>=3.3.0`，但当前 `pubspec.lock → sdks` 为 Dart `>=3.9.0-0 <4.0.0`、Flutter `>=3.32.0`。不能只用清单最低版本判定当前锁文件可解析 |
| 应用版本 | `pubspec.yaml → version` 与 `lib/foundation/def.dart → appVersion` 分别为 `4.2.11+4211` 和 `4.2.11`；修改版本时要核对这两个消费者，本轮未改 |
| 包与资源 | 单一根包；`pubspec.yaml → dependencies / flutter.assets` 声明依赖、JS 与翻译资源。Git 依赖及 resolved-ref 见锁文件，不执行依赖升级 |
| Android | `android/settings.gradle` 声明 AGP `8.12.0`、Kotlin `2.2.10`；wrapper 为 Gradle `8.14.3`；`android/app/build.gradle` 要求 Java 17、NDK `28.0.13004108`，SDK 版本取 Flutter 变量 |
| Android 本机配置 | `android/settings.gradle → flutterSdkPath` 读取 `local.properties → flutter.sdk`；`android/app/build.gradle` 无条件加载 `key.properties`，debug 与 release 都引用其 `storeFile / storePassword / keyAlias / keyPassword`。当前检出不含这两个文件，不能假设 debug 自动采用默认签名；只记录键名，不生成或索取真实密钥 |
| Windows | 存在 CMake／runner 工程；`windows/runner/CMakeLists.txt → runner / flutter_assemble` 为原生构建入口；额外打包见 `windows/build_windows.py`，后者还依赖 tar、Inno Setup `iscc` 及字体资源 |
| iOS／macOS | `.github/workflows/main.yml` 使用 macos-15、Xcode 16.4、Flutter stable；iOS 以 `--no-codesign` 构建并打包 IPA。配置存在不等于本机或最新 CI 已通过 |
| Linux | `.github/workflows/linux.yml` 安装 ninja、GTK3 和 webkit2gtk-4.1，调用 `debian/build.py`、`flutter_to_debian`、`flutter_to_arch`；打包元数据见 `debian/` 和 `pubspec.yaml → flutter_to_arch` |
| Web | 有 `web/` 工程，但业务使用 `dart:io` 与多个原生依赖，本轮没有 Web 构建证据 |

## 建议的后续本地启动顺序

【建议】首先让 Flutter／Dart 在 PATH 可发现，核对版本与设备；不通过盲目降级到 `>=3.3.0` 或重生成锁文件解决环境差异。以下是待执行的 PowerShell 命令：

```powershell
Get-Command flutter,dart
flutter --version
flutter doctor -v
flutter devices
```

【建议】确认 Git 依赖与原生工具链后，才执行依赖解析和项目检查；检查锁文件变化的原因，不将更新依赖混入无关工作：

```powershell
flutter pub get
flutter analyze
flutter test
```

分析入口依据为 `analysis_options.yaml → include: package:flutter_lints/flutter.yaml`；原 `test/widget_test.dart → main` 仍为空。多选功能已新增 `test/comic_selection_test.dart` 和基于 Flutter SDK `integration_test` 开发依赖的真机测试；其验证范围见[多选变更记录](changes/2026-11-16-multi-select-favorites.md)，不据此认为阅读、下载或迁移已验证。

【建议】目标是 Windows 时，可在工具链检查通过后使用 `flutter run -d windows` 做最小启动验证。首次运行会创建 support/cache 数据并执行旧数据检查；应使用独立的测试应用数据，观察启动、设置、无账户浏览和错误提示。Android 还需先解决上表的本机 SDK／签名配置；本轮不通过修改 Gradle 绕过它。

## CI 的实际职责

| 文件 | 静态核对的动作 | 本轮是否执行 |
| --- | --- | --- |
| `.github/workflows/main.yml` | 手动触发 iOS／macOS 构建、上传 artifact；Flutter channel 为浮动 stable | 未触发 |
| `.github/workflows/ios_simulator.yml` | 手动触发模拟器构建、上传 artifact | 未触发 |
| `.github/workflows/linux.yml` | 手动安装系统／打包依赖，构建 Linux 并上传包 | 未触发 |
| `.github/workflows/delete_old_workflows.yml` | 手动删除旧运行记录，申请 `actions: write` | 未触发；不是项目测试 |

这些工作流中没有 `flutter analyze` 或 `flutter test` 步骤，也没有常规 push／PR 的自动检查配置。本轮未查询运行历史，不能以 YAML 存在证明 CI 绿灯。

## 已审阅但未运行的写操作脚本

- `windows/build_windows.py` 追加字体到 `pubspec.yaml`、构建 Windows、改写 `windows/build.iss` 后打包，再尝试恢复；没有 `try/finally` 保证异常恢复。它是打包脚本，不是只读验证命令。
- `debian/build.py` 临时替换 Debian 配置及 desktop 文件的版本，调用构建／打包后恢复；同样包含写入。
- `utils/check_translation.dart → main` 会直接改写 `assets/translation.json`、补空翻译并删除未发现的键；不能按文件名把它当成只读检查。
- `utils/tags_translation.dart → main` 克隆标签数据库、覆盖 `assets/tags.json` 并递归删除临时仓库；不能作为首轮静态分析的默认步骤。
- `lib/tools/io_tools.dart → importData / moveDirectory` 与 `lib/init.dart → _checkOldData` 会替换／删除应用数据。首轮只阅读定义；后续用户指定备份的导入恢复执行记录见[导入恢复](changes/2026-11-16-data-import-recovery.md)。

## 首轮分析验证记录

【已验证：执行证据】已检出用户指定的公开仓库，完成分支／远程／HEAD、工作区及暂存区检查；源码基准只记录在[索引](README.md)。仓库初始干净，未发现已跟踪的 AGENTS、ADR、子模块或 LFS 配置。

【已验证：执行证据】使用 `Get-Command` 检查 PATH：Git 与 Python 可发现，`flutter` 和 `dart` 均不可发现。没有安装 SDK、解析依赖、运行应用、构建、分析器或 Flutter 测试；不以静态阅读代替这些检查。

文档相对链接、源码路径、占位内容、变更范围及空白检查的结果记录在[索引的交付检查](README.md#交付检查)。首轮分析阶段未执行提交、推送、创建 PR、远程工作流或漫画源／WebDAV 账户访问；后续按用户授权配置的 Fork 与 `dev` 分支见[协作仓库与分支](README.md#协作仓库与分支)。

## 本机 Android 真机环境（2026-11-16）

【已验证：执行证据】按用户确认的最小方案安装，工具实际存放在 `E:\Program Files\AndroidDev`。`E:\AndroidDev` 是指向该目录的 NTFS Junction，用于 Android/NDK 的无空格路径访问，不是第二份安装。未安装 Android Studio、模拟器或系统镜像。

| 组件 | 已配置版本／位置 |
| --- | --- |
| Flutter / Dart | Flutter 3.41.6（官方 Git 标签固定版本）、Dart 3.11.4；`E:\Program Files\AndroidDev\flutter` |
| Android 命令行工具 | 22.0；`AndroidDev\android-sdk\cmdline-tools\latest` |
| SDK 平台／Build-Tools | API 31～36，Build-Tools 35.0.0；`AndroidDev\android-sdk\platforms`、`build-tools`；平台版本对应当前锁定插件各自的 compileSdk，不包含模拟器系统镜像 |
| ADB | Platform-Tools 37.0.0；复制复用用户已有 E 盘工具，保留原目录；本环境入口为 `AndroidDev\android-sdk\platform-tools` |
| NDK / CMake | NDK 28.0.13004108、CMake 3.22.1；`AndroidDev\android-sdk\ndk`、`cmake`；后者由 `flutter_qjs` 的 Android 构建指定 |
| Java | 复用已有 JDK 21.0.10，`E:\Program Files\jdk\jdk21` |
| Pub / Gradle 缓存 | `AndroidDev\pub-cache`、`AndroidDev\gradle-cache`；项目依赖按原锁文件解析，没有升级依赖 |
| 配置、调试签名、临时目录 | `AndroidDev\user-config`、`android-user`、`local-data`、`temp`；日志和安装清单在 `AndroidDev\logs`、`setup` |

除首行和 Java 行写明绝对路径外，表中 `AndroidDev\...` 均相对 `E:\Program Files`。各目录空间占用以本机安装清单为准；不把 Junction 重复计入。

【已验证：执行证据】`AndroidDev\bin` 中的 `flutter.cmd`、`dart.cmd`、`sdkmanager.cmd`、`adb.cmd` 已配置到用户 PATH。包装器把 Pub、Gradle、Android 用户配置、Flutter 配置和运行临时文件定向 E 盘；已有终端需重新打开才能继承用户环境变量，也可直接调用完整路径。

```powershell
& 'E:\Program Files\AndroidDev\bin\flutter.cmd' doctor -v
& 'E:\Program Files\AndroidDev\bin\flutter.cmd' pub get --offline --enforce-lockfile
& 'E:\Program Files\AndroidDev\bin\flutter.cmd' devices
```

【已验证：执行证据】`flutter doctor -v` 检查全部通过；Redmi K30 5G 真机已授权 USB 调试，Android 11（API 30）、ARM64。手机 ID 仅用于本地命令，不写入共享知识库。`android/local.properties` 和 `android/key.properties` 为本机配置，已确认被 Git 忽略；调试签名位于 E 盘，不使用发布密钥。

本机 Java 下载复用现有 HTTP 代理 `127.0.0.1:7897`，设置保存在专用 Gradle 配置和启动包装器中。若本机代理端口或网络改变，应同步调整这些本地设置。工具未改系统代理。

【已验证：执行证据】首次 Gradle 默认 4 GiB 堆构建出现原生内存分配失败；已在专用 `gradle-cache/gradle.properties` 中配置 1536 MiB 堆、2 个 worker、关闭并行和常驻 daemon、Kotlin 编译进程复用。该本机限制不修改仓库 `android/gradle.properties`。构建时仍需留出其他进程可用的系统内存。

【已验证：执行证据】释放其他应用占用并补齐 SDK 平台后，以下命令退出码为 0；Gradle 8.14.3 完成 636 个任务（631 执行、5 已为最新），首次成功构建约 6 分 28 秒。产物为 `build/app/outputs/flutter-apk/app-debug.apk`，约 104.5 MiB；APK 元数据确认应用 ID 为 `com.github.pacalini.pica_comic`、版本 4.2.11（4211）、可调试。未修改业务源码、依赖锁文件或已跟踪的 Android 构建配置。

```powershell
& 'E:\Program Files\AndroidDev\bin\flutter.cmd' build apk --debug --target-platform android-arm64 --no-pub
```

【已验证：执行证据】Redmi 的首次安装返回 `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`。用户更换手机后，识别为 PHZ110、Android 14（API 34）、ARM64；该设备已有原版应用，因此采用独立测试包 `com.github.pacalini.pica_comic.devtest`，不覆盖原应用或使用其数据。

【已验证：执行证据】初次独立包名由 E 盘本机 `gradle-cache/init.d/pica-isolated-debug.gradle` 设置：仅匹配本检出目录的 `:app` 工程，通过 `androidComponents.finalizeDsl` 为 Debug 的 `applicationIdSuffix` 设置 `.devtest`。后续多选功能验证改用 `.devtest.multiselect`，保留手机既有原版和 `.devtest` 包的数据。Release 不加后缀，仓库 Android 构建配置未改。生成路径仍为 `build/app/outputs/flutter-apk/app-debug.apk`，该路径随当前构建目标被覆盖；集成测试 APK 不能当作正常应用入口的 APK。

【已验证：执行证据】独立测试包构建通过，ADB 安装返回 `Success`；`am start -W` 返回 `Status: ok`，冷启动约 3 秒。启动后检查到应用进程和前台 MainActivity，截图确认显示首次设置界面（漫画列表显示方式）；采集的启动日志没有匹配到初始化失败、Flutter 错误或崩溃标记。证据在本机 `logs/pica-device-launch.log`、`logs/pica-device-launch.png` 和 `setup/device-test.json`。验证仅覆盖安装及首次启动，漫画源、阅读、下载和数据迁移仍未验证。

【已验证：执行证据】安装主目录按 Windows 文件分配空间统计约 10.23 GiB，其中包含 Pub／Gradle 依赖和构建缓存；项目内 `build/`、`.dart_tool/`、`android/.gradle/` 的生成文件另约 1.68 GiB。复用的 JDK 约 317 MiB，不计入新增安装主目录。统计未重复计入 Junction，也不包含目录元数据；后续构建会改变缓存大小。本机逐项清单为 `E:\Program Files\AndroidDev\installation-report.md`，机器可读数据为同目录下 `setup/inventory.json`。

## 多选收藏的检查与真机运行

【已验证：执行证据】本轮多选新增 `integration_test` SDK 开发依赖，原有依赖版本未升级。`flutter test --no-pub test/comic_selection_test.dart` 的 8 项回归通过；当前 Android 14 真机运行集成测试的 5 组场景通过，补充关键词/排序/漫画源切换的 1 组场景也通过。精确范围及验证日志见[变更记录](changes/2026-11-16-multi-select-favorites.md)。按目标文件静态检查无 error/warning，保留 8 条既有 info；未触发远程 CI。

真机测试通过 `flutter test integration_test/multi_select_favorites_test.dart --no-pub --reporter expanded` 并以 `-d` 指定授权设备；设备 ID 仅留在本机命令。测试目标使用中性临时源供数和临时 SQLite 收藏夹，不需要真实账户或站点 Cookie。测试不是实际网站连通性检查。

【已验证：执行证据】最终正常入口按 `flutter build apk --debug --target lib/main.dart --target-platform android-arm64 --no-pub` 构建；本机 Debug 名称为“Pica 多选测试”，包名后缀 `.devtest.multiselect`，已在当前真机安装并正常冷启动。E 盘的 `setup/pica-multiselect-debug-manifest.xml` 复制原 Debug 权限并仅覆盖应用名称，由本机 Gradle init 配置引用；仓库 Android 构建文件未改。普通入口 APK 另存于 `build/app/outputs/multiselect/PicaComic-multiselect-debug.apk`，避免与集成测试入口产物混淆。原版与之前的 `.devtest` 应用及数据均保留。

## 大库导入恢复检查

导入修复范围与执行证据见[导入恢复变更](changes/2026-11-16-data-import-recovery.md)。新增 `integration_test/data_import_test.dart` 使用中性生成的数据库和数据包，必须使用不含个人数据的独立 Debug 包。

【已实现：静态依据】本机 Flutter 3.41.6 的 `flutter_tools/lib/src/test/integration_test_device.dart → start / kill` 在构建前读取现有 APK 的包名，测试结束按该缓存包名卸载；Android `startApp` 构建后另行读取新 APK。切换本机 Debug 后缀而直接运行测试，会使这两个包名不一致。【已验证：执行证据】本轮由此误卸载多选测试版，已发现并从事前完整快照恢复；原版应用及原导出未受影响。不能将一次成功测试等同于测试环境隔离正确。

【建议】今后切换测试包名时，先单独构建相应测试目标，使用 `aapt dump badging` 核实生成 APK 为独立测试包，再启动真机测试；测试前另行确认设备包名及快照。已有个人数据的应用不得作为 `flutter test integration_test/...` 的目标，正常入口更新使用校验包名后的 ADB `install -r`，避免测试工具自动卸载行为。

## 跨页选择的本地回归与安装交付

【已验证：执行证据】`flutter test --no-pub test/comic_selection_test.dart test/cross_page_selection_test.dart --reporter expanded` 共 14 项通过；定向分析为 No issues found。新增测试使用电脑端中性源/条目，不读取个人数据或调用站点；已有真机集成脚本已更新分页保留和数量文案期望，但本轮未运行。规则、模拟边界及证据见[跨页变更](changes/2026-11-16-cross-page-selection.md)。

正常入口构建、包名核对、当前应用完整数据备份及 ADB `install -r` 更新完成，启动请求返回 Status: ok。当前普通测试版支持跨页选择，提示顶部偏移为安全区域下 228 个逻辑像素；APK 为 `build/app/outputs/multiselect/PicaComic-cross-page-selection-debug.apk`。实际网站和真机交互仍交由用户验收，不用本地模拟通过代替真机验收。

【已验证：用户反馈】用户在最新大图标与全不选版本安装后确认测试通过，并授权汇总提交到个人仓库 dev；该验收记录见[跨页选择变更](changes/2026-11-16-cross-page-selection.md#用户验收与仓库交付2026-11-16)。本机自动安装记录保留执行时的 user_pending 状态，其后的用户确认以本段和变更记录为准。

## 阅读统计/收藏分页主机验证（2026-11-17）

【已验证：执行证据】阅读统计与本地收藏分页排序的 34 项主机测试和 Android arm64 Debug 构建通过，未安装/启动真机；用户明确要求连接后另行通知更新。未使用个人数据或漫画源账户。详细范围与待验证项见[实施记录](changes/2026-11-17-reading-statistics-favorites.md)。

Windows 运行临时 SQLite 测试时，将 PICA_TEST_SQLITE3 指向已有 SQLite DLL，再用已配置 E 盘 wrapper 执行 `flutter test --no-pub`；这是测试进程的动态库选择，不是应用依赖或全局环境安装。静态分析无 error，但保留未改文件的 22 条 warning 和既有 info。当前构建仍输出既有 NDK 版本建议/SDK XML 警告，构建成功；没有为此升级依赖或改业务/原生配置。

2026-11-18 补充交付：按用户新授权调整页大小至 20/40/60/80/100，默认及旧 50 项归为 60；34 项主机回归和正常 APK 构建通过。先保存当前测试版 APK/完整私有数据，再核对包名并使用 ADB install -r 覆盖更新，启动请求成功、MainActivity 保持前台；收藏/历史数据库哈希未变。未运行设备集成测试，功能交互仍由用户验收，见[交付记录](changes/2026-11-17-reading-statistics-favorites.md#2026-11-18-页大小调整与真机交付)。

同日收藏显示/排序修复：37 项主机回归、定向分析无 error/warning、正常 Android 构建与覆盖安装/启动检查通过；未运行设备集成测试，收藏/历史哈希与事前备份一致。验证细节见[增量修复](changes/2026-11-18-favorites-display-fixes.md)。

## 磁盘缓存回归与真机验收（2026-11-18）

【已验证：执行证据】缓存回归入口为 `flutter test --no-pub test/cache_manager_test.dart`。Windows 测试进程可通过 `PICA_TEST_SQLITE3` 指向已有 SQLite DLL。测试使用临时缓存目录和 SQLite 库，通过测试接口降低容量，覆盖界面最小值以下的压力场景。

【已验证：执行证据】Android 合成压力测试在独立包运行。真实 EH 验收使用正常入口的 Android 14 测试版，临时隔离该应用的磁盘缓存和索引，并恢复原设置、缓存和索引。各场景的验证结果见[缓存修复记录](changes/2026-11-18-disk-cache-capacity.md)。

## 阅读统计与收藏合并交付回归（2026-11-18）

【已验证：执行证据】在已包含磁盘缓存修复的 `dev` 基线上纳入阅读统计、收藏分页排序和显示修复，使用临时 SQLite 运行 `flutter test --no-pub --reporter expanded`，42 项通过。本轮验证在主机执行，真机交互验证范围见[实施记录](changes/2026-11-17-reading-statistics-favorites.md)和[显示修复](changes/2026-11-18-favorites-display-fixes.md)。
