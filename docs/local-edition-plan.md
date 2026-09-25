# 无官方业务后端版本实施方案

日期：2026-09-25。状态：本地版已实现；按用户要求恢复匿名资源发现。

## 已确认范围

- 保留原版页面、播放器、学习流程、本地数据库、收藏、统计及文件备份恢复。
- 禁用登录、会员、支付、恢复购买及官方 AI 等业务后端调用；公开资源读取作为明确例外。
- AI 翻译、句子解析、单词/词组词典、意群和聊天直连用户填写的云端模型 API；AI 仍需要联网。
- 保留原有词典、单词发音包、ASR/TTS 模型的官方 CDN 下载、校验和安装流程，不新增本地资源包导入。
- 保留“发现资源”、官方精选合集、Apple 播客搜索与公开 RSS 订阅；本地版加入资源不要求登录，也不要求配置 AI。隐藏网盘、网页词典、云端字幕转录等入口。
- 禁用网络埋点、远程配置刷新、官方更新检查；保留本地诊断日志。
- 已下载资源、已保存内容和已缓存 AI 结果可离线使用。资源发现和下载需要联网，其中官方精选目录、合集元数据和字幕依赖官方匿名服务。

## 维护原则

使用同一个 `lib/main.dart` 和同一套页面；增加编译期 `APP_EDITION=local` 选择本地版，默认保持上游行为。通过集中能力配置和 Riverpod 注入选择实现，不复制启动文件或页面，也不把本地版伪装成已登录会员。

新增实现集中在 `lib/features/custom_ai/`；共享能力策略放在 `lib/config/app_capabilities.dart`。没有复制启动页、数据库或学习页面；现有文件只添加必要接入点。

继续复用上游数据表和迁移，不删除现有数据；关闭远程功能不应删除已经下载到本地的学习材料。正式本地版默认从配置中排除官方认证、支付和埋点凭据。

## 阶段一：本地版启动与功能边界

建议新增 `lib/config/app_capabilities.dart`，集中定义账号、支付、官方业务 API、资源下载、自带 AI、在线内容、网络统计及更新检查是否可用。资源下载在本地版保持开启。

修改接入点：

| 现有文件或目录 | 具体改动 |
| --- | --- |
| `lib/main.dart` | 读取版本配置；不启动本地版的订阅/套餐控制器、账号分析同步、社区和播客刷新、远程下载恢复任务；保留数据库、媒体预热、词典和发音包初始化 |
| `lib/providers/startup_bootstrap_provider.dart` | 将后台音频、本地维护与网络 SDK 初始化分开；本地版跳过 Supabase、RevenueCat、Firebase 等远程服务和 iOS 官方地址联网探测 |
| `lib/router/main_shell.dart` | 停止远程配置、播客、更新检查在启动/回前台时的刷新；保留本地学习数据刷新及提醒 |
| `lib/analytics/analytics_providers.dart` | 本地版选择本地日志通道；检查 PostHog 包装与原生 SDK 自动初始化，正式包也不得恢复网络上报 |
| `lib/features/remote_config/remote_config_providers.dart` | 本地版使用固定功能配置，不加载旧的远程开关来覆盖本地策略，不启动轮询 |
| `lib/screens/settings_screen.dart`、`lib/router/app_router.dart` | 隐藏账号/会员/更新入口并限制对应路由与深链；后续增加模型设置入口 |
| `lib/features/subscription/providers/subscription_availability.dart` | 本地版订阅入口不可用；不能仅靠留空支付 key 判断 |
| 在线内容的入口及服务 Provider | 开放匿名社区与播客发现、订阅和按需下载；隐藏网盘和云转录，保留本地导入 |
| `lib/providers/dictionary/dictionary_registry.dart` | 本地版仅注册本地词典和 AI 词典；处理旧偏好指向网页词典的回退 |
| `lib/services/backend_dio.dart` | 本地版仅向显式启用的资源客户端放行同源、白名单 GET；其余官方业务请求在发送前拒绝 |

网络控制：账号、支付和官方 AI 等业务 API 禁止；匿名资源 API、公开 RSS、Apple 搜索和 CDN 下载允许；用户 AI 使用独立客户端。普通 Dio、图片、WebView、原生 SDK 不能由 `backend_dio.dart` 一处拦截覆盖，需在入口禁用并检查正式包的实际流量。不得清空 `API_BASE_URL` 后假设所有联网都已停止。

