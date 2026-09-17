import Foundation

public struct StoragePolicy: Sendable {
    public static let forbiddenExactPaths: Set<String> = ["/", "/Library", "/private/var"]
    public static let allowedSystemRoots = [
        "/Library/Updates",
        "/Library/Caches",
        "/private/var/folders"
    ]

    public init() {}

    public func classify(path rawPath: String) -> (FindingCategory, RiskLevel, String, Bool) {
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let lower = path.lowercased()

        if path.hasPrefix("/Library/") || path.hasPrefix("/private/var/") {
            let allowed = Self.allowedSystemRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
            return (.systemItem, allowed ? .high : .protected, "Requires administrator authorization and recoverable quarantine.", allowed)
        }

        let userDataMarkers = [
            "/messages/", "/mail/", "/msg/", "/attachments/", "/steamapps/", "/documents/",
            "/mobile documents/", "/browser/", "/databases/", "/application support/google/chrome/"
        ]
        if userDataMarkers.contains(where: lower.contains) {
            return (.userData, .protected, "May contain irreplaceable user or application data. Use the app's storage manager.", false)
        }

        let modelMarkers = ["model", "huggingface", "whisper", "gpt4all", ".gguf", "simulator", "runtime"]
        if modelMarkers.contains(where: lower.contains) {
            return (.redownloadable, .medium, "Can usually be downloaded again; offline features may stop working.", true)
        }

        let cacheMarkers = ["/caches/", "/.cache/", "/logs/", "/.npm/", "sparkle", "update_downloading", "code_sign_clone"]
        if cacheMarkers.contains(where: lower.contains) {
            return (.lowRiskCache, .low, "Reproducible cache, log, or updater staging data.", true)
        }

        return (.userData, .high, "Unrecognized application data; review manually before removal.", false)
    }

    public func validateSystemPath(_ rawPath: String) throws -> String {
        let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        guard standardized.hasPrefix("/") else { throw PolicyError.notAbsolute }
        guard !Self.forbiddenExactPaths.contains(standardized) else { throw PolicyError.forbiddenRoot }
        guard Self.allowedSystemRoots.contains(where: { standardized == $0 || standardized.hasPrefix($0 + "/") }) else {
            throw PolicyError.outsideAllowlist
        }

        let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().standardizedFileURL.path
        guard Self.allowedSystemRoots.contains(where: { resolved == $0 || resolved.hasPrefix($0 + "/") }) else {
            throw PolicyError.symlinkEscape
        }
        return resolved
    }

    public enum PolicyError: LocalizedError, Equatable {
        case notAbsolute
        case forbiddenRoot
        case outsideAllowlist
        case symlinkEscape

        public var errorDescription: String? {
            switch self {
            case .notAbsolute: "Path must be absolute."
            case .forbiddenRoot: "Broad system roots cannot be cleaned."
            case .outsideAllowlist: "Path is outside the system cleanup allowlist."
            case .symlinkEscape: "Resolved path escapes the allowed directory."
            }
        }
    }
}
