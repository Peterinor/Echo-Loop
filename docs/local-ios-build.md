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

## 最新构建：同步上游与本地版精简（2026-09-26）

- [成功运行 #5](https://github.com/Peterinor/Echo-Loop/actions/runs/36160762454)，源码 `018e07d1fad20f9143e9a4d736ba5e90ac78104c`，耗时 18 分 19 秒；已包含上游 `315a326a` 和合并提交 `6789c3d2`。
- 云端 6 项 Python、18 项本地版/访问策略、61 项资源与播客、19 项 AI 客户端/官方访问策略测试全部通过，共 104 项。
- macOS 15.7.9 / Xcode 16.4 / Flutter 3.41.5；iPhone ARM64 Release，版本 `1.0.36 (5)`，最低 iOS 15.0，原始 Bundle ID `top.echo-loop.dev`。
- GitHub 外层 Artifact 摘要、应用 ZIP 校验值、本地模式、原生埋点关闭、ARM64 及本机模型密钥未打包检查通过；IPA 内 684 个条目的字节内容与权限均与云端产物一致。
- IPA：`D:\env\echo-loop\ios-build\run-5\Echo-Loop-local-1.0.36-5.ipa`，61,720,872 字节；仍为未签名包，使用 Sideloadly 和原 Apple 账号、Bundle ID 配置覆盖签名安装，无需删除旧版。
- IPA SHA256：`286bccbae96d7938c71728d7e9da76170b8281b10d8e96d24298b72f1a467819`。
- 应用 ZIP SHA256：`8c2f49090bab97333bdc894b2515f0595cde831c21f372992ed17aafb194b3ef`。
- GitHub Artifact SHA256：`09364de7f31680fa5f80692e8274bd6634e3a7511186d364bfed06207aee9dfe`。

本轮仅推送、云端构建及产物校验，未修改运行时代码。未重跑 `scripts/check.sh` 或 UI / Maestro：上一轮已完成相关测试和 Android 设备验证，全量脚本的既有 Kokoro 集成测试编译阻塞见本地版验收记录。新 IPA 尚未在 iPhone 上签名安装或验证。

## 历史构建：修复合集 404 与首装播客入口（2026-09-25）

- [成功运行 #4](https://github.com/Peterinor/Echo-Loop/actions/runs/36092777859)，源码 `70f3df5dbe3f7a959ff4c80ec88c5e569766bb01`，耗时 17 分 35 秒。
- 修正社区合集与字幕 API 路径，Apple Podcasts 入口不再依赖精选缓存，详情请求失败显示本地化重试按钮。该问题不由 GitHub 打包引起，原 Android 包日志也存在相同 404。
- 云端 6 项 Python、6 项本地版、40 项资源与播客页面、7 项 AI 客户端测试全部通过，共 59 项。
- iPhone ARM64 Release，版本 `1.0.35 (4)`，最低 iOS 15.0；本地模式、原生埋点关闭及模型密钥未打包检查通过。
- 下载后校验 SHA256，重新打包为 `Payload/Runner.app`；684 个应用条目的字节内容与权限均与云端产物一致。
- IPA：`D:\env\echo-loop\ios-build\run-4\Echo-Loop-local-1.0.35-4.ipa`，61,600,457 字节，仍需 Sideloadly 使用原 Apple 账号与 Bundle ID 配置覆盖签名安装。
- IPA SHA256：`464f7f8626dee35f3e6464332f973168bb7cd760915305b77c1035a171449d7e`。
- 原始 ZIP SHA256：`fb83efb41110fed3da069e1ea8ce33f71b8e14153d6a876a711486e2d48ec3ca`。

本地相关测试 46 项、官方相关测试 49 项及静态分析通过；Android 模拟器真实验证 Example 加入、音频/字幕下载及播客入口、搜索、RSS 订阅和单集列表。Maestro CLI 未安装，使用 Flutter integration_test；未运行全量 `scripts/check.sh`（本次是局部修复及构建验证）。已恢复模拟器普通运行包，新 IPA 尚未安装到 iPhone。

## 历史构建：恢复匿名发现资源（2026-09-25）

- [成功运行 #3](https://github.com/Peterinor/Echo-Loop/actions/runs/36089026211)，源码提交 `22b0b7baf0945fb5464207e011e6b078d2f57451`，耗时 15 分 22 秒。
- 包含“发现资源”、免登录加入合集/订阅播客、资源接口白名单和播客首启目录刷新修改。
- macOS 15.7.9 / Xcode 16.4 / Flutter 3.41.5；6 项 Python、6 项本地版和 7 项 AI 客户端测试全部通过。
- iPhone ARM64 Release，版本 `1.0.35`，构建号 `3`，最低 iOS `15.0`；原生埋点关闭，逐文件扫描未发现本机验证所用的模型密钥。
- 下载后核对 SHA256，并将 `.app` 整理成 `Payload/Runner.app` 的未签名 IPA；684 个应用条目的内容及权限元数据均与云端产物一致。
- IPA：`D:\env\echo-loop\ios-build\run-3\Echo-Loop-local-1.0.35-3.ipa`，61,583,532 字节，供 Sideloadly 签名覆盖安装。
- IPA SHA256：`cb50db54ad72686fc91b37b27c0837efa0ed39d9ef09eaf8b8f823eae4d9d79e`。
- 原始 ZIP SHA256：`9c49667f8dd5618996d4a5bc2b3a844a953226fcdcee4b9a32750f52ea30eb79`。

此轮仅进行云端构建和本地打包校验，未运行全量 `scripts/check.sh` 或重新执行 UI / Maestro。用户随后在 iPhone 上反馈 404 与播客入口缺失；后续确认是客户端接口路径和缓存依赖问题，第 4 包已修复，详见上节。

## 首次成功构建记录（2026-09-25）

- [成功运行 #2](https://github.com/Peterinor/Echo-Loop/actions/runs/36082542625)，代码提交 `52486de9`。
- macOS 15.7.9 / Xcode 16.4 / Flutter 3.41.5；6 项 Python 构建配置测试、5 项本地版行为测试及 7 项 AI 客户端测试通过。
- 原入口 `lib/main.dart` 的 iOS Release 编译、ARM64 架构、本地模式及原生 PostHog 配置检查通过。
- 版本 `1.0.35`、构建号 `2`、最低 iOS `15.0`；未签名压缩包约 58.7 MiB。
- 下载后重新核对 SHA256、Mach-O ARM64 及 iPhoneOS 平台；全部压缩包条目未发现本机验证所用的模型密钥。
- SHA256：`33ca4c6212cadcb29ef4ac208743b97dce7720110aaa4a7c69d914f681d41d69`。

首轮编译与本地配置检查已通过，但架构检查命令的参数顺序有误；修复后上述第二轮完整成功。
此次只验证 iOS 构建链路，未运行覆盖全项目/macOS 集成测试的 `scripts/check.sh`。
没有新增应用页面或运行时行为，因此未重跑 Android UI / Maestro；iPhone 真机验证仍未执行。

## 使用 Sideloadly 在自己的 iPhone 上安装

也可以将已编译的 `Runner.app` 按 `Payload/Runner.app` 目录结构打包为 IPA，
交给 Sideloadly 使用自己的 Apple 账号签名安装。这与修改文件后缀不同，
打包时应保留文件内容和 ZIP 权限/符号链接元数据，随后重新验证。
此 IPA 在签名前仍不能直接安装；不需要将 Apple 密码或模型密钥上传到 GitHub。

更新已有安装时，使用上次相同的 Apple 账号与 Bundle ID 配置覆盖安装，
无需先删除旧应用。手机上如有开发者信任或开发者模式提示，需用户亲自确认。

## 可选：使用 Ad Hoc 证书在云端签名

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
