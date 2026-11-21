# Docket

A menu bar task manager for macOS: tasks for three companies plus personal
work, always one click (or one shortcut) away. Built with Flutter for the
interface and Swift/AppKit for everything that has to be native.

## Using it

| | |
|---|---|
| Click the ✓ icon in the menu bar | Open / close Docket |
| **⌃⌥T** (anywhere) | Open / close Docket |
| **⌃⌥N** (anywhere) | Quick Add: type, ⇥ to change company, ↵ to save |
| Right-click the icon | Quick Add, Settings, Quit |
| ⌘N / ⌘F / ⌘↵ | New task / Search / Complete the task under the pointer |
| ⌘1 / ⌘2 / ⌘3 / ⌘0 | All tasks / Today / Overdue / Home |
| ⌘[ / esc / ⌘, | Back / Close / Settings |

In any add field, `!` makes a task urgent and `#word` adds a tag.
The circle in front of a task moves one step per click: to do → **in
progress** (half circle) → **done** (✓); clicking a done task reopens it.
Hovering shows what the next click does; ⌘↵ still completes in one go.
A task you start stays where it is (on a company's To Do tab it moves to the
In Progress group at the top). Completing a task keeps it in the list: it moves to a *Completed* group at the
bottom, ticked and crossed out (a company's lists keep its newest 10, the
Today/Urgent/Overdue lists keep what was finished today). Untick to reopen.
Settings › Menu Bar › *Keep completed tasks in lists* turns this off.
⌘-click selects several tasks, ⇧-click selects a range.
Global shortcuts can be changed in Settings; Docket refuses combinations
that macOS or another app already uses.

## Display modes

Settings › Appearance › Display mode:

| Mode | What it is |
|---|---|
| Small | 360×500 drop-down: summary, urgent tasks, quick add |
| Normal | 400×640 drop-down (default): companies, today |
| Large | 520×820 drop-down: more rows, descriptions, In Progress |
| Curtain | Full-width glass sheet that slides down from the menu bar |

The curtain is its own layout: top bar (date, urgent/overdue/today/open,
search, new task), a sidebar to switch between the overview, smart lists and
each company, one column per company (or To Do / In Progress / Completed for a
single company), and a side pane for editing a task. Drag a card to another
column to change its status or company. Other screens open as sheets over the
glass; esc closes a sheet first, then the curtain.

The glass is a native `NSVisualEffectView` behind a transparent Flutter view.
Transparency (the tint drawn by Flutter), blur (the effect view's opacity),
height, light/dark glass and the slide animation apply live while you drag the
sliders. The curtain opens on the display under the pointer and follows
resolution changes.

### Session list

The curtain's end edge (left in Arabic) holds the **session list**: what you
plan to do in this sitting — an hour, two, or the day. It is separate from
company tasks: its own `session_items` table, no dates or reminders, not
counted in the summary or the menu bar badge. Write a line and press ↵. Its
circle works like a task's: one click marks what you're on now (listed first,
tinted), a second marks it done (stays at the bottom, crossed out), a third
reopens it. Click a line to rename it. The
header shows done/total, when the session started (the first line written)
and how long it has run. ⋯ › *New session* empties the list, *Clear
completed* removes only the ticked lines; both can be undone. The ⚡ button
in the top bar shows or hides the list. It needs a curtain at least 1100pt
wide.

### Companies or projects

Settings › Appearance › *Call them* switches every label between
"companies" and "projects" (both languages); `lib/l10n/projects.dart` holds the
alternative wording and `test/l10n_test.dart` fails if a string that says
company has no projects version.

## Languages

Arabic (default) and English, switchable in Settings › Appearance. Arabic
mirrors the whole layout right-to-left, and dates, times, notifications and
the menu bar menu follow the language. English text inside Arabic (and vice
versa) keeps its own reading order. Search understands both (`urgent` and
`عاجلة` find the same tasks). Typed times accept `2 م` and `٢:٣٠ م`.

Strings are written in English in code as `tr('…')`; the Arabic lives in
`lib/l10n/arabic.dart`. `test/l10n_test.dart` fails if a string is missing,
unused, or loses a `{placeholder}`. Default company names ("Company A" /
«الشركة الأولى») follow the language until you rename them.

## Architecture

```
macos/Runner/                 native shell (Swift)
  AppDelegate.swift           menu-bar-only app (LSUIElement), one Flutter engine
  PanelController.swift       status item + borderless drop-down panel
  HotKeyCenter.swift          global shortcuts via Carbon (no Accessibility permission)
  Reminders.swift             UserNotifications; schedule is computed in Dart
  NativeBridge.swift          the `docket/native` method channel

lib/
  data/                       models, SQLite persistence, store, queries, backup
  services/                   reminder planning, hotkey registration
  ui/                         controller (navigation, undo), pages, widgets, theme
  harness/                    screenshot + persistence self-test runner
```

**Data** lives in a local SQLite database (WAL mode) at
`~/Library/Containers/app.docket.mac/Data/Library/Application Support/app.docket.mac/docket.sqlite`.
Every change is written immediately in a transaction. Records use UUIDs,
`updated_at` timestamps and `deleted_at` tombstones so a cloud sync can be
added later with last-writer-wins merging. Automatic backups (daily, rotating)
go to the `Backups` folder next to the database; export/import use the same
JSON format.

**Notifications** are planned entirely in Dart (`services/reminders.dart`) and
replace the pending macOS notifications whenever data changes, so they never
drift from the tasks.

## Build & install

```sh
flutter build macos --release
ditto build/macos/Build/Products/Release/Docket.app /Applications/Docket.app
open /Applications/Docket.app
```

The first launch of an installed build turns on *Open at login* and asks for
notification permission. Both can be changed in Settings.

## Demo for screenshots

```sh
osascript -e 'tell application id "app.docket.mac" to quit'
open --env DOCKET_DEMO=1 /Applications/Docket.app
```

Runs the installed app on a fresh `demo/` data folder filled with English
sample tasks — a team lead's week across Project One/Two/Three and Personal
(PRs, TestFlight builds, sprint planning, 1:1s) — worded as *projects*, with
your language, display mode, theme, curtain settings and shortcuts.
`DOCKET_HARNESS=demoshots` renders the same data to PNG. Notifications, backups and the login item are
left alone and your real tasks are never opened. Quit and open Docket
normally to go back; anything added during the demo is discarded next time.

## Verifying changes

```sh
flutter analyze
flutter test                                   # store logic + UI interaction tests

# Real-database persistence across a restart (two separate processes):
BIN=build/macos/Build/Products/Debug/Docket.app/Contents/MacOS/Docket
DOCKET_HARNESS=selftest1 $BIN && DOCKET_HARNESS=selftest2 $BIN

# Render every screen in light and dark mode to PNG:
DOCKET_HARNESS=snapshot $BIN

# Check the native side: panel activation, status item, shortcut registration:
DOCKET_HARNESS=activation $BIN
```

Harness runs use a throwaway `harness/` folder next to the real database and
never touch your tasks. Results land in that folder (`selftest1.txt`,
`selftest2.txt`, `shots/`).
