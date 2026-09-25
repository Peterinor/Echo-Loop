# GitHub 云端构建 iOS 本地版

## 当前方式：无证书编译验证

工作流：`.github/workflows/build-local-ios.yml`，名称 **Local iOS Build**。
使用 macOS 15、Xcode、Flutter 3.41.5 编译 `dev` flavor 的 Release，明确传入
`APP_EDITION=local`，不需要任何 GitHub Secrets、苹果开发者账号或模型密钥。
模型地址和密钥仍在安装后的应用设置中由用户填写。

推送相关代码到 `codex/local-edition` 或 `main` 后自动构建。
在 GitHub 的 **Actions → Local iOS Build** 查看运行，失败时可进入失败步骤查看日志，
也可以从 **Re-run jobs → Re-run failed jobs** 重试临时网络故障。
工作流合并到默认分支后，可用 **Run workflow** 手动选择分支运行；
工作流仅在功能分支时，使用上述 push 触发即可，无需更改仓库默认分支。

成功后在运行详情底部 **Artifacts** 下载 `echo-loop-local-ios-unsigned-<运行编号>`。
其中包括 `.app` 压缩包、SHA256 校验文件和代码提交编号；构建日志独立保存。
产物保留 14 天，过期后可以重新构建。

**这是面向 iPhone ARM64 的未签名 .app，不是可安装 IPA，也不能在 iOS 模拟器运行。**
构建成功只证明代码能在 Apple 工具链编译、原生埋点已关闭，不代表真机功能测试完成。
工作流会先执行本地版行为测试和 Apple 配置测试，再验证编译产物。
现有上游 `CI`、`Release` 工作流保持原样；不要通过 `Release` 打包本地版。

## 已完成验证（2026-09-25）

- [成功运行 #2](https://github.com/Peterinor/Echo-Loop/actions/runs/36082542625)，代码提交 `52486de9`。
- macOS 15.7.9 / Xcode 16.4 / Flutter 3.41.5；6 项 Python 构建配置测试、5 项本地版行为测试及 7 项 AI 客户端测试通过。
- 原入口 `lib/main.dart` 的 iOS Release 编译、ARM64 架构、本地模式及原生 PostHog 配置检查通过。
- 版本 `1.0.35`、构建号 `2`、最低 iOS `15.0`；未签名压缩包约 58.7 MiB。
- 下载后重新核对 SHA256、Mach-O ARM64 及 iPhoneOS 平台；全部压缩包条目未发现本机验证所用的模型密钥。
- SHA256：`33ca4c6212cadcb29ef4ac208743b97dce7720110aaa4a7c69d914f681d41d69`。

首轮编译与本地配置检查已通过，但架构检查命令的参数顺序有误；修复后上述第二轮完整成功。
此次只验证 iOS 构建链路，未运行覆盖全项目/macOS 集成测试的 `scripts/check.sh`。
没有新增应用页面或运行时行为，因此未重跑 Android UI / Maestro；iPhone 真机验证仍未执行。

## 后续导出可安装 IPA

需要 Apple Developer Program 账号、包含私钥的 Apple Distribution `.p12` 及密码，
以及登记目标 iPhone UDID 的 Ad Hoc `.mobileprovision`。
先注册自己的 Bundle ID，再创建匹配的证书和描述文件。
准备后将以下内容保存到仓库 **Settings → Secrets and variables → Actions**：

- `IOS_DIST_CERT_BASE64`：证书文件的 Base64。
- `IOS_DIST_CERT_PASSWORD`：证书密码。
- `IOS_PROVISIONING_PROFILE_BASE64`：描述文件的 Base64。

当前无签名工作流不会读取这些 Secrets。签名阶段还需配置自己的 Team / Bundle ID、
为本地版移除不用的 Apple 登录与原项目关联域名权限，并加入 archive/export 步骤。
不能只改文件后缀将未签名 `.app` 当成可安装 IPA。
证书、私钥和模型凭据不要放进仓库。
