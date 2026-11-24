import AppKit

struct SourceIdentity {
    let id: String
    let name: String

    // Chromium and Electron may expose only an unregistered helper PID.
    static func owner(of executable: URL) -> URL? {
        var cursor = executable
        var app: URL?
        while cursor.path != "/" && !cursor.path.isEmpty {
            if cursor.pathExtension.lowercased() == "app" { app = cursor }
            cursor.deleteLastPathComponent()
        }
        return app
    }

    static func resolve(pid: Int32, object: UInt32) -> Self {
        let running = NSRunningApplication(processIdentifier: pid)
        let executable = FoniaExecutablePath(pid).map { URL(fileURLWithPath: $0) } ?? running?.executableURL
        let identifier = running?.bundleIdentifier ?? FoniaBundleIdentifier(object)
        let owner = executable.flatMap(owner(of:)) ?? running?.bundleURL.flatMap(owner(of:))
            ?? identifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.flatMap(owner(of:))
        if let owner {
            let bundle = Bundle(url: owner)
            let title = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            return Self(id: bundle?.bundleIdentifier ?? owner.path,
                        name: title.flatMap { $0.isEmpty ? nil : $0 } ?? owner.deletingPathExtension().lastPathComponent)
        }
        return Self(id: identifier ?? "pid:\(pid)",
                    name: running?.localizedName ?? executable?.lastPathComponent ?? identifier ?? "Fonte não identificada (\(pid))")
    }
}
