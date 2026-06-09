# Focus Pet V0

Focus Pet 是一个本地运行的 macOS 专注桌宠原型。V0 包含菜单栏入口、桌宠浮窗、今日报告、默认规则、隐私面板、摄像头权限入口、前台应用分类和可演示的状态融合/提醒引擎。

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
