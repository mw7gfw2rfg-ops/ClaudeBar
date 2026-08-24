import Testing
import Foundation
@testable import ClaudeBarKit

/// A payload shaped exactly like the one Claude Code hands its status line, captured from a
/// real session. Anchoring the tests to the real schema is the point — a hand-invented shape
/// would let a field rename pass silently.
private let realPayload = """
{
  "session_id": "7ffccf5a-d73c-4bce-bdae-65d11e3ec312",
  "cwd": "/tmp/definitely-not-a-repo",
  "effort": {"level": "high"},
  "session_name": "Audit CS NEA",
  "model": {"id": "claude-sonnet-5", "display_name": "Sonnet 5"},
  "workspace": {"current_dir": "/tmp/definitely-not-a-repo",
                "repo": {"host": "github.com", "owner": "someone", "name": "agenticos"}},
  "version": "2.1.220",
  "output_style": {"name": "default"},
  "thinking": {"enabled": true},
  "fast_mode": false,
  "cost": {"total_cost_usd": 13.79, "total_lines_added": 1402, "total_lines_removed": 103},
  "context_window": {"total_input_tokens": 317216, "context_window_size": 1000000,
                     "used_percentage": 32},
  "rate_limits": {"five_hour": {"used_percentage": 36, "resets_at": 1787608800},
                  "seven_day": {"used_percentage": 13, "resets_at": 1788127200}}
}
""".data(using: .utf8)!

private func parse(_ data: Data = realPayload, capturedAt: Date = Date()) throws -> UsageSnapshot {
    // Git lookup stubbed out: these tests are about parsing, not about subprocesses.
    try UsageReader.parse(data, capturedAt: capturedAt, branch: { _ in nil })
}

// MARK: - Parsing the real schema

@Test
func parsesRateLimitsAsFractions() throws {
    let snapshot = try parse()
    #expect(abs(snapshot.fiveHour.used - 0.36) < 1e-9)
    #expect(abs(snapshot.sevenDay.used - 0.13) < 1e-9)
}

@Test
func parsesContextAndFormatsItCompactly() throws {
    let snapshot = try parse()
    #expect(snapshot.contextUsedTokens == 317_216)
    #expect(snapshot.contextWindowTokens == 1_000_000)
    #expect(snapshot.contextText == "317.2k / 1.0M")
    #expect(abs(snapshot.contextUsed - 0.317216) < 1e-6)
}

@Test
func parsesSessionMetadata() throws {
    let snapshot = try parse()
    #expect(snapshot.modelName == "Sonnet 5")
    #expect(snapshot.version == "2.1.220")
    #expect(snapshot.effort == "high")
    #expect(snapshot.thinking == true)
    #expect(snapshot.fastMode == false)
    #expect(snapshot.outputStyle == "default")
    #expect(snapshot.linesAdded == 1402)
    #expect(snapshot.linesRemoved == 103)
    #expect(snapshot.project == "agenticos", "repo name is preferred over the directory")
}

@Test
func fallsBackToTheDirectoryWhenThereIsNoRepo() throws {
    let data = """
    {"cwd": "/Users/x/Developer/SomeProject", "workspace": {}}
    """.data(using: .utf8)!
    #expect(try parse(data).project == "SomeProject")
}

@Test
func missingFieldsDegradeToPlaceholdersRatherThanFailing() throws {
    // Claude Code's schema has grown over time; an older build simply won't send some keys.
    // One missing field must not cost the whole readout.
    let snapshot = try parse("{}".data(using: .utf8)!)
    #expect(snapshot.fiveHour.used == 0)
    #expect(snapshot.modelName == "—")
    #expect(snapshot.version == "—")
    #expect(snapshot.contextWindowTokens == 0)
    #expect(snapshot.contextUsed == 0, "a zero window must not divide by zero")
}

