import AppKit
import SwiftUI

@main
struct DisplayOFFApp: App {
    @State private var currentDisplaySleepMinutes: Int?
    @State private var currentSystemSleepMinutes: Int?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @StateObject private var loginItemManager = LoginItemManager()

    private let displaySleepManager = DisplaySleepManager()

    var body: some Scene {
        MenuBarExtra("Display OFF", systemImage: "display") {
            menuContent
                .task {
                    await refreshCurrentValue()
                    loginItemManager.refresh()
                }
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuContent: some View {
        Text("Display OFF")
            .font(.headline)

        Divider()

        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
        }

        Divider()

        Menu {
            displaySleepOptions
        } label: {
            Label(
                "ディスプレイオフ: \(DisplaySleepOption.title(for: currentDisplaySleepMinutes))",
                systemImage: "display"
            )
        }
        .disabled(isLoading)

        Menu {
            systemSleepOptions
        } label: {
            Label(
                "スリープ: \(DisplaySleepOption.title(for: currentSystemSleepMinutes))",
                systemImage: "moon"
            )
        }
        .disabled(isLoading)

        Divider()

        Button("今すぐディスプレイをオフ") {
            Task {
                await sleepDisplayNow()
            }
        }
        .disabled(isLoading)

        Divider()

        Button {
            toggleLoginItem()
        } label: {
            if loginItemManager.isEnabled {
                Label("起動時に自動起動", systemImage: "checkmark")
            } else {
                Text("起動時に自動起動")
            }
        }

        Divider()

        Button("終了") {
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private var displaySleepOptions: some View {
        ForEach(DisplaySleepOption.all) { option in
            Button {
                Task {
                    await setDisplaySleep(option.minutes)
                }
            } label: {
                if currentDisplaySleepMinutes == option.minutes {
                    SelectedPowerOptionLabel(title: option.title)
                } else {
                    Text(option.title)
                }
            }
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private var systemSleepOptions: some View {
        ForEach(DisplaySleepOption.all) { option in
            Button {
                Task {
                    await setSystemSleep(option.minutes)
                }
            } label: {
                if currentSystemSleepMinutes == option.minutes {
                    SelectedPowerOptionLabel(title: option.title)
                } else {
                    Text(option.title)
                }
            }
            .disabled(isLoading)
        }
    }

    @MainActor
    private func refreshCurrentValue() async {
        do {
            currentDisplaySleepMinutes = try await displaySleepManager.getCurrentDisplaySleepMinutes()
            currentSystemSleepMinutes = try await displaySleepManager.getCurrentSystemSleepMinutes()
            errorMessage = nil
        } catch {
            currentDisplaySleepMinutes = nil
            currentSystemSleepMinutes = nil
            showError("現在の設定を取得できませんでした", error: error)
        }
    }

    @MainActor
    private func setDisplaySleep(_ minutes: Int) async {
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            try await displaySleepManager.setDisplaySleep(minutes: minutes)
            await refreshCurrentValue()
        } catch {
            showError("ディスプレイオフ設定の変更に失敗しました", error: error)
        }
    }

    @MainActor
    private func setSystemSleep(_ minutes: Int) async {
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            try await displaySleepManager.setSystemSleep(minutes: minutes)
            await refreshCurrentValue()
        } catch {
            showError("スリープ設定の変更に失敗しました", error: error)
        }
    }

    @MainActor
    private func sleepDisplayNow() async {
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            try await displaySleepManager.sleepDisplayNow()
        } catch {
            showError("今すぐディスプレイをオフにできませんでした", error: error)
        }
    }

    @MainActor
    private func toggleLoginItem() {
        do {
            try loginItemManager.toggle()
            errorMessage = nil
        } catch {
            showError("自動起動設定に失敗しました", error: error)
        }
    }

    @MainActor
    private func showError(_ title: String, error: Error) {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorMessage = title

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct SelectedPowerOptionLabel: View {
    let title: String

    var body: some View {
        HStack {
            Text("\(title) ✓")
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
        }
    }
}
