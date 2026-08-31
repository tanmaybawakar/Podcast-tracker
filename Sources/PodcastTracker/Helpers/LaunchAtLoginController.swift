import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var message: String?

    private let service = SMAppService.mainApp

    private init() {
        status = SMAppService.mainApp.status
    }

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    var statusText: String {
        switch status {
        case .notRegistered: "Off"
        case .enabled: "On"
        case .requiresApproval: "Needs approval"
        case .notFound: "Unavailable"
        @unknown default: "Unknown"
        }
    }

    func setEnabled(_ enabled: Bool) {
        message = nil
        do {
            if enabled {
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    message = "Allow PodTrackio under Login Items to keep Rescue available."
                } else if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    func refresh() { status = service.status }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
