# Launchory 开发规范

## 项目概述

Launchory 是一个 macOS 启动台替代应用，旨在恢复 macOS Tahoe 移除的经典 Launchpad 体验。

## 环境要求

- **macOS**: 26.0+ (Tahoe)
- **Xcode**: 26.0+
- **Swift**: 5.0+
- **许可证**: MIT

## 项目结构

```
Launchory/
├── Launchory/
│   ├── LaunchpadApp.swift      # 应用入口
│   ├── AppDelegate.swift       # 应用代理
│   ├── AppStore.swift          # 核心状态管理
│   ├── AppInfo.swift           # 应用信息模型
│   ├── AppCacheManager.swift   # 缓存管理
│   ├── FolderInfo.swift        # 文件夹信息
│   ├── FolderView.swift        # 文件夹视图
│   ├── LaunchpadView.swift     # 主视图
│   ├── LaunchpadItemButton.swift
│   ├── SettingsView.swift      # 设置视图
│   ├── ControllerInputManager.swift  # 手柄支持
│   ├── SoundManager.swift      # 音效管理
│   ├── VoiceManager.swift      # 语音反馈
│   ├── Animations.swift        # 动画工具
│   ├── Extensions.swift        # 扩展
│   ├── GeometryUtils.swift     # 几何工具
│   ├── IconStore.swift         # 图标存储
│   ├── Localization.swift      # 本地化
│   ├── NativeLaunchpadImporter.swift  # Launchpad导入
│   ├── PerformanceMode.swift   # 性能模式
│   ├── Info.plist              # 应用配置
│   ├── Launchory.entitlements # 沙盒权限
│   ├── Assets.xcassets/        # 资源目录
│   └── AppIcon.icon/           # 自定义图标
├── Launchory.xcodeproj/
├── UpdaterScripts/             # 更新脚本
├── i18n/                       # 国际化文档
└── *.lproj/                    # 本地化文件
```

## 编码规范

### 命名规范

- **类/结构体**: PascalCase (`AppStore`, `LaunchpadView`)
- **变量/属性**: camelCase (`isFullscreenMode`, `currentPage`)
- **常量**: kebab-case 或 camelCase (`minColumnsPerPage`)
- **枚举值**: camelCase (`case system`, `case light`)
- **文件命名**: 与主要类型同名

### Swift 风格指南

```swift
// ✅ 推荐
final class AppStore: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published private(set) var updateState: UpdateState = .idle

    func checkForUpdates() { }

    private func performInitialScanIfNeeded() { }
}

// ❌ 避免
class appStore: ObservableObject { }
class App_store: ObservableObject { }
```

### 访问控制

```swift
// 公开接口使用 public/internal
// 内部实现使用 private/fileprivate

final class AppStore: ObservableObject {
    @Published public private(set) var apps: [AppInfo] = []

    func publicMethod() { }

    private func privateMethod() { }

    fileprivate func internalMethod() { }
}
```

### MainActor 隔离

```swift
// UI 相关代码应在 MainActor 上执行

@MainActor
final class AppStore: ObservableObject {
    @Published var currentPage: Int = 0

    // 自动在主线程执行
    func updateUI() { }
}

// 非 UI 代码使用非隔离
final class DataProcessor {
    func processData() async {
        // 后台处理
        let result = await compute()
        // 回到主线程更新 UI
        await MainActor.run {
            viewModel.update(result)
        }
    }
}
```

### 错误处理

```swift
// ✅ 推荐
enum AppError: LocalizedError {
    case invalidURL
    case scanFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .scanFailed(let msg): return "Scan failed: \(msg)"
        case .permissionDenied: return "Permission denied"
        }
    }
}

// 使用 Result 或 throws
func fetchLatestRelease() async throws -> GitHubRelease {
    guard let url = URL(string: apiURL) else {
        throw AppError.invalidURL
    }
    // ...
}
```

## App Store 上架注意事项

### 环境检测

```swift
enum AppStoreEnvironment {
    case appStore
    case standalone

    static var current: AppStoreEnvironment {
        #if DEBUG
        return .standalone
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .appStore
        }
        return .standalone
        #endif
    }
}
```

### 禁用功能

在 App Store 环境下禁用以下功能：

- GitHub 自动更新 (使用 `AppStoreEnvironment.current.isAppStore` 检测)
- 直接读取 Launchpad 数据库 (改用用户选择目录)
- 某些需要临时权限异常的系统操作

### 权限配置

`Launchory.entitlements` 中必须包含：

