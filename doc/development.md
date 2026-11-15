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
