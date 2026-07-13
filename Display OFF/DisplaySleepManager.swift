import Foundation

enum DisplaySleepError: LocalizedError {
    case commandFailed(command: String, message: String)
    case cancelled
    case invalidMinutes(Int)
    case invalidUserName(String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .commandFailed(_, let message):
            return message.isEmpty ? "コマンドの実行に失敗しました" : message
        case .cancelled:
            return "管理者認証がキャンセルされました"
        case .invalidMinutes(let minutes):
            return "\(minutes)分は許可されていない設定値です"
        case .invalidUserName(let userName):
            return "sudoersに登録できないユーザー名です: \(userName)"
        case .parseFailed:
            return "現在の設定を取得できませんでした"
        }
    }
}

struct DisplaySleepManager {
    private enum PowerSetting: String, CaseIterable {
        case displaySleep = "displaysleep"
        case systemSleep = "sleep"
    }

    private let allowedMinutes: Set<Int> = [0, 1, 5, 10, 30, 60, 120]

    func getCurrentDisplaySleepMinutes() async throws -> Int? {
        try await getCurrentMinutes(for: .displaySleep)
    }

    func getCurrentSystemSleepMinutes() async throws -> Int? {
        try await getCurrentMinutes(for: .systemSleep)
    }

    func setDisplaySleep(minutes: Int) async throws {
        try await set(minutes: minutes, for: .displaySleep)
    }

    func setSystemSleep(minutes: Int) async throws {
        try await set(minutes: minutes, for: .systemSleep)
    }

    func sleepDisplayNow() async throws {
        _ = try await run("/usr/bin/pmset", arguments: ["displaysleepnow"], requiresAdmin: false)
    }

    private func getCurrentMinutes(for setting: PowerSetting) async throws -> Int? {
        let output = try await run("/usr/bin/pmset", arguments: ["-g", "custom"], requiresAdmin: false)
        return try parseMinutes(from: output, setting: setting)
    }

    private func set(minutes: Int, for setting: PowerSetting) async throws {
        guard allowedMinutes.contains(minutes) else {
            throw DisplaySleepError.invalidMinutes(minutes)
        }

        let arguments = ["-n", "/usr/bin/pmset", "-a", setting.rawValue, String(minutes)]

        do {
            _ = try await runProcess(launchPath: "/usr/bin/sudo", arguments: arguments)
        } catch {
            try await installPasswordlessPmsetPermission()
            _ = try await runProcess(launchPath: "/usr/bin/sudo", arguments: arguments)
        }
    }

    private func parseMinutes(from output: String, setting: PowerSetting) throws -> Int? {
        let values = output
            .split(separator: "\n")
            .compactMap { line -> Int? in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.first == Substring(setting.rawValue), let value = parts.dropFirst().first else {
                    return nil
                }
                return Int(value)
            }

        guard let firstValue = values.first else {
            throw DisplaySleepError.parseFailed
        }

        return firstValue
    }

    private func run(_ launchPath: String, arguments: [String], requiresAdmin: Bool) async throws -> String {
        if requiresAdmin {
            let command = ([launchPath] + arguments).map(shellQuoted).joined(separator: " ")
            return try await runProcess(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", "do shell script \(appleScriptString(command)) with administrator privileges"]
            )
        }

        return try await runProcess(launchPath: launchPath, arguments: arguments)
    }

    private func installPasswordlessPmsetPermission() async throws {
        let userName = NSUserName()
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

        guard !userName.isEmpty, userName.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw DisplaySleepError.invalidUserName(userName)
        }

        let allowedCommands = PowerSetting.allCases
            .flatMap { setting in
                allowedMinutes
                    .sorted()
                    .map { "/usr/bin/pmset -a \(setting.rawValue) \($0)" }
            }
            .sorted()
            .joined(separator: ", ")
        let sudoersLine = "\(userName) ALL=(root) NOPASSWD: \(allowedCommands)"
        let script = """
        set -e
        tmp="$(/usr/bin/mktemp /tmp/display-off-sudoers.XXXXXX)"
        /bin/cat > "$tmp" <<'DISPLAY_OFF_SUDOERS'
        \(sudoersLine)
        DISPLAY_OFF_SUDOERS
        /usr/sbin/chown root:wheel "$tmp"
        /bin/chmod 0440 "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        /bin/cp "$tmp" /etc/sudoers.d/display-off
        /usr/sbin/chown root:wheel /etc/sudoers.d/display-off
        /bin/chmod 0440 /etc/sudoers.d/display-off
        /bin/rm -f "$tmp"
        """

        _ = try await runProcess(
            launchPath: "/usr/bin/osascript",
            arguments: ["-e", "do shell script \(appleScriptString(script)) with administrator privileges"]
        )
    }

    private func runProcess(launchPath: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw DisplaySleepError.commandFailed(command: launchPath, message: error.localizedDescription)
            }

            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                if process.terminationStatus == 1, errorOutput.localizedCaseInsensitiveContains("User canceled") {
                    throw DisplaySleepError.cancelled
                }

                let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw DisplaySleepError.commandFailed(command: launchPath, message: message)
            }

            return output
        }.value
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }
}
