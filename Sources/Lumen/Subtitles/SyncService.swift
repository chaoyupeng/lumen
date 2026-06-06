import Foundation

enum SyncError: LocalizedError {
    case toolNotInstalled
    case failed(String)
    case timedOut
    case noOutput

    var errorDescription: String? {
        switch self {
        case .toolNotInstalled:
            return "Install a sync tool: brew install alass (or pipx install ffsubsync)."
        case .failed(let msg):
            return msg
        case .timedOut:
            return "Sync timed out."
        case .noOutput:
            return "Sync produced no output."
        }
    }
}

/// Reference-free subtitle synchronization against the video's own audio.
/// Prefers alass (single Rust binary, offset + framerate correction); falls back
/// to ffsubsync if present.
enum SyncService {
    private enum Tool {
        case alass(String)
        case ffsubsync(String)
    }

    /// Helper binaries (alass, ffmpeg, ffprobe) bundled inside the .app.
    private static var bundledHelpersDir: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers").path
    }

    private static func locate(_ names: [String]) -> String? {
        // Bundled helpers first (shipped .app), then Homebrew.
        let dirs = [bundledHelpersDir, "/opt/homebrew/bin", "/usr/local/bin",
                    "/opt/homebrew/opt/ffsubsync/libexec/bin"]
        let fm = FileManager.default
        for dir in dirs {
            for name in names {
                let path = "\(dir)/\(name)"
                if fm.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    private static func resolveTool() -> Tool? {
        if let alass = locate(["alass-cli", "alass"]) { return .alass(alass) }
        if let ffs = locate(["ffs", "ffsubsync"]) { return .ffsubsync(ffs) }
        return nil
    }

    static var isAvailable: Bool { resolveTool() != nil }

    /// Sync `subtitlePath` against `videoPath`'s audio. Returns the path to the
    /// corrected subtitle file.
    static func sync(videoPath: String,
                     subtitlePath: String,
                     timeout: TimeInterval = 300) async throws -> String {
        guard let tool = resolveTool() else { throw SyncError.toolNotInstalled }

        let subURL = URL(fileURLWithPath: subtitlePath)
        let base = subURL.deletingPathExtension().lastPathComponent
        let outURL = subURL.deletingLastPathComponent()
            .appendingPathComponent("\(base).synced.srt")
        let outPath = outURL.path

        let executable: String
        let arguments: [String]
        var environment = ProcessInfo.processInfo.environment
        switch tool {
        case .alass(let path):
            executable = path
            arguments = [videoPath, subtitlePath, outPath]
            // Point alass at ffmpeg/ffprobe (bundled first, else system).
            if let ffmpeg = locate(["ffmpeg"]) { environment["ALASS_FFMPEG_PATH"] = ffmpeg }
            if let ffprobe = locate(["ffprobe"]) { environment["ALASS_FFPROBE_PATH"] = ffprobe }
        case .ffsubsync(let path):
            executable = path
            arguments = [videoPath, "-i", subtitlePath, "-o", outPath, "--vad", "auditok"]
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = environment
                let errPipe = Pipe()
                process.standardOutput = Pipe()
                process.standardError = errPipe

                var timedOut = false
                let killer = DispatchWorkItem {
                    if process.isRunning { timedOut = true; process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
                }

                do {
                    try process.run()
                } catch {
                    killer.cancel()
                    continuation.resume(throwing: SyncError.failed(error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                group.wait()
                killer.cancel()

                if timedOut { continuation.resume(throwing: SyncError.timedOut); return }
                guard process.terminationStatus == 0 else {
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: SyncError.failed("Sync failed. \(stderr.suffix(200))"))
                    return
                }
                guard FileManager.default.fileExists(atPath: outPath) else {
                    continuation.resume(throwing: SyncError.noOutput); return
                }
                continuation.resume(returning: outPath)
            }
        }
    }
}
