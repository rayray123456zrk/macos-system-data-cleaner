import Foundation

struct PrivilegedHelperClient: Sendable {
    enum HelperError: LocalizedError {
        case helperMissing
        case authorizationCancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing: "The bundled quarantine helper is missing. Rebuild the application."
            case .authorizationCancelled: "Administrator authorization was cancelled. No files were changed."
            case .failed(let message): message
            }
        }
    }

    func run(action: String, arguments: [String]) async throws -> String {
        guard let helperURL = Bundle.main.url(forAuxiliaryExecutable: "macspaceguard-helper") else { throw HelperError.helperMissing }
        let command = ([helperURL.path, action] + arguments).map(shellQuote).joined(separator: " ")
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            if stderr.localizedCaseInsensitiveContains("cancel") || process.terminationStatus == 1 { throw HelperError.authorizationCancelled }
            throw HelperError.failed(stderr.isEmpty ? "Privileged helper failed." : stderr)
        }
        return stdout
    }

    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func appleScriptQuote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
}
