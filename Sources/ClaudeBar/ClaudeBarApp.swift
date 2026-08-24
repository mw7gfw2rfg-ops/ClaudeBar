import AppKit
import SwiftUI
import GlassKit
import ClaudeBarKit

/// Entry point.
///
/// Compare with PomoDot's: the same shape, because both apps inherit the whole menu bar
/// lifecycle from GlassKit. The only app-specific parts are what to draw and what to read.
@main
enum ClaudeBarMain {
    static func main() {
        MenuBarAppDelegate.run(AppDelegate())
    }
}

@MainActor
final class AppDelegate: MenuBarAppDelegate {

    private let reader = UsageReader()

    override var napReason: String { "Usage readout must keep refreshing" }
    /// 2s rather than 1s: the payload itself only changes about once a second, and a menu
    /// bar readout of a percentage doesn't need to be tighter than its own source.
    override var tickInterval: TimeInterval { 2.0 }

    override func makeController() -> MenuBarController {
        reader.refresh()

        let controller = MenuBarController(
            statusItem: { [unowned self] in
                guard let snapshot = reader.snapshot else {
                    // No session: a dash rather than a stale or invented number.
                    return StatusItemRenderer.image(text: "--", progress: 0, running: false)
                }
                return StatusItemRenderer.image(
                    text: snapshot.headlineText,
                    progress: snapshot.fiveHour.used,
                    running: true,
                    // Dim the whole item when the reading has gone stale, so the menu bar
                    // never presents a leftover number as if it were current.
                    dimmed: !snapshot.isLive()
                )
            },
            panel: { [unowned self] in
                AnyView(ClaudeBarPanel(reader: reader, onQuit: { NSApp.terminate(nil) }))
            }
        )

        controller.onTick = { [unowned self] in reader.refresh() }
        return controller
    }
}
