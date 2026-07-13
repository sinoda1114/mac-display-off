import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() throws {
        if isEnabled {
            try SMAppService.mainApp.unregister()
        } else {
            try SMAppService.mainApp.register()
        }

        refresh()
    }
}