阶段验收：未配置官方凭据可启动和使用本地学习流程；登录、支付及云转录入口不可达；匿名资源可以访问和加入；启动、停留和回前台无官方业务请求；缺少词典/发音包时仍按原逻辑下载，断网失败不阻塞本地学习；已有资源离线可用。

## 阶段二：模型设置与一句翻译闭环

新增自带 AI 模块，职责分为配置存储、协议客户端、任务提示词和结果转换。第一版支持一个明确的兼容协议适配器（OpenAI Chat Completions 兼容），不宣称任意厂商 API 都可直接使用。其他协议后续增加适配器。

- 设置项先提供 API Base URL、API Key、模型 ID、连接测试。先使用一个默认配置服务所有文本任务，按功能选模型可后续扩展。
- 普通配置存入本地设置；密钥使用已有 `flutter_secure_storage` 依赖保存，日志、错误消息及普通备份不包含密钥。
- 连接测试由用户触发，使用轻量请求验证真实调用，明确失败原因，不自动扫描模型列表或后台探测。
- 独立客户端不复用官方 `createAuthenticatedBackendDio`，不携带 Supabase token、地理标识、会员拦截器或官方业务路径。鉴权仅在目标适配器中使用用户密钥，禁止跨主机重定向泄漏鉴权头。
- 用固定的“翻译任务 + 上下文 + 目标语言”提示词调用模型，转换为现有 `SentenceTranslation` 和流帧，继续使用原版翻译页面。
- 先核实协议和结果，再支持增量展示；官方 NDJSON 帧与模型 SSE 不能直接互换。未完成和错误结果不写成功缓存。

实际接入：保留 `lib/services/sentence_ai_api_client.dart` 的官方实现，以子类覆盖已有学习任务方法，Provider 在本地版注入自带模型实现。只将鉴权参数放宽为可空，减少对上游调用点的修改；本地实现不读取该参数。继续复用缓存、请求去重及取消机制。

同时引入统一 AI 请求访问策略：官方模式仍验证登录和额度；本地版验证模型配置。业务层不通过伪造 token、会员状态或空字符串鉴权来绕过登录。UI 对未配置模型显示“配置 AI”，而非“登录/升级会员”。缓存读取不应要求联网或有效密钥。

阶段验收：不登录、不配置官方地址，用用户密钥在原版页面完成一句真实翻译；错误密钥、超时、取消有明确状态；重启后缓存可离线查看。

## 阶段三：其他 AI 功能

| 功能 | 改造与校验 |
| --- | --- |
| 句子解析 | 独立提示词，校验 grammar/vocabulary/listening，转换为现有 `SentenceAnalysis`；不能把容错解析后的空对象当成功结果 |
| 单词/词组词典 | `ai_dictionary_source.dart`、`dictionary_registry.dart`、`lookup_controller.dart` 接统一接口和访问策略；不依赖 Supabase 会话变化触发查询；继续保留本地词典回退 |
| 意群 | 复用现有意群拼接校验，模型输出不得漏词、改写或打乱原句 |
| 对话 | `chat_api_client_provider.dart` 注入直连实现；`chat_session_controller.dart` 使用统一访问策略；将官方 endpoint 映射为客户端任务提示词，不拼接到用户地址；保留多轮、引用、停止和原版展示 |
| 复述评估 | 单独改造：现实现上传音频给官方后端，不能直接改成普通文本接口；使用本地 ASR 得到转录文字，再让用户模型评估内容与表达；不把文字评估标成真实发音评分 |

模型返回的 401 显示密钥问题，429 显示供应商限流，余额或其他供应商错误不进入官方付费墙；保留失败重试，避免无界自动重试造成额外调用。

自带模型缓存采用独立命名空间，包含任务、提供方配置身份、模型、提示词版本、目标语言和必要上下文；不包含密钥。保留既有缓存，提供明确的重新生成入口。模型配置变化时取消或隔离旧请求，避免结果串入新会话或新缓存。

阶段验收：各功能都在原版页面使用真实返回值；格式错误、半途断流、重复请求、取消、切换模型和页面销毁均有测试；本地版无登录及付费跳转。

