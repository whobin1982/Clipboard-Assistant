import Foundation
import ServiceManagement

/// 开机自启动功能可能因为系统版本过低而不可用。
enum LoginItemServiceError: LocalizedError {
    case unsupportedOperatingSystem

    var errorDescription: String? {
        switch self {
        case .unsupportedOperatingSystem:
            return "开机自动启动需要 macOS 13 或更高版本。"
        }
    }
}

/// 封装 ServiceManagement 的开机自动启动状态读写。
final class LoginItemService {
    /// 查询当前应用是否已经注册为登录项。
    func isEnabled() throws -> Bool {
        guard #available(macOS 13.0, *) else {
            throw LoginItemServiceError.unsupportedOperatingSystem
        }

        return SMAppService.mainApp.status == .enabled
    }

    /// 注册或取消注册登录项；状态未变化时不重复调用系统 API。
    func setEnabled(_ isEnabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LoginItemServiceError.unsupportedOperatingSystem
        }

        guard try self.isEnabled() != isEnabled else { return }

        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