@Test
func malformedPayloadThrowsRatherThanReturningZeroes() {
    // Silently reporting 0% used would be the worst possible failure mode for this app.
    #expect(throws: (any Error).self) {
        try parse("not json at all".data(using: .utf8)!)
    }
}

// MARK: - Reset countdowns

@Test
func resetTextCountsDownInTheRightUnits() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func text(_ seconds: TimeInterval) -> String {
        LimitWindow(used: 0.5, resetsAt: now.addingTimeInterval(seconds)).resetText(now: now)
    }
    #expect(text(4 * 3600 + 18 * 60) == "4h18m")
    #expect(text(6 * 86_400 + 4 * 3600) == "6d04h")
    #expect(text(90) == "1m")
    #expect(text(-5) == "now", "an elapsed window reads as now, never as negative")
}

@Test
func resetTextIsADashWhenNoResetWasProvided() {
    #expect(LimitWindow(used: 0.5, resetsAt: nil).resetText() == "—")
}

// MARK: - Staleness
//
// The payload refreshes about once a second while Claude Code is open. Presenting a leftover
// reading as if it were current is the one lie this app must not tell.

@Test
func freshnessIsJudgedFromTheFilesModificationTime() throws {
    let now = Date()
    let fresh = try parse(capturedAt: now.addingTimeInterval(-2))
    #expect(fresh.isLive(now: now))
    #expect(fresh.statusText(now: now) == "LIVE")

    let stale = try parse(capturedAt: now.addingTimeInterval(-45))
    #expect(!stale.isLive(now: now))
    #expect(stale.statusText(now: now) == "45S AGO")

    let old = try parse(capturedAt: now.addingTimeInterval(-7200))
    #expect(old.statusText(now: now) == "IDLE")
}

// MARK: - Headline

@Test
func headlineIsAlwaysTheFiveHourWindow() throws {
    // Not the larger of the two: a glance value that silently switches which window it means
    // would be worse than useless.
    let data = """
    {"rate_limits": {"five_hour": {"used_percentage": 12},
                     "seven_day": {"used_percentage": 88}}}
    """.data(using: .utf8)!
    #expect(try parse(data).headlineText == "12%")
}

@Test
func headlineRendersInTheDotMatrixCharacterSet() throws {
    // The menu bar draws this through GlassKit's glyph table, which has digits and `%` and
    // nothing else. A headline containing anything else would silently render as gaps.
    let allowed = Set("0123456789% ")
    for percent in [0, 7, 36, 100] {
        let data = """
        {"rate_limits": {"five_hour": {"used_percentage": \(percent)}}}
        """.data(using: .utf8)!
        let text = try parse(data).headlineText
        #expect(text.allSatisfy { allowed.contains($0) }, "\(text) has unrenderable characters")
    }
}

@Test
func compactTokenFormatting() {
    #expect(UsageSnapshot.compact(0) == "0")
    #expect(UsageSnapshot.compact(999) == "999")
    #expect(UsageSnapshot.compact(1_500) == "1.5k")
    #expect(UsageSnapshot.compact(317_216) == "317.2k")
    #expect(UsageSnapshot.compact(1_000_000) == "1.0M")
}

// MARK: - Reader

@Test @MainActor
func readerReportsAMissingPayloadRatherThanInventingOne() {
    let missing = URL(fileURLWithPath: "/tmp/claudebar-does-not-exist-\(UUID().uuidString).json")
    let reader = UsageReader(fileURL: missing)
    reader.refresh()
    #expect(reader.snapshot == nil)
    #expect(reader.lastError != nil)
}

@Test @MainActor
func readerLoadsARealPayloadFromDisk() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("claudebar-\(UUID().uuidString).json")
    try realPayload.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let reader = UsageReader(fileURL: url)
    reader.refresh()
    #expect(reader.lastError == nil)
    #expect(reader.snapshot?.modelName == "Sonnet 5")
    #expect(reader.snapshot?.headlineText == "36%")
}
