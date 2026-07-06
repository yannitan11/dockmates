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
  editor: skin tone; hair (crop / bob / long / ponytail / pigtails / bun) +
  color; hat (none / beanie / bucket / cap / beret / headband / flower crown)
  + color; top style (singlet / t-shirt / cardigan / jacket) + color, each
  with a genuinely different silhouette (bare arms, capped sleeves, or full
  sleeves, plus buttons/pockets/seam details to match); bottom (pants or
  skirt) + color; shoes; neck accessory (none / scarf / tie / bow) + color;
  and glasses / tote toggles. Chip rows wrap onto a second line and the whole
  options list scrolls, so it keeps working cleanly as more options get added.
  Changes apply instantly on the dock and persist across restarts
  (`UserDefaults`); Reset restores the original look.
- **Claude Code watch:** the buddies nudge you when a Claude Code session
  finishes a turn or needs your attention (a permission prompt or waiting for
  input), so you can tab back. A buddy hops with a bubble naming the project
  that wrapped up ("dockmates is done!") when it can tell, and a macOS
  notification fires too (useful when you're in a fullscreen app and the dock
  is hidden). It only nudges when Claude Code **isn't** the app you're already
  looking at, so it stays quiet while you're actively using it. Sessions that
  finish while you're away stack up as a little red badge on the buddy that
  nudged you; it clears when you click a buddy or switch back to Claude Code.
  Toggle the whole feature from the menu bar ("Notify me about Claude Code").
  See "Claude Code hooks" below for the one-time setup this relies on.
- **Routines** (menu bar → Routines): little recurring nudges. "Drink water
  every 1h", "exercise at 6:00 pm". When one fires, a free buddy hops and says
  it in a speech bubble. Toggle reminders on/off or delete them; everything
  persists across restarts. If your Mac was asleep when a daily reminder was
  due, it fires on wake unless it's more than 90 minutes late.
- **Pets:** Mochi the cat and Tofu the white dog are optional dockmates —
  chunky side-profile pets that stroll, blink, and swish/wag their tails
  (the cat sways slowly; the dog wags fast). A left-click gets a happy
  "meow!" or "woof!" (pets don't run Claude tasks); right-click opens their
  dressing room — fur color, collar (on/off + color), and an accessory (bow,
  bandana, or party hat) with its own color. Juno and Bo are the two people
  who can talk to Claude.
- **Choose who's on the dock:** menu bar → **On the dock** lists every
  dockmate (Juno, Bo, Mochi (cat), Tofu (dog)) with a check; toggle any on
  or off — e.g. keep just one pet, or none. The choice persists, and the
  dock happily runs with all of them, some, or none.
- **Menu bar (sparkles icon):** Ask Claude, Dressing room, Routines, On the
  dock, Notify me about Claude Code, Pause/Resume strolling, Start at Login,
  Quit.
- Buddies only grab your mouse when the cursor is directly over them; the rest
  of the strip stays click-through.

## Claude Code hooks (for the Claude Code watch feature)

The "come back to Claude" nudge, the project name in it ("**dockmates** is
done!"), and the unread-count badge on a buddy all rely on Claude Code
telling Dockmates when something happens. That's wired up via two hooks in
your global `~/.claude/settings.json` — merge this into the `"hooks"` block
(creating the file if it doesn't exist):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.dockmates && p=$(jq -r '.cwd // \"\" | split(\"/\") | last // \"\"' 2>/dev/null | tr '\\n\\t' '  '); printf 'stop\\t%s\\t%s\\n' \"$(date +%s)\" \"$p\" >> ~/.dockmates/events.log 2>/dev/null || true"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p ~/.dockmates && msg=$(jq -r '.message // empty' | tr '\\n\\t' '  '); printf 'notify\\t%s\\t%s\\n' \"$(date +%s)\" \"$msg\" >> ~/.dockmates/events.log 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

- **Stop** hook → appends a `stop` line (timestamp + the session's project
  folder name, read from the hook's `cwd` field) to `~/.dockmates/events.log`
  when a session finishes a turn. The project name is what lets the nudge say
  which project wrapped up instead of a generic "Claude's all done!"; if it's
  missing (e.g. an older hook, or `jq` not installed) Dockmates falls back to
  the generic message.
- **Notification** hook → appends a `notify` line (with the message) when
  Claude Code needs permission or is waiting for input.

Both commands use `jq` to parse the hook's JSON input; it isn't bundled with
macOS, so install it first with `brew install jq` if you don't already have
it (`which jq` to check). Without `jq` the hooks still run (`|| true` keeps
them from erroring) but the project name and notification message are lost.

Dockmates tails that log and nudges you. The hooks only write a line to a file;
they change nothing else. To turn the feature off entirely, either uncheck
"Notify me about Claude Code" in the menu (keeps the hooks but ignores them) or
remove the `"hooks"` block from `~/.claude/settings.json`. New Claude Code
sessions pick up the hooks automatically; an already-open session may need to
be reopened (or run `/hooks` in it to reload).

## App icon

`Resources/icon_1024.png` is the master art — Juno and Bo on the dock ledge,
rendered with the app's own `Buddy` character code so it always matches the
live look. `build.sh` converts it to `Contents/Resources/AppIcon.icns` (all
standard sizes via `sips`/`iconutil`) on every build; `Info.plist` points at
it via `CFBundleIconFile`. To change the art, regenerate the master and
rebuild:

```bash
build/Dockmates.app/Contents/MacOS/Dockmates --icon Resources/icon_1024.png 1024
./install.sh
```

## Design review mode

Renders the characters to a PNG without launching the app — handy for iterating
on the art:

```bash
build/Dockmates.app/Contents/MacOS/Dockmates --snapshot /tmp/buddies.png
build/Dockmates.app/Contents/MacOS/Dockmates --snapshot-closeup /tmp/closeup.png
build/Dockmates.app/Contents/MacOS/Dockmates --snapshot-hats /tmp/hats.png
build/Dockmates.app/Contents/MacOS/Dockmates --snapshot-dressing-room /tmp/panel.png
```

`--snapshot` renders a wardrobe mosaic of several outfits; `--snapshot-closeup`
and `--snapshot-hats` render characters at real geometric zoom (the `scale:`
parameter on `Buddy.init` is contentsScale for sharpness only, not physical
size, so a real closeup needs an explicit `CATransform3DMakeScale` on
`buddy.root`); `--snapshot-dressing-room` renders the whole scrollable options
list from `StylePanel` (not just what fits in the visible window) as one tall
image, for checking chip-wrapping without having to scroll the live panel.

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
