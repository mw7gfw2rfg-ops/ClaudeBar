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

    /// Slow by default, fast while the panel is open.
    ///
    /// The menu bar shows a whole-number percentage that moves a few times an hour, so
    /// re-reading a file every second to redraw it is pure energy cost — the sort of thing
    /// that earns a menu bar app a reputation for flattening batteries. The panel shows a
    /// live countdown and does want a fast tick, but only while you're looking at it.
    override var tickInterval: TimeInterval { Self.idleInterval }

    private static let idleInterval: TimeInterval = 15
    private static let openInterval: TimeInterval = 1

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
        controller.onPanelVisibilityChanged = { [weak controller] isOpen in
            controller?.setTickInterval(isOpen ? Self.openInterval : Self.idleInterval)
        }
        return controller
    }
}