## 阶段四：Android 与回归验收

- 单元测试：能力配置矩阵、AI 请求策略、密钥脱敏、缓存隔离、协议解析与结构化结果验证。
- Widget 测试：资源匿名加入、其他远程入口隐藏、模型设置引导、未下载音频展示及下载失败状态。
- 集成验收：全新数据启动、已有数据升级、已有资源断网、缺少资源联网下载、用户模型调用、备份恢复。
- Android 正式包检查：仅出现允许的资源下载和用户主动 AI 请求；禁止官方业务请求和埋点。原生插件的流量也要覆盖。
- 先使用现有安卓模拟器验证页面与调用，再用真机验证麦克风、跟读、转录和语音合成。PLAN.md 已记录部分 Android 设备离线 ASR 闪退，不能把模式切换当作该问题已修复。
- 运行每阶段相关 analyze/test；涉及 UI 与首启时运行可用的设备检查。Maestro 当前未安装，执行时需补齐或如实记录阻塞；不以缺少 Maestro 为由跳过其他验证。

## 提交与上游同步

实施时从干净、确认的基线创建 `codex/local-edition` 分支，保留当前未提交改动。按阶段小步提交，每次保持可构建；不修改 `CLAUDE.md` 或 `.claude/` 配置。上游改动通过正常合并接入，不定期重新复制整个项目。

同步后重点复核启动任务、路由、AI 数据契约及新增联网客户端。保留一项检查来提示新增官方地址/调用，并以行为测试和设备流量验证补充；文本扫描不能独自证明无网络依赖。

## 实现与运行（2026-09-24）

分支：`codex/local-edition`。默认构建保持上游版本；添加 `--dart-define=APP_EDITION=local` 才启用本地版。Android Firebase 自动初始化随此开关停用；iOS/macOS 构建阶段从成品 plist 移除 PostHog key 并禁用自动初始化，重新构建官方版时从源码恢复，不改变源码 plist。

本机运行：先打开 Android 模拟器，再在仓库运行 `powershell -ExecutionPolicy Bypass -File scripts/run_local.ps1`。脚本自动读取本机 `D:\env\echo-loop\Activate.ps1`，工具及缓存继续使用 D 盘。其他设备通过 `-Device <设备编号>` 指定。标准构建命令：

```powershell
flutter build apk --debug --flavor dev --target lib/main.dart --dart-define=APP_EDITION=local
```

本机 x86_64 模拟器额外使用 `--target-platform android-x64`，ABI 兼容配置仍只在 D 盘本机 Gradle 配置中，仓库正式 ARM64 设置不变。

应用中进入「设置 → AI 模型设置」，填写 HTTPS Base URL、模型 ID 和密钥，保存后即可使用。当前实测 DeepSeek 官方地址 `https://api.deepseek.com`、模型 `deepseek-flash`；密钥不随代码、普通设置备份或正式 APK 分发。密钥存在 Android 安全存储中，恢复备份到其他设备后需要重新填写。

结构化任务等完整结果返回后展示；对话逐字流式展示。复述评估先在设备上识别录音，仅上传文字供内容与表达评估，不提供声学发音评分。

### 已完成的验证

