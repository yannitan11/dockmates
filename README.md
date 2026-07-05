# Dockmates

Two tiny illustrated coworkers, Juno and Bo, who live on your macOS dock and help
you work. They stroll along the top of the dock, blink, chat, and hop. Click one
and a little prompt panel opens; whatever you ask gets run through the `claude`
CLI while your buddy paces around saying "thinking...", then the answer pops up
in a warm paper panel with a Copy button.

Inspired by the "tiny AI agents on your dock" trend, with original characters:

- **Juno** — tangerine boxy jacket, black beanie, round glasses. The fast walker.
- **Bo** — sage cardigan, mustard scarf, lilac bucket hat, smiley tote. Takes it slow.

## Requirements

- macOS 13+ (built and tested on much newer)
- Swift command line tools (`xcode-select --install`) — no Xcode needed
- **Optional:** a logged-in `claude` command-line tool, only for open-ended
  questions. Note the Claude **desktop app** does not provide this — you need
  the standalone CLI installed and signed in (`claude` once to log in). The
  pets, reminders, and dressing room all work fully without it, and the ask
  box shows a friendly note if you ask a question with no CLI available.

## Build & run

For quick dev iteration (compiles into `build/Dockmates.app`, doesn't touch
your installed copy or its login item):

```bash
./build.sh
open build/Dockmates.app
```

For a stable, permanent install (builds, then copies to `/Applications` and
relaunches from there):

```bash
./install.sh
```

Dockmates runs as a menu-bar app (sparkles icon) with no dock icon of its own.
It launches itself automatically at login by default (toggle it from the menu
under "Start at Login"), and you can quit it anytime from the same menu. The
login item points at wherever the app was last launched from, so use
`./install.sh` (not `./build.sh` + `open build/Dockmates.app`) whenever you
want the auto-launch to keep working reliably, especially if you might move or
delete this project folder later.

## Using it

- **Click a buddy** → ask panel opens → type a question → return to send.
- **Reminders from the ask box:** typing something like "drink water every 30
  mins", "stretch every 2 hours", or "exercise at 6pm" sets a routine directly
  (no Claude needed) and the buddy confirms with the schedule it understood.
  Real questions still go to Claude.
- **Dismissing panels:** any panel (ask, answer, dressing room, routines)
  closes when you click outside it, press Esc, or hit its Close button.
- While working they say "on it!" and pace; when done you get a "ta-da!" and the
  answer panel. Copy button puts the raw text on your clipboard.
- **Drag a buddy** left or right to slide it anywhere along the dock; it
  strikes a picked-up pose while held and resumes strolling after you drop it.
  A plain click (no drag) still opens the ask box.
- **Right-click a buddy** (or menu bar → Dressing room) → live character
  editor: skin tone, hair (crop / bob / long / bun) + color, hat (beanie /
  bucket / none) + color, top, bottom (pants or skirt) + color, shoes, plus
  glasses / scarf / tote toggles.
  Changes apply instantly on the dock and persist across restarts
  (`UserDefaults`); Reset restores the original look.
- **Claude Code watch:** the buddies nudge you when a Claude Code session
  finishes a turn or needs your attention (a permission prompt or waiting for
  input), so you can tab back. A buddy hops with a bubble, and a macOS
  notification fires too (useful when you're in a fullscreen app and the dock
  is hidden). It only nudges when Claude Code **isn't** the app you're already
  looking at, so it stays quiet while you're actively using it. Toggle it from
  the menu bar ("Notify me about Claude Code"). See "Claude Code hooks" below
  for the one-time setup this relies on.
- **Routines** (menu bar → Routines): little recurring nudges. "Drink water
  every 1h", "exercise at 6:00 pm". When one fires, a free buddy hops and says
  it in a speech bubble. Toggle reminders on/off or delete them; everything
  persists across restarts. If your Mac was asleep when a daily reminder was
  due, it fires on wake unless it's more than 90 minutes late.
- **Menu bar (sparkles icon):** Ask Claude, Dressing room, Routines, Notify me
  about Claude Code, Pause/Resume strolling, Start at Login, Quit.
- Buddies only grab your mouse when the cursor is directly over them; the rest
  of the strip stays click-through.

## Claude Code hooks (for the Claude Code watch feature)

The "come back to Claude" nudge relies on Claude Code telling Dockmates when
something happens. That's wired up via two hooks in your global
`~/.claude/settings.json`:

- **Stop** hook → appends a `stop` line to `~/.dockmates/events.log` when a
  session finishes a turn.
- **Notification** hook → appends a `notify` line (with the message) when
  Claude Code needs permission or is waiting for input.

Dockmates tails that log and nudges you. The hooks only write a line to a file;
they change nothing else. To turn the feature off entirely, either uncheck
"Notify me about Claude Code" in the menu (keeps the hooks but ignores them) or
remove the `"hooks"` block from `~/.claude/settings.json`. New Claude Code
sessions pick up the hooks automatically; an already-open session may need to
be reopened.

## Design review mode

Renders the characters to a PNG without launching the app — handy for iterating
on the art:

```bash
build/Dockmates.app/Contents/MacOS/Dockmates --snapshot /tmp/buddies.png
```

## Architecture

Vanilla AppKit + Core Animation, compiled with `swiftc` (see `build.sh`).

- `Sources/Theme.swift` — palette (paper / ink / one tangerine accent) + SF Rounded helper
- `Sources/Buddy.swift` — character art (pure CAShapeLayers) + walk/idle/think/celebrate state machine
- `Sources/Bubble.swift` — speech bubble layer with spring pop
- `Sources/Overlay.swift` — transparent click-through window above the dock, 30fps tick, snapshot renderer
- `Sources/AskPanel.swift` / `AnswerPanel.swift` — prompt input + markdown-lite answer panels
- `Sources/ClaudeRunner.swift` — shells out to `claude -p` off the main thread
- `Sources/AppController.swift` — menu bar item + wiring

The dock position is derived from `NSScreen.visibleFrame`; if the dock is hidden
or on the side, the buddies walk along the bottom edge of the screen instead.
