# Focus Pet V0

Focus Pet 是一个本地运行的 macOS 专注桌宠原型。当前版本包含菜单栏入口、桌宠浮窗、今日报告、默认规则、隐私面板、摄像头权限入口、前台应用分类、可演示的状态融合/提醒引擎，以及默认 live 检测管线。

## MVP 行为

- 默认运行在 `真实检测` 模式。
- 没有接入视觉模型时，live 管线不会伪造人脸、视线或 head pose；视觉字段保持 `unknown`。
- Demo 场景会切换到 `Demo` 模式，事件会单独标记，不计入真实日报指标。
- 暂停检测会停止摄像头 session，并且不会继续写入状态事件。
- 本地 JSON 分开保存设置、规则、提醒和状态事件；删除数据后不会自动回填 Demo seed 数据。

## 构建

```bash
swift build
```

## 核心校验

当前机器的 Command Line Tools 没有可用的 `XCTest`/`Testing` 模块，所以核心逻辑使用一个无外部测试框架的校验入口：

```bash
swift run FocusPetCoreChecks
```

## 运行 App 原型

```bash
./scripts/package-macos-app.sh
open .build/FocusPet.app
```

打包脚本会生成带 `NSCameraUsageDescription` 的 `.app`，用于正常触发 macOS 摄像头权限说明。V0 不保存视频或图片，只保存结构化状态事件和聚合统计。

当前开发环境只有 Command Line Tools，完整 `xcodebuild` 需要安装 Xcode 后再启用；本仓库默认使用 SwiftPM 构建和打包。
