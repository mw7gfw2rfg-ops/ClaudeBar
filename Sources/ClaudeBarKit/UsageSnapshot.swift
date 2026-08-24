import Foundation

/// One rate-limit window.
public struct LimitWindow: Sendable, Equatable {
    /// 0...1, from Claude Code's own `used_percentage`.
    public let used: Double
    /// When the window rolls over. Absolute, so the countdown stays correct across sleep.
    public let resetsAt: Date?

    public init(used: Double, resetsAt: Date?) {
        self.used = used
        self.resetsAt = resetsAt
    }

    /// `4h18m`, `6d04h`, or `—` if we weren't told.
    public func resetText(now: Date = Date()) -> String {
        guard let resetsAt else { return "—" }
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return String(format: "%dd%02dh", days, hours) }
        if hours > 0 { return "\(hours)h\(String(format: "%02d", minutes))m" }
        return "\(minutes)m"
    }
}

/// Everything the menu bar shows, as of one reading.
public struct UsageSnapshot: Sendable, Equatable {
    public let fiveHour: LimitWindow
    public let sevenDay: LimitWindow

    public let contextUsedTokens: Int
    public let contextWindowTokens: Int

    public let modelName: String
    public let version: String
    public let effort: String
    public let thinking: Bool
    public let fastMode: Bool
    public let outputStyle: String

    public let project: String
    public let linesAdded: Int
    public let linesRemoved: Int

    /// When the underlying payload was last written. Used to decide whether these numbers
    /// are live or a leftover from a Claude Code window that has since closed.
    public let capturedAt: Date

    public init(fiveHour: LimitWindow, sevenDay: LimitWindow,
                contextUsedTokens: Int, contextWindowTokens: Int,
                modelName: String, version: String, effort: String,
                thinking: Bool, fastMode: Bool, outputStyle: String,
                project: String, linesAdded: Int, linesRemoved: Int,
                capturedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.contextUsedTokens = contextUsedTokens
        self.contextWindowTokens = contextWindowTokens
        self.modelName = modelName
        self.version = version
        self.effort = effort
        self.thinking = thinking
        self.fastMode = fastMode
        self.outputStyle = outputStyle
        self.project = project
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.capturedAt = capturedAt
    }

    public var contextUsed: Double {
        guard contextWindowTokens > 0 else { return 0 }
        return min(1, Double(contextUsedTokens) / Double(contextWindowTokens))
    }

    /// `317.0k / 1.0M`
    public var contextText: String {
        "\(Self.compact(contextUsedTokens)) / \(Self.compact(contextWindowTokens))"
    }

    static func compact(_ tokens: Int) -> String {
        switch tokens {
        case ..<1_000: "\(tokens)"
        case ..<1_000_000: String(format: "%.1fk", Double(tokens) / 1_000)
        default: String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }

    /// The number the menu bar shows.
    ///
    /// Deliberately the 5-hour window, not the larger of the two: the 5-hour limit is the one
    /// that actually stops you mid-session, and a glance value that silently switches which
    /// window it means would be worse than useless. The 7-day figure is in the panel, where
    /// it's labelled.
    public var headlineText: String { "\(Int((fiveHour.used * 100).rounded()))%" }

    /// How stale the reading is. The payload is refreshed every second while Claude Code is
    /// open, so anything older than a few seconds means nothing is running — and presenting
    /// a leftover reading as live would be a lie.
    public func age(now: Date = Date()) -> TimeInterval { now.timeIntervalSince(capturedAt) }

    public func isLive(now: Date = Date()) -> Bool { age(now: now) < 10 }

    public func statusText(now: Date = Date()) -> String {
        let seconds = Int(age(now: now))
        if seconds < 10 { return "LIVE" }
        if seconds < 60 { return "\(seconds)S AGO" }
        if seconds < 3600 { return "\(seconds / 60)M AGO" }
        return "IDLE"
    }
}
