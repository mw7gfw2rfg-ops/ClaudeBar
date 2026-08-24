# ClaudeBar

Claude Code usage and limits in the macOS menu bar, in [GlassKit](../GlassKit)'s visual
language.

![the panel](docs/panel.png)

The menu bar shows your 5-hour usage as dot-matrix numerals with a progress hairline. Click
it for the full readout: both rate-limit windows with reset countdowns, context window usage,
and the current session's model, project, branch, diff and flags.

## Install

Requires macOS 26+ and the `claude-statusbar` status line (see *Where the data comes from*).

```bash
./build.sh release
open build/ClaudeBar.app
```

## Where the data comes from

Claude Code passes its status line a JSON payload on stdin every tick, containing rate
limits, context usage, model, version and session state. `claude-statusbar` caches that
payload verbatim to `~/.cache/claude-statusbar/last_stdin.json` and rewrites it roughly once
a second while any Claude Code window is open.

So the numbers are already on disk: first-party, structured, and fresh. ClaudeBar reads that
file. It does **not** reimplement usage tracking, scrape transcripts, or call an API —
inventing a second source of truth could only ever be less correct than Claude Code's own.

```
rate_limits.five_hour.used_percentage   →  the headline number
rate_limits.five_hour.resets_at         →  the countdown (epoch, so it survives sleep)
context_window.total_input_tokens       →  517.9k
context_window.context_window_size      →  / 1.0M
model.display_name                      →  Opus 5
workspace.repo.name + git               →  agenticos ⎇ main●
cost.total_lines_added / _removed       →  +5052 −333
effort.level, thinking, fast_mode       →  HIGH · THINK ON · FAST OFF
```

Set `CLAUDEBAR_PAYLOAD` to point at a different file.

## Design notes

**It never presents a stale reading as live.** The payload refreshes about once a second
while Claude Code is open; freshness is judged from the file's modification time, not from
when we happened to read it. Over ten seconds old and the header switches from `LIVE` to
`45S AGO` / `IDLE`, and the menu bar item dims. Showing a leftover number as current is the
one lie this app must not tell — and quietly reporting `0%` on a malformed payload would be
worse, so parsing throws rather than defaulting.

**The headline is always the 5-hour window**, never the larger of the two. The 5-hour limit
is the one that actually stops you mid-session, and a glance value that silently switched
which window it meant would be worse than useless. The 7-day figure is in the panel, labelled.

**With several Claude Code windows open, the payload is whichever ticked most recently.**
Rate limits are account-wide so they're always correct; the session rows show whichever
window last reported, labelled with its project so it's never ambiguous. This matches how the
status line itself behaves.

**Missing fields degrade, malformed payloads don't.** Claude Code's schema has grown over
time and an older build won't send some keys, so each field falls back to a placeholder
independently. A payload that isn't valid JSON at all is a different matter and throws.

**Git is cached for 15 seconds.** Two subprocesses per tick to learn something that changes a
few times a day would be silly.

## Layout

```
Sources/ClaudeBarKit/
  UsageSnapshot.swift   the model, formatting, and freshness rules
  UsageReader.swift     reads and parses the payload; caches git lookups
  ClaudeBarPanel.swift  the panel — composition only, no design code
Sources/ClaudeBar/
  ClaudeBarApp.swift    ~50 lines; everything else comes from GlassKit
Tests/                  14 tests, anchored to a real captured payload
```

## Tests

```bash
swift test
```

The test fixture is a real payload captured from a live session rather than a hand-invented
shape, so a field rename upstream fails the suite instead of silently zeroing the display.
