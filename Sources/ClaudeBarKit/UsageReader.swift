import Foundation
import Observation

/// Reads the payload Claude Code hands its status line.
///
/// **Why this file and not an API call:** Claude Code passes its status line a JSON blob on
/// stdin every tick containing rate limits, context usage, model, version and session state.
/// `claude-statusbar` caches that blob verbatim to `~/.cache/claude-statusbar/last_stdin.json`
/// and rewrites it roughly once a second while any Claude Code window is open. So the numbers
/// are already on disk, first-party, and fresh — reimplementing usage tracking would be
/// inventing a second source of truth that could only ever be less correct than this one.
///
/// The dependency is therefore on that cache file existing, which is worth stating plainly:
/// if the status line is switched to a tool that doesn't write it, this app goes stale and
/// says so rather than guessing.
@Observable
@MainActor
public final class UsageReader {

    public private(set) var snapshot: UsageSnapshot?
    /// Set when the payload exists but couldn't be understood — surfaced rather than swallowed.
    public private(set) var lastError: String?

    private let fileURL: URL
    /// Branch lookups shell out to git, so they're cached rather than run at 1 Hz.
    private var branchCache: (path: String, branch: String, dirty: Bool, at: Date)?

    public static func defaultPayloadURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDEBAR_PAYLOAD"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/claude-statusbar/last_stdin.json")
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultPayloadURL()
    }

    /// Re-reads the payload. Cheap: a couple of KB and one JSON parse.
    public func refresh(now: Date = Date()) {
        guard let data = try? Data(contentsOf: fileURL) else {
            lastError = "no payload at \(fileURL.lastPathComponent)"
            return
        }
        // Modification time, not "now": the reading is as fresh as the file, and treating a
        // leftover payload as current is exactly the failure this app must not have.
        let captured = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? now

        do {
            snapshot = try Self.parse(data, capturedAt: captured, branch: branch(for:))
            lastError = nil
        } catch {
            lastError = "unreadable payload"
        }
    }

    // MARK: - Parsing

    nonisolated struct ParseFailure: Error {}

    /// Decodes the payload. Every field is optional in practice — Claude Code's schema has
    /// grown over time and an older build simply won't send some of these — so each one
    /// degrades to a placeholder rather than failing the whole read.
    nonisolated static func parse(_ data: Data,
                      capturedAt: Date,
                      branch: (String) -> (name: String, dirty: Bool)?) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseFailure()
        }

        func dict(_ key: String, in parent: [String: Any]) -> [String: Any] {
            parent[key] as? [String: Any] ?? [:]
        }

        let limits = dict("rate_limits", in: root)
        func window(_ key: String) -> LimitWindow {
            let raw = dict(key, in: limits)
            let percent = (raw["used_percentage"] as? NSNumber)?.doubleValue ?? 0
            let resets = (raw["resets_at"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue)
            }
            return LimitWindow(used: min(1, max(0, percent / 100)), resetsAt: resets)
        }

        let context = dict("context_window", in: root)
        let model = dict("model", in: root)
        let cost = dict("cost", in: root)
        let workspace = dict("workspace", in: root)
        let repo = dict("repo", in: workspace)

        let cwd = (root["cwd"] as? String) ?? (workspace["current_dir"] as? String) ?? ""
        // Prefer the repo name; fall back to the directory, which is what you'd call it anyway.
        let project = (repo["name"] as? String)
            ?? (cwd.isEmpty ? "—" : URL(fileURLWithPath: cwd).lastPathComponent)

        let git = cwd.isEmpty ? nil : branch(cwd)

        return UsageSnapshot(
            fiveHour: window("five_hour"),
            sevenDay: window("seven_day"),
            contextUsedTokens: (context["total_input_tokens"] as? NSNumber)?.intValue ?? 0,
            contextWindowTokens: (context["context_window_size"] as? NSNumber)?.intValue ?? 0,
            modelName: (model["display_name"] as? String) ?? "—",
            version: (root["version"] as? String) ?? "—",
            effort: (dict("effort", in: root)["level"] as? String) ?? "—",
            thinking: (dict("thinking", in: root)["enabled"] as? Bool) ?? false,
            fastMode: (root["fast_mode"] as? Bool) ?? false,
            outputStyle: (dict("output_style", in: root)["name"] as? String) ?? "—",
            project: git.map { "\(project)  ⎇ \($0.name)\($0.dirty ? "●" : "")" } ?? project,
            linesAdded: (cost["total_lines_added"] as? NSNumber)?.intValue ?? 0,
            linesRemoved: (cost["total_lines_removed"] as? NSNumber)?.intValue ?? 0,
            capturedAt: capturedAt
        )
    }

    // MARK: - Git

    /// Branch + dirty flag for a working directory, cached for 15 seconds.
    ///
    /// Two `git` subprocesses at 1 Hz would be a silly amount of work to learn something that
    /// changes a few times a day.
    private func branch(for path: String) -> (name: String, dirty: Bool)? {
        if let cache = branchCache, cache.path == path, Date().timeIntervalSince(cache.at) < 15 {
            return (cache.branch, cache.dirty)
        }
        guard let name = Self.git(["rev-parse", "--abbrev-ref", "HEAD"], in: path),
              !name.isEmpty else { return nil }
        let dirty = !(Self.git(["status", "--porcelain"], in: path) ?? "").isEmpty
        branchCache = (path, name, dirty, Date())
        return (name, dirty)
    }

    nonisolated static func git(_ arguments: [String], in path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
