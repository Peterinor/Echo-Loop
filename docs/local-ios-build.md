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
