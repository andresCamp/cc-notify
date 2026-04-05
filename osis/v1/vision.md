# Vision

## North Star

Every developer running parallel AI agent sessions knows exactly which one needs them, instantly, without checking each tab.

## Problem

Developers running 10-20+ Claude Code sessions in parallel across terminal tabs lose significant time because they have no way to know which session needs them. The bottleneck is not the AI thinking -- it is the human noticing. Every minute a session waits for approval or input is a minute of wasted compute and developer flow.

## Insight

The terminal is invisible by design. Terminals do not surface state from background tabs. But CLI agents have a clear, finite set of states (working, done, needs input) and the operating system already has the primitives to observe and surface them. The missing piece is not monitoring infrastructure -- it is a fast, keyboard-native switcher that treats agent sessions as first-class objects.

## Name

Overstory. The overstory is the highest layer of the forest canopy -- the layer that sees everything below. Overstory sits above all your terminal sessions, sees their state, and lets you reach any one of them instantly.

## Solution

A lightweight macOS app with a floating panel as the primary interface. A global hotkey opens and closes the panel -- like Cmd+Tab, but for agent sessions. The panel shows session cards, each with the CC title (from the Ghostty terminal name), directory, status, and a unique visual identity (a gradient derived from the title). Arrow keys and Enter to navigate. Hovering a card previews the window by focusing it. Selecting a card dismisses the panel and focuses the correct terminal.

Session detection uses polling as the baseline (pgrep to find claude processes, Ghostty AppleScript to get window/tab context). Hooks provide richer status data on top of that baseline.

## Principles

1. **Invisible until needed.** The app has zero presence until a session needs attention. No persistent windows, no dock icon, no interruptions unless something is actionable.

2. **Keyboard-native.** The primary interaction is hotkey, arrow keys, Enter. Mouse is supported but secondary. The interaction model is Cmd+Tab, not a dashboard.

3. **Zero configuration.** It works out of the box. Polling detects sessions automatically. Hooks make status richer, but the app is useful without them. No config files to edit, no agents to install per-project.

4. **The floating panel is primary.** The panel is the interface. The menubar is secondary and ambient -- a badge and session count, not the main interaction path.

5. **Terminal-agnostic thinking, terminal-specific execution.** The architecture assumes multiple terminals from day one. Adapters handle the differences. New terminal support is additive, not architectural. Ghostty-first for v1.

6. **CC-first, multi-agent future.** v1 is built for Claude Code. The architecture accommodates any CLI agent. The product grows from CC switcher to universal CLI agent switcher.

7. **Supplement, don't replace.** This is not a terminal multiplexer or a process manager. It tells you where to go. The terminal does the rest.

## Audience

Developers who run multiple Claude Code sessions simultaneously across terminal tabs and windows. Power users of CLI-based AI agents who work on several projects or branches in parallel. macOS users (the first platform) running Ghostty (the first terminal).

## Success

- Developers stop manually cycling through terminal tabs to find the session that needs them.
- The time between "Claude needs approval" and the developer responding drops from minutes to seconds.
- Developers run more parallel sessions because the coordination cost has disappeared.
- The app becomes muscle memory -- hotkey, glance, Enter -- the same way Cmd+Tab is muscle memory for app switching.
