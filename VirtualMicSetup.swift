import Foundation
import CryptoKit

enum DriverAction: CaseIterable {
    case install, remove
    var filename: String {
        self == .install ? "BlackHole2ch-0.7.1.pkg" : "BlackHole2chUninstaller.pkg"
    }
    var checksum: String {
        self == .install ? "57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"
                         : "30f833287b0e5b482f80c2649d8f8c2fff37359db2c6fa1d48cc50e5684567cf"
    }
}

enum VirtualMicSetup {
    static let driver = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver")

    static func driverPresent(at url: URL = driver) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static let signer = "Developer ID Installer: Existential Audio Inc. (Q5C99V536K)"

    static func accepts(signed: String, assessment: String) -> Bool {
        let chain = signed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let policy = assessment.components(separatedBy: .newlines)
        return chain.contains("1. \(signer)") && policy.contains("source=Notarized Developer ID")
            && policy.contains("origin=\(signer)") && policy.contains { $0.hasSuffix(": accepted") }
    }

    private static func check(_ tool: String, _ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw VoiceRouteError("O macOS não validou o pacote. Nenhum instalador foi aberto.")
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func verify(_ package: URL, for action: DriverAction) throws {
        let hash = SHA256.hash(data: try Data(contentsOf: package, options: .mappedIfSafe))
        guard hash.map({ String(format: "%02x", $0) }).joined() == action.checksum else {
            throw VoiceRouteError("O pacote não corresponde à versão revisada.")
        }
        let signed = try check("/usr/sbin/pkgutil", ["--check-signature", package.path])
        let assessed = try check("/usr/sbin/spctl", ["--assess", "--type", "install", "-vv", package.path])
        guard accepts(signed: signed, assessment: assessed) else {
            throw VoiceRouteError("Não foi possível confirmar o editor e a notarização pela Apple.")
        }
    }

    static func download(_ action: DriverAction = .install) async throws -> URL {
        let url = URL(string: "https://existential.audio/downloads/")!.appendingPathComponent(action.filename)
        let (temporary, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url == url else {
            throw VoiceRouteError("Não foi possível obter o pacote na origem oficial.")
        }
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let package = folder.appendingPathComponent(action.filename)
            try manager.moveItem(at: temporary, to: package)
            try verify(package, for: action)
            return package
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }
}