- 相关官方模式回归 96 项通过；本地模式 12 项通过，未提供凭据时真实 API 用例自动跳过。
- 显式使用本机凭据的真实 API 验证通过：翻译、解析、单词、词组、意群、流式对话和复述文本评估。发现并修复真实 SSE `Uint8List` 类型兼容问题，回归测试使用同种字节流。
- 55 个修改相关 Dart 文件静态检查通过。
- 聊天、登录门控、启动、句子讲解、音频列表和播客合集相关页面/行为回归 285 项通过；最后修改涉及的 4 个目录/文件补充静态检查通过。学习首页补充官方模式 21 项及本地社群入口隐藏回归 1 项通过，对应静态检查通过。
- Android API 35 x86_64 模拟器验证通过：原版启动、设置与路由限制、词典/发音包匿名下载、原音播放、数据库导出和 manifest 校验、Kokoro INT8 下载与真实合成、Whisper Tiny/VAD 下载与真实识别。
- 安卓配置页保存安全密钥后真实翻译通过。保留已安装资源再次运行，在 AI 调用结束后关闭模拟器 Wi-Fi 和移动数据，本地播放、备份、TTS/ASR 全部通过，测试结束恢复联网。
- 日常入口 `lib/main.dart` 的最终模拟器 APK 已构建、安装、启动，首页社群外链已隐藏，启动崩溃日志为空。产物：`D:\env\echo-loop\echo-loop-local-emulator.apk`；源码和最终 APK 的用户密钥扫描通过。模拟器保留已保存的模型配置及下载资源，`D:\env\echo-loop\Open-Android.cmd` 可重新启动，开发模式也已切换本地版。
- 直接读取 APK manifest 确认 FirebaseInitProvider disabled、analytics collection deactivated。Apple 原生配置测试覆盖 iOS/macOS 的本地禁用、官方恢复及其他配置保留；当前 Windows 环境无法实际执行 Xcode 构建。
- 额外备份回归出现 4 项 Windows 临时目录清理失败（文件占用，errno 32）；未修改备份实现或降低原测试要求。Android 导出验证通过，不能据此宣称所有恢复边界已验收。

### 验证边界与后续

- 不是完全断网 AI：首次资源下载和用户主动模型请求仍需联网。已有资源和学习数据可在本机使用。
- 本机没有 Android 真机；麦克风、部分设备已有的 VAD native 闪退仍需真机验证。
- Maestro 脚本已尝试，CLI 缺失而退出；实际设备流程使用 Flutter integration_test 验证。
- 未运行全量 `scripts/check.sh`：脚本硬编码 macOS 集成测试和 macOS 构建，当前为 Windows；已执行针对改动的分析、单测与 Android 集成验证。
- 正式 ARM64 发布包的真机流量审计、已有账号数据升级和完整设备恢复验收仍需发布前执行。当前的后台隔离、HTTP 拦截测试和模拟器验证不能替代正式包抓包。

Android 集成测试使用 `integration_test/local_edition_test.dart` 与对应 driver。运行 `flutter drive` 时必须加 `--keep-app-running`，否则 Flutter 工具会在测试结束后卸载应用（并删除其数据）；请只对测试设备运行。真实模型凭据通过本机文件显式注入测试包，日常包只使用 `lib/main.dart` 和版本开关，不注入模型凭据。

## 修改文件清单

现有页面和 Provider 保留小范围接入；新增模型实现、测试和运行脚本单独存放。未修改 Claude Code 配置。

