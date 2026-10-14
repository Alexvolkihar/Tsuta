import Foundation

/// Minimal blocking process runner shared by git, forge CLIs and AI CLIs.
public enum ProcessRunner {
    public struct Output: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
        public let timedOut: Bool
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    /// GUI apps inherit a minimal PATH; CLIs like `gh` or `claude` live in user-level directories.
    public static let searchDirectories: [String] = {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local",
                "\(home)/.cargo/bin", "\(home)/.bun/bin", "/usr/bin", "/bin"]
    }()

    public static func resolve(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in searchDirectories {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    public static func environment(adding extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        env["PATH"] = (searchDirectories + existing.filter { !searchDirectories.contains($0) }).joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"
        for (key, value) in extra { env[key] = value }
        return env
    }

    public static func run(executable: String, arguments: [String], stdin: String? = nil,
                           environment extra: [String: String] = [:], directory: URL? = nil,
                           timeout: TimeInterval? = nil) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment(adding: extra)
        if let directory { process.currentDirectoryURL = directory }

        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input

        try process.run()

        var timedOut = false
        let timeoutBox = Box()
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { timeoutBox.data = Data([1]); process.terminate() }
            }
        }

        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if let stdin {
            DispatchQueue.global().async {
                input.fileHandleForWriting.write(Data(stdin.utf8))
                try? input.fileHandleForWriting.close()
            }
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timedOut = !timeoutBox.data.isEmpty

        return Output(status: process.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errBox.data, as: UTF8.self),
                      timedOut: timedOut)
    }
}
