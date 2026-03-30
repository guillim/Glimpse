# Menu Bar Agent List

## Overview

Rework the menu bar dropdown to list all active agent sessions with their current activity state, and surface a bell icon + orange badge dot when any agent is in the `asking` state.

## Current State

The menu bar is minimal: a single `NSStatusItem` with a static `photo.on.rectangle` icon and an `NSMenu` containing only an "Exit" item. All session visualization lives in the SpriteKit desktop overlay.

## Design

### Menu Bar Icon

- Keep the existing `photo.on.rectangle` SF Symbol as the base icon.
- When **any** active session has `activity == .asking`, overlay a small orange dot (badge) on the icon — similar to notification badges on macOS dock icons.
- When no session is asking, show the icon without the badge.
- The badge state updates on each SessionMonitor poll cycle (every 2 seconds).

### Dropdown Menu Structure

```
┌──────────────────────────────────┐
│ background        writing        │
│ my-api            thinking       │
│ frontend-app      asking    🔔  │
│ ──────────────────────────────── │
│ Exit                             │
└──────────────────────────────────┘
```

Each active session is a menu item with:
- **Left side:** project name (from `Session.projectName`)
- **Right side:** activity label (lowercase string from `Session.activity`) — colored orange when asking, gray otherwise
- **Far right:** bell symbol (🔔) shown only when `activity == .asking`

Sessions are separated from the "Exit" item by a separator.

### Empty State

When no sessions are active, show a single disabled menu item:

```
┌──────────────────────────────────┐
│ No agents active           (dim) │
│ ──────────────────────────────── │
│ Exit                             │
└──────────────────────────────────┘
```

### Click Behavior

Clicking a session menu item activates the parent application (Terminal, Cursor, etc.) for that session — reusing the same activation logic already in `AgentMonitorScene` / `CharacterNode`.

### Update Mechanism

The menu is rebuilt each time `SessionMonitor.sessions` changes (on its existing 2-second polling interval). This means:
- Menu items are regenerated from the current session list on each poll.
- The menu bar icon badge is recalculated (any session asking → badge on, none asking → badge off).

## Implementation Notes

### NSMenu with Attributed Strings

Use `NSAttributedString` on each `NSMenuItem` to render the project name and activity label with different styles/colors in a single menu item. The bell can be appended as part of the attributed string or via the menu item's `image` property.

### Orange Dot Badge on NSStatusItem

Compose the badge by drawing the base SF Symbol into an `NSImage`, then drawing a small filled orange circle at the top-right corner. Swap the button's image between badged and un-badged versions based on asking state.

### Click-to-Activate

Each session menu item's action should call the same activation logic used by the desktop overlay:
- For Claude Code sessions: activate Terminal.app (or iTerm, etc.) via `NSWorkspace`
- For Cursor sessions: activate the Cursor app

Store the session ID or necessary info in the menu item's `representedObject` to identify which session was clicked.

### Ordering

List sessions in the same order as `SessionMonitor.sessions` (by `lastModified`, most recent first).

## Scope

- Modify `AppDelegate.setupMenuBarItem()` to build the dynamic menu
- Add a method to rebuild the menu on session changes (subscribe to SessionMonitor updates or rebuild in the poll callback)
- Add badge compositing logic for the status item icon
- Wire click actions to session activation

## Out of Scope

- Submenus or expandable details per session
- Showing topics in the menu
- Source badges (Claude Code vs Cursor)
- Sound or system notifications for asking state
