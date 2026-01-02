# App Store Review Preparation Guide

## 权限说明

### Network Client (com.apple.security.network.client)
**用途：** 检查应用更新（仅在独立版本中启用）

**审核说明：**
```
"Launchory uses network access only for update checking.
In App Store version, updates are managed by Apple's automatic
system. No network usage occurs in App Store builds."
```

### User-Selected Files (com.apple.security.files.user-selected.read-only)
**用途：** 导入用户选择的 Launchpad 数据库文件

**审核说明：**
```
"Launchory allows users to import their existing Launchpad layout
by selecting their Launchpad database file. This is a one-time
optional operation that only reads the file to restore user's app
organization preferences. No other file access is performed."
```

### Apple Events Automation (com.apple.security.automation.apple-events)
**用途：**
1. 注册全局热键（⌘+Space 或自定义快捷键）
2. 登录项管理（SMAppService）

**审核说明：**
```
"Launchory requires Apple Events automation for:

1. Global Hotkeys: Users can open Launchory with a keyboard
   shortcut (⌘+Space by default). This automation enables
   the app to register system-wide keyboard shortcuts.

2. Login Item Management: Users can optionally set Launchory to
   automatically start when they log in to their Mac.

The app only interacts with SystemEvents for these two specific purposes.
No other automation or monitoring is performed."
```

## 隐私声明

### 数据收集
```
Launchory does NOT collect, store, or transmit any personal data.

What we store LOCALLY:
- Application icons (cached for performance)
- App names and paths (for organization)
- User preferences and folder structure

Where it's stored:
~/Library/Application Support/Launchory/

All data remains on the user's device and is never transmitted.
```

### 使用情况
```
Launchory is a local-first application. The only potential network
usage is for update checks in the non-App Store version.

App Store version: No network usage
Standalone version: Optional update check (user-controlled)
```

## 功能演示指南

### 必需展示的功能

1. **核心功能：启动应用**
   - 展示如何从 Launchory 启动应用
   - 验证图标显示正确
   - 展示搜索功能

2. **Launchpad 导入功能**
   - 步骤 1: 打开设置
   - 步骤 2: 点击 "Import Launchpad"
   - 步骤 3: 选择 Launchpad 数据库
   - 步骤 4: 展示导入后的布局恢复

3. **文件夹管理**
   - 展示拖拽应用到文件夹
   - 展示从文件夹移出应用
   - 展示文件夹命名

4. **全局热键**
   - 展示设置热键界面
   - 演示使用热键打开应用
   - 展示自定义快捷键选项

5. **多语言切换**
   - 切换到不同语言
   - 验证所有文本正确显示

### 审核测试账号

提供测试账号信息：
```
Test Account 1:
- Username: reviewer@launchory.test
- Purpose: Testing basic functionality

Test Account 2:
- Username: test2@launchory.test
- Purpose: Testing import functionality

Note: These are dummy accounts for review purposes.
No account is required to use Launchory.
```

## 常见审核问题准备

### Q: 为什么需要 Apple Events 自动化？
**A:** 用于注册全局热键和登录项管理，这是核心功能。

### Q: 数据存储在何处？
**A:** 完全在本地 ~/Library/Application Support/Launchory/

### Q: 应用是否收集用户数据？
**A:** 否，所有数据本地存储，不上传任何信息。

### Q: Launchpad 导入如何工作？
**A:** 用户手动选择其旧系统的 Launchpad 数据库文件，应用读取并恢复布局。

## 提交前检查清单

### 技术检查
- [x] 应用在 macOS 26 (Tahoe) 上测试通过
- [x] 沙盒限制下所有功能正常工作
- [x] 无崩溃或卡顿
- [x] 内存使用合理（< 200MB）
- [x] 启动时间 < 2 秒

### 审核检查
- [x] 所有权限都有明确说明
- [x] 隐私政策已提交
- [x] 应用描述准确反映功能
- [x] 截图展示真实功能
- [x] 无 Apple IP 侵权
- [x] 无误导性功能描述

### 素材检查
- [x] 应用图标符合 Apple 设计规范
- [x] 所有截图设备尺寸正确
- [x] 截图无模拟设备或占位符
- [x] 预览视频展示核心功能
- [x] 应用名称在不同语言中显示正确
