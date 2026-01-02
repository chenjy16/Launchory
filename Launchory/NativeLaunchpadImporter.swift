import Foundation
import SwiftData

/// App Store 合规版本 - 移除了所有私有 API 访问
/// 原有的从系统 Launchpad 数据库导入功能已被移除，因为它违反了 App Store 审核指南 2.5.2
class NativeLaunchpadImporter {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // 所有从系统数据库导入的功能已被移除以符合 App Store 规定
    // - importFromNativeLaunchpad(): 访问私有系统数据库
    // - importFromDatabasePath(): 读取外部数据库文件
    // - importFromLegacyArchive(): 解压并读取归档中的数据库
    // - getNativeLaunchpadDatabasePath(): 获取系统私有路径
}

// MARK: - 数据模型（保留用于可能的未来合规导入功能）

struct ImportResult {
    let convertedApps: Int
    let convertedFolders: Int
    let failedApps: [String]

    var summary: String {
        var lines = [
            "✅ Import Completed!",
            "📱 Apps: \(convertedApps)",
            "📁 Folders: \(convertedFolders)"
        ]

        if !failedApps.isEmpty {
            lines.append("⚠️ Not found: \(failedApps.count)")
        }
        
        return lines.joined(separator: "\n")
    }
}

enum ImportError: LocalizedError {
    case databaseNotFound(String)
    case databaseError(String)
    case systemError(String)
    case conversionError(String)
    case featureDisabled(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let msg):
            return "Database not found: \(msg)"
        case .databaseError(let msg):
            return "Database error: \(msg)"
        case .systemError(let msg):
            return "System error: \(msg)"
        case .conversionError(let msg):
            return "Conversion error: \(msg)"
        case .featureDisabled(let msg):
            return "Feature disabled: \(msg)"
        }
    }
}
