import Foundation
import ServiceManagement

enum LoginItemServiceError: LocalizedError {
    case unsupportedOperatingSystem

    var errorDescription: String? {
        switch self {
        case .unsupportedOperatingSystem:
            return "开机自动启动需要 macOS 13 或更高版本。"
        }
    }
}

final class LoginItemService {
    func isEnabled() throws -> Bool {
        guard #available(macOS 13.0, *) else {
            throw LoginItemServiceError.unsupportedOperatingSystem
        }

        return SMAppService.mainApp.status == .enabled
    }

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