- `PLAN.md`
- `TASKS.md`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `docs/local-edition-plan.md`
- `integration_test/local_edition_driver.dart`
- `integration_test/local_edition_test.dart`
- `ios/Runner.xcodeproj/project.pbxproj`
- `lib/analytics/analytics_providers.dart`
- `lib/config/app_capabilities.dart`
- `lib/config/auth_config.dart`
- `lib/features/auth/sign_in_required_dialog.dart`
- `lib/features/chatbot/providers/chat_api_client_provider.dart`
- `lib/features/chatbot/providers/chat_session_controller.dart`
- `lib/features/chatbot/services/chat_api_client.dart`
- `lib/features/chatbot/services/fake_chat_api_client.dart`
- `lib/features/custom_ai/custom_ai_access.dart`
- `lib/features/custom_ai/custom_ai_client.dart`
- `lib/features/custom_ai/custom_ai_prompts.dart`
- `lib/features/custom_ai/custom_ai_settings.dart`
- `lib/features/custom_ai/custom_ai_settings_screen.dart`
- `lib/features/custom_ai/custom_chat_api.dart`
- `lib/features/custom_ai/custom_sentence_ai_client.dart`
- `lib/features/custom_ai/local_review_transcriber.dart`
- `lib/features/remote_config/remote_config_providers.dart`
- `lib/features/subscription/providers/feature_access_provider.dart`
- `lib/features/subscription/providers/subscription_availability.dart`
- `lib/features/subscription/providers/subscription_controller.dart`
- `lib/features/subscription/widgets/feature_gate.dart`
- `lib/main.dart`
- `lib/providers/app_update_provider.dart`
- `lib/providers/dictionary/dictionary_registry.dart`
- `lib/providers/retell_review_evaluation_provider.dart`
- `lib/providers/sentence_ai_provider.dart`
- `lib/providers/startup_bootstrap_provider.dart`
- `lib/router/app_router.dart`
- `lib/router/main_shell.dart`
- `lib/screens/collection_detail_screen.dart`
- `lib/screens/collection_screen.dart`
- `lib/screens/library_screen.dart`
- `lib/screens/retell_player_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/study_screen.dart`
- `lib/services/app_deep_link_router.dart`
- `lib/services/backend_dio.dart`
- `lib/services/dictionary/ai_dictionary_source.dart`
- `lib/services/sentence_ai_api_client.dart`
- `lib/widgets/audio_list_tile.dart`
- `lib/widgets/audio_list_view.dart`
- `lib/widgets/dictionary/ai_dict_result_view.dart`
- `lib/widgets/import_audio_sheet.dart`
- `lib/widgets/manage_subtitles_sheet.dart`
- `lib/widgets/practice/sentence_annotation_card.dart`
- `lib/widgets/practice/sentence_explanation_view.dart`
- `macos/Runner.xcodeproj/project.pbxproj`
- `scripts/configure_native_analytics.py`
- `scripts/run_local.ps1`
- `test/features/chatbot/carriers_test.dart`
- `test/features/chatbot/providers/chat_session_controller_test.dart`
- `test/features/chatbot/sheet_race_test.dart`
- `test/features/chatbot/widgets/chat_view_test.dart`
- `test/features/custom_ai/custom_ai_client_test.dart`
- `test/features/custom_ai/custom_ai_live_test.dart`
- `test/features/custom_ai/local_edition_test.dart`
- `test/providers/retell_review_evaluation_provider_test.dart`
- `test/screens/study_screen_test.dart`
- `test/scripts/native_analytics_config_test.py`

## 2026-09-25：匿名发现资源例外

资源客户端只放行 `/api/v1/catalog`、`/api/v2/collections`、`/api/v2/collections/{id}` 和 `/api/v2/collections/{id}/files/{fileId}` 的同源 GET。本地版资源地址由 `RESOURCE_API_BASE_URL` 指定，默认 `https://www.echo-loop.top`；官方版仍使用 `API_BASE_URL`。保持启动/回前台的官方资源后台同步禁用，资源由用户打开页面或刷新时获取。

初次线上抽查时目录返回 200、旧文件地址返回 404，未完成合集下载验收。随后根据 iPhone 反馈核对上游 `a7fb15ee`，确认是客户端 API 路径不匹配，而非必须登录或服务端整体不可用；上面的白名单已修正为实际接口。修复记录见下节。

本次修改文件：

- 配置与网络：`lib/config/app_capabilities.dart`、`lib/config/api_config.dart`、`lib/services/backend_dio.dart`。
- 资源客户端：`lib/features/community_collections/data/community_collection_api.dart`、`lib/features/podcast/data/podcast_catalog_service.dart`。
- 匿名加入：`lib/features/community_collections/screens/discover_collections_screen.dart`、`lib/features/community_collections/screens/community_collection_detail_screen.dart`、`lib/features/podcast/screens/podcast_discovery_screen.dart`、`lib/features/podcast/screens/podcast_preview_screen.dart`。
- 入口与下载：`lib/screens/library_screen.dart`、`lib/screens/collection_screen.dart`、`lib/screens/collection_detail_screen.dart`、`lib/widgets/audio_list_view.dart`、`lib/widgets/audio_list_tile.dart`。
- 测试：`test/features/custom_ai/local_edition_test.dart`、`test/features/community_collections/discover_collections_screen_test.dart`、`test/features/podcast/podcast_discovery_screen_test.dart`、`integration_test/local_edition_test.dart`、`integration_test/local_resources_test.dart`。
- 记录：`PLAN.md`、`TASKS.md`、本文件。

验证记录：

