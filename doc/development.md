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

分析入口依据为 `analysis_options.yaml → include: package:flutter_lints/flutter.yaml`；测试依赖为 `pubspec.yaml → dev_dependencies.flutter_test`。目前 `test/widget_test.dart → main` 为空，没有断言；即使将来测试命令结束，也不能据此认为阅读、下载或迁移已验证。

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
- `lib/tools/io_tools.dart → importData / moveDirectory` 与 `lib/init.dart → _checkOldData` 会替换／删除应用数据。本轮只阅读定义，没有执行。

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

【已验证：执行证据】独立包名由 E 盘本机 `gradle-cache/init.d/pica-isolated-debug.gradle` 设置：仅匹配本检出目录的 `:app` 工程，通过 `androidComponents.finalizeDsl` 为 Debug 的 `applicationIdSuffix` 设置 `.devtest`。Release 不加后缀，仓库源码和构建配置未改。使用本机工具链的后续 Debug 构建也沿用这一测试包名；生成路径仍为 `build/app/outputs/flutter-apk/app-debug.apk`，首次无后缀构建的产物已由后续测试版替换。

【已验证：执行证据】独立测试包构建通过，ADB 安装返回 `Success`；`am start -W` 返回 `Status: ok`，冷启动约 3 秒。启动后检查到应用进程和前台 MainActivity，截图确认显示首次设置界面（漫画列表显示方式）；采集的启动日志没有匹配到初始化失败、Flutter 错误或崩溃标记。证据在本机 `logs/pica-device-launch.log`、`logs/pica-device-launch.png` 和 `setup/device-test.json`。验证仅覆盖安装及首次启动，漫画源、阅读、下载和数据迁移仍未验证。

【已验证：执行证据】安装主目录按 Windows 文件分配空间统计约 10.23 GiB，其中包含 Pub／Gradle 依赖和构建缓存；项目内 `build/`、`.dart_tool/`、`android/.gradle/` 的生成文件另约 1.68 GiB。复用的 JDK 约 317 MiB，不计入新增安装主目录。统计未重复计入 Junction，也不包含目录元数据；后续构建会改变缓存大小。本机逐项清单为 `E:\Program Files\AndroidDev\installation-report.md`，机器可读数据为同目录下 `setup/inventory.json`。