- `com.apple.security.app-sandbox`: true
- `com.apple.security.files.user-selected.read-only`: true
- `com.apple.security.network.client`: true

## 本地化规范

### 添加新语言

1. 在 `*.lproj/` 目录创建 `Localizable.strings`
2. 添加语言到 `project.pbxproj` 的 `knownRegions`
3. 在 `Localization.swift` 中添加语言枚举

### 本地化字符串格式

```swift
// Localization.swift
enum LocalizationKey {
    case appName
    case settingsTitle
    case checkForUpdates
    // ...
}

// 使用
Text(appStore.localized(.checkForUpdates))
```

## 性能优化

### 图标缓存

```swift
// 使用 AppCacheManager 进行图标缓存
cacheManager.cacheIcon(image, for: appPath)
let cachedIcon = cacheManager.getCachedIcon(for: appPath)
```

### 后台扫描

```swift
// 应用扫描应在后台队列执行
DispatchQueue.global(qos: .userInitiated).async {
    // 扫描逻辑
    DispatchQueue.main.async {
        // 更新 UI
    }
}
```

## 测试规范

### 单元测试

```swift
import XCTest
@testable import Launchory

final class AppStoreTests: XCTestCase {
    func testAppScanning() async {
        let store = AppStore()
        // 测试扫描逻辑
    }
}
```

### UI 测试

```swift
import XCTest

final class LaunchoryUITests: XCTestCase {
    func testLaunchpadOpens() {
        let app = XCUIApplication()
        app.launch()
        // 测试 UI 交互
    }
}
```

## 提交规范

### Git 提交信息

```
<type>(<scope>): <subject>

<body>

<footer>
```

类型：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式
- `refactor`: 重构
- `perf`: 性能优化
- `test`: 测试
- `chore`: 构建/工具

示例：
```
feat(appstore): 添加沙盒环境检测

- 添加 AppStoreEnvironment 枚举
- 禁用 App Store 环境下的自动更新
- 更新项目配置以支持沙盒

Closes #123
```

### 分支命名

- `main`: 主分支
- `develop`: 开发分支
- `feature/*`: 功能分支
- `bugfix/*`: Bug 修复分支
- `release/*`: 发布分支

## 构建与发布

### 本地构建

```bash
# Debug 构建
xcodebuild -project Launchory.xcodeproj -scheme Launchory -configuration Debug

# Release 构建
xcodebuild -project Launchory.xcodeproj -scheme Launchory -configuration Release

# 通用二进制
xcodebuild -project Launchory.xcodeproj -scheme Launchory -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

### App Store 构建

1. 更新版本号 (`MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`)
2. 配置 `DEVELOPMENT_TEAM`
3. 启用 `CODE_SIGN_STYLE = Automatic`
4. 确认 `GENERATE_INFOPLIST_FILE = NO`
5. 确认 `CODE_SIGN_ENTITLEMENTS` 指向正确的 entitlements 文件

### 上传 App Store

```bash
xcrun altool --upload-app -f Launchory.app -u "Apple ID" -p "App-Specific Password"
```

## 依赖管理

### 系统框架

项目使用以下系统框架（无需额外依赖管理）：

- `AppKit`: macOS UI
- `SwiftUI`: 声明式 UI
- `SwiftData`: 数据持久化
- `Combine`: 响应式编程
- `Carbon`: 系统交互
- `GameController`: 手柄支持
- `ServiceManagement`: 登录项管理

### 外部工具

- **SwiftUpdater**: 用于独立版本的自动更新（不在 App Store 版本中使用）

## 文档维护

### API 文档

- 使用 Swift DocC 生成文档
- 关键类型和函数添加注释

### README 维护

- 更新功能列表
- 添加新功能说明
- 更新截图

## 常见问题

### Q: Xcode 报错 "Cannot find type 'XXX' in scope"

**A**: 这是 Xcode 诊断错误，不影响实际编译。确保所有文件已添加到正确的 target。

### Q: 如何切换 App Store 和独立版本？

**A**: 使用 `AppStoreEnvironment.current.isAppStore` 检测当前环境。

### Q: 沙盒限制导致功能异常？

**A**: 检查 `Launchory.entitlements` 是否包含必要的权限，或考虑改用用户选择的方式。

## 参考文献

- [Apple App Store 审核指南](https://developer.apple.com/app-store/review/guidelines/)
- [macOS Sandbox 指南](https://developer.apple.com/documentation/security/app_sandbox)
- [Swift 编码规范](https://www.swift.org/documentation/api-design-guidelines/)