- 修改相关静态分析通过；补充的播客首启加载和设备验收脚本静态分析通过。
- 官方配置相关回归 185 项通过；最后修改后补跑资源与播客页面 10 项通过（本地专用用例只在本地配置运行）。
- 本地配置相关回归 130 项、下载交互 17 项通过；最后补充的播客空缓存回归在 9 项播客页面测试中通过，网络白名单与匿名加入补跑 8 项通过。
- 曾将官方云转录用例放在本地配置下运行，该用例因本地版按设计隐藏云转录而失败；未修改或跳过该用例，在官方配置下完整通过。
- Android API 35 模拟器真实验收通过：入口可见、匿名合集目录、精选播客、Apple 搜索、RSS 预览/订阅和更新、342 期 BBC 节目入库及列表可见。模拟器直连因本机代理网络超时，验收通过 `RESOURCE_TEST_PROXY=10.0.2.2:8087` 使用电脑已有代理；该参数只由测试入口读取，普通安装包不包含代理覆盖。
- 已有登录校验改为本地资源专用放行，没有修改通用 AI 登录/配置门控。支付、账号和官方 AI 请求仍被拦截。
- `scripts/check.sh` 未运行：此次为资源入口及访问范围的局部改动，执行相关检查即可。Maestro CLI 未安装，使用 Flutter integration_test 完成模拟器验证。
- iPhone 上现有安装包仍为此前版本；后续已完成 [iOS 第 3 次构建及 IPA 打包](local-ios-build.md)，更新 iPhone 可使用该 IPA 和同一 Apple 账号覆盖签名安装。
- 原入口 Android dev Debug（x86_64）普通包构建、覆盖安装和启动成功；模拟器已恢复普通运行入口，最新包位于 `D:\env\echo-loop\echo-loop-local-emulator.apk`，未清除原有学习数据。

下一步手动验证：以 `APP_EDITION=local` 运行原入口，进入“资源库 → 发现资源 → Apple Podcasts”，搜索或粘贴公开 RSS 后加入，确认无需登录或配置模型；进入 Example 合集添加并下载一条素材，确认字幕和音频可用。

## 2026-09-25：修复 iPhone 反馈的合集 404 与播客入口缺失

- 合集文件列表改为读取 `GET /api/v2/collections/{id}`；字幕改为从 `GET /api/v2/collections/{id}/files/{fileId}` 的 `subtitle` 对象读取。参考上游 `a7fb15ee` 的实际契约，仅适配客户端边界，未合并上游其它 UI、数据库或目录重构。
- 本地版资源白名单同步修正；旧错误端点、写请求、跨域及账号/支付/官方 AI 接口仍不放行。
- Apple Podcasts 入口独立于精选缓存、社区列表加载/错误/空状态，进入播客页后使用已有目录刷新逻辑。此前模拟器已有精选缓存，掩盖了 iPhone 首装缺少入口的问题。
- 合集详情请求失败改为本地化重试按钮，不再将 Dio 英文异常直接显示到页面。
- 先补回归测试，修复前 7 项失败；修复后本地相关测试 46 项、官方相关测试 49 项通过（另 1 项仅本地模式用例按既有规则不在官方配置运行），相关静态分析通过。iOS 工作流加入社区合集和播客页面回归测试。
- 模拟器原安装包日志同样记录 CATTI 与天津高考合集加入时 404，确认不是 GitHub/iOS 独有问题。
- Android 模拟器完整 integration_test 已通过：Example 匿名预览/加入，下载音频 268333 字节与字幕并校验本地落盘；从可见 Apple 播客入口进入精选、Apple 搜索、RSS 订阅和单集列表。已有学习记录与配置保留，测试可在已加入合集状态重复运行。
- 首轮补充设备测试已下载成功，但脚本按英文寻找中文按钮导致后续等待超时；已改为读取当前语言，并保留详情 Provider 监听及明确返回资源库步骤，最终完整通过。此过程未改动额外应用业务逻辑。
- 本轮未运行 `scripts/check.sh`（局部接口与入口修复）；Maestro CLI 未安装，使用 Flutter integration_test。iPhone 仍需安装新包后复核。
- 修复提交 `70f3df5d` 已推送；第 4 次 iOS 构建成功，59 项云端测试通过，IPA 校验与位置见 [最新构建记录](local-ios-build.md)。后续 `b7372d20` 只补充设备测试与记录，不改变安装包运行时代码。
- Android 普通入口包已重新构建、覆盖安装并启动，最新 APK 为 `D:\env\echo-loop\echo-loop-local-emulator.apk`，启动崩溃日志为空；没有卸载应用或清除学习数据。
