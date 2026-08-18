import Foundation
import ServiceManagement

/// 登录启动管理（PRD F-09「登录时启动」/ 技术方案 12 LoginItemManager）。
///
/// 封装 macOS 13 原生 `SMAppService.mainApp`：读取与更新「登录时启动」状态。
/// 首次注册若需用户在系统设置确认（`requiresApproval`），仍视为成功进入流程，
/// 由系统设置完成最终启用。
@MainActor
final class LoginItemManager {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    /// 是否已启用登录启动。
    var isEnabled: Bool {
        service.status == .enabled
    }

    /// 首次注册后需用户在系统设置中确认。
    var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    /// 开启登录启动。已开启时幂等；状态变为 requiresApproval 不算失败。
    func enable() throws {
        guard service.status != .enabled else { return }
        try service.register()
    }

    /// 关闭登录启动。未开启时幂等。
    func disable() throws {
        guard service.status == .enabled else { return }
        try service.unregister()
    }
}
