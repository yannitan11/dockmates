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

```bash
./build.sh
open build/Dockmates.app
```

Dockmates runs as a menu-bar app (sparkles icon) with no dock icon of its own.

## Using it

- **Click a buddy** → ask panel opens → type a question → return to send.
- **Reminders from the ask box:** typing something like "drink water every 30
  mins", "stretch every 2 hours", or "exercise at 6pm" sets a routine directly
  (no Claude needed) and the buddy confirms with the schedule it understood.
  Real questions still go to Claude.
- While working they say "on it!" and pace; when done you get a "ta-da!" and the
  answer panel. Copy button puts the raw text on your clipboard.
- **Right-click a buddy** (or menu bar → Dressing room) → live character
  editor: skin tone, hair (crop / bob / long / bun) + color, hat (beanie /
  bucket / none) + color, top, bottom (pants or skirt) + color, shoes, plus
  glasses / scarf / tote toggles.
  Changes apply instantly on the dock and persist across restarts
  (`UserDefaults`); Reset restores the original look.
- **Routines** (menu bar → Routines): little recurring nudges. "Drink water
  every 1h", "exercise at 6:00 pm". When one fires, a free buddy hops and says
  it in a speech bubble. Toggle reminders on/off or delete them; everything
  persists across restarts. If your Mac was asleep when a daily reminder was
  due, it fires on wake unless it's more than 90 minutes late.
- **Menu bar (sparkles icon):** Ask Claude, Dressing room, Routines,
  Pause/Resume strolling, Quit.
- Buddies only grab your mouse when the cursor is directly over them; the rest
  of the strip stays click-through.

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
