# Vision

## North Star

Every developer running parallel AI agent sessions knows exactly which one needs them, instantly, without checking each tab.

## Problem

Developers running 10-20+ Claude Code sessions in parallel across terminal tabs lose significant time because they have no way to know which session needs them. The bottleneck is not the AI thinking -- it is the human noticing. Every minute a session waits for approval or input is a minute of wasted compute and developer flow.

## Insight

The terminal is invisible by design. Terminals do not surface state from background tabs. But CLI agents have a clear, finite set of states (working, done, needs input) and the operating system already has the primitives to observe and surface them. The missing piece is not monitoring infrastructure -- it is a fast, keyboard-native switcher that treats agent sessions as first-class objects.

## Solution

A lightweight macOS app that detects all running CLI agent sessions, shows their status in the menubar, and on a global hotkey opens a floating panel of session cards. Each card shows the agent, directory, and status at a glance. Arrow keys and Enter to navigate. The panel disappears on selection, focusing the correct terminal window -- like Cmd+Tab, but for agent sessions.

## Principles

1. **Invisible until needed.** The app should have zero presence until a session needs attention. No persistent windows, no dock icon, no interruptions unless something is actionable.

2. **Keyboard-native.** The primary interaction is hotkey, arrow keys, Enter. Mouse is supported but secondary. The interaction model is Cmd+Tab, not a dashboard.

3. **Zero configuration.** It works out of the box. Hooks make it richer, but polling provides the baseline. No config files to edit, no agents to install per-project.

4. **Terminal-agnostic thinking, terminal-specific execution.** The architecture assumes multiple terminals from day one. Adapters handle the differences. New terminal support is additive, not architectural.

5. **Supplement, don't replace.** This is not a terminal multiplexer or a process manager. It tells you where to go. The terminal does the rest.

## Audience

Developers who run multiple Claude Code sessions simultaneously across terminal tabs and windows. Power users of CLI-based AI agents who work on several projects or branches in parallel. macOS users (the first platform) running Ghostty (the first terminal).

## Success

- Developers stop manually cycling through terminal tabs to find the session that needs them.
- The time between "Claude needs approval" and the developer responding drops from minutes to seconds.
- Developers run more parallel sessions because the coordination cost has disappeared.
- The app becomes muscle memory -- hotkey, glance, Enter -- the same way Cmd+Tab is muscle memory for app switching.
