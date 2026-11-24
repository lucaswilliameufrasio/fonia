import Foundation

@main
struct IdentityChecks {
    static func main() {
        let app = URL(fileURLWithPath: "/Applications/Test Browser.app", isDirectory: true)
        let helper = app.appendingPathComponent("Contents/Frameworks/Helpers/Audio Helper.app/Contents/MacOS/Audio Helper")
        precondition(SourceIdentity.owner(of: helper)?.path == app.path)
        precondition(SourceIdentity.owner(of: app.appendingPathComponent("Contents/MacOS/Browser"))?.path == app.path)
        precondition(SourceIdentity.owner(of: URL(fileURLWithPath: "/usr/bin/afplay")) == nil)
        if let argument = CommandLine.arguments.dropFirst().first, let pid = Int32(argument) {
            print(SourceIdentity.resolve(pid: pid, object: 0).name)
        }
    }
}
