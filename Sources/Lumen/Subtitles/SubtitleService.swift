import Foundation

struct SubtitleResult: Decodable {
    let language: String
    let provider: String?
    let path: String?
}

private struct SubdlOutput: Decodable {
    let results: [SubtitleResult]
    let listed: Int?
    let error: String?
}

/// Outcome of a download attempt. `listed` is how many candidates were found
/// across providers; if `results` is empty but `listed > 0`, the search worked
/// but downloads were blocked (needs an OpenSubtitles.com account).
struct DownloadOutcome {
    let results: [SubtitleResult]
    let listed: Int
}

enum SubtitleError: LocalizedError {
    case subliminalNotInstalled
    case scriptMissing
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .subliminalNotInstalled:
            return "subliminal isn't installed. Run: brew install subliminal"
        case .scriptMissing:
            return "Internal error: subtitle downloader script is missing."
        case .timedOut:
            return "Subtitle service timed out. Try again."
        case .failed(let msg):
            return msg
        }
    }
}

/// Drives the bundled subdl.py via the subliminal venv interpreter to download
/// subtitles with key-free providers. No API key required.
enum SubtitleService {
    /// Resolve the Python interpreter that has subliminal available, by reading
    /// the subliminal launcher's shebang, with a version-agnostic fallback.
    static func resolveInterpreter() -> String? {
        let fm = FileManager.default
        let launchers = ["/opt/homebrew/bin/subliminal", "/usr/local/bin/subliminal"]
        for launcher in launchers where fm.isExecutableFile(atPath: launcher) {
            if let line = try? String(contentsOfFile: launcher, encoding: .utf8)
                .split(separator: "\n", maxSplits: 1).first,
               line.hasPrefix("#!") {
                let interp = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if fm.isExecutableFile(atPath: interp) { return interp }
            }
        }
        // Version-agnostic Homebrew opt path.
        let fallback = "/opt/homebrew/opt/subliminal/libexec/bin/python"
        return fm.isExecutableFile(atPath: fallback) ? fallback : nil
    }

    static var isAvailable: Bool { resolveInterpreter() != nil }

    enum VerifyResult {
        case success
        case failure(String)
    }

    private struct VerifyOutput: Decodable {
        let ok: Bool
        let error: String?
    }

    /// Verify OpenSubtitles.com credentials by attempting a login.
    static func verifyAccount(username: String, password: String, apiKey: String) async -> VerifyResult {
        guard let interpreter = resolveInterpreter() else { return .failure(SubtitleError.subliminalNotInstalled.errorDescription!) }
        guard let script = scriptURL() else { return .failure("Internal error: downloader missing.") }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: interpreter)
                process.arguments = [script.path, "--verify"]
                var env = ProcessInfo.processInfo.environment
                env["OS_USERNAME"] = username
                env["OS_PASSWORD"] = password
                if !apiKey.isEmpty { env["OS_APIKEY"] = apiKey }
                process.environment = env

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription)); return
                }
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard let out = try? JSONDecoder().decode(VerifyOutput.self, from: data) else {
                    continuation.resume(returning: .failure("Could not verify (unexpected output)."))
                    return
                }
                continuation.resume(returning: out.ok ? .success : .failure(out.error ?? "Login failed."))
            }
        }
    }

    private static func scriptURL() -> URL? {
        Bundle.module.url(forResource: "subdl", withExtension: "py")
    }

    /// Download subtitles for `videoPath` in the given IETF languages.
    /// Returns the saved subtitle results (possibly empty if none found).
    /// OpenSubtitles.com credentials entered in Settings, passed to subdl.py.
    private static func credentialEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        if let u = defaults.string(forKey: "osUsername"), !u.isEmpty { env["OS_USERNAME"] = u }
        if let p = defaults.string(forKey: "osPassword"), !p.isEmpty { env["OS_PASSWORD"] = p }
        if let k = defaults.string(forKey: "osApiKey"), !k.isEmpty { env["OS_APIKEY"] = k }
        return env
    }

    static func download(videoPath: String,
                         languages: [String],
                         timeout: TimeInterval = 90) async throws -> DownloadOutcome {
        guard let interpreter = resolveInterpreter() else { throw SubtitleError.subliminalNotInstalled }
        guard let script = scriptURL() else { throw SubtitleError.scriptMissing }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: interpreter)
                process.arguments = [script.path, videoPath] + languages
                process.environment = credentialEnvironment()

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var timedOut = false
                let killer = DispatchWorkItem {
                    if process.isRunning { timedOut = true; process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                // Read both pipes concurrently to avoid a full-buffer deadlock.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
                }

                do {
                    try process.run()
                } catch {
                    killer.cancel()
                    continuation.resume(throwing: SubtitleError.failed(error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                group.wait()
                killer.cancel()

                if timedOut {
                    continuation.resume(throwing: SubtitleError.timedOut)
                    return
                }

                guard let output = try? JSONDecoder().decode(SubdlOutput.self, from: outData) else {
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: SubtitleError.failed(
                        "Unexpected downloader output. \(stderr.suffix(200))"))
                    return
                }
                if let error = output.error {
                    continuation.resume(throwing: SubtitleError.failed(error))
                    return
                }
                continuation.resume(returning: DownloadOutcome(results: output.results,
                                                               listed: output.listed ?? 0))
            }
        }
    }
}
