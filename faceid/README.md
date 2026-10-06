# Face ID (Noctalia plugin)

An iOS-style Face ID overlay for Noctalia. While
[Howdy](https://github.com/boltgolt/howdy) runs a face scan, a **square attached
panel** drops from the bar (the same placement the built-in control center uses)
and loops the looking-for-face animation, then closes when the scan ends.

There is no success or error state — the panel simply appears while scanning and
closes afterwards.

Plugin id: `diasbaskara/faceid`

## How it works

Noctalia entries run in isolated VMs. Two entries cooperate:

- **`service.luau`** (headless) — watches for a running Howdy scan with a tiny
  `pgrep` loop via `noctalia.runStream()` (bracket trick so the loop's own
  command line never matches itself). On the rising edge it opens the panel; on
  the falling edge it closes it.
- **`panel.luau`** — an attached, non-interactive panel. It loops the animation
  frames with `onFrameTick()` and closes itself when the phase returns to idle.

The panel is declared `placement = "attached"` (hangs from the bar, like the
control center) with `dismiss_on_outside_click = false` and
`keyboard_focus = "none"`, so it never steals focus and is not dismissed by a
stray click. Attached panels cannot be persistent, so it uses the normal panel
slot while a scan runs.

## Artwork

The "looking for face" animation is from LottieFiles
([faceid](https://lottiefiles.com/free-animation/faceid-PC8pwZve58)), recoloured
**white** to match the shell theme. Noctalia's `ui.image` only renders the first
frame of an animated image, so the frames are exported to PNGs
(`assets/look_00.png … look_59.png`) and played by swapping the image path each
frame tick. The source runs at 60 fps over ~3.9 s; every 4th frame is kept for a
smooth, small loop.

## Install

The plugin ships from this repo as a Noctalia source:

```sh
noctalia msg plugins source add diasbaskara git https://github.com/diasbaskara/noctalia-plugins
noctalia msg plugins update diasbaskara
noctalia msg plugins enable diasbaskara/faceid
```

That is all — the panel opens and closes itself around each scan. There is
nothing to place on the bar.

## Settings

| Key | Type | Default | Meaning |
|---|---|---|---|
| `process_pattern` | string | `compare.py` | `pgrep -f` fragment that identifies a Howdy scan. |

## Lock screen

The panel is a normal layer-shell surface, so it **cannot render over the lock
screen**: Noctalia locks via the compositor's secure `ext-session-lock`, and no
other client — plugin panel, desktop widget, or external overlay — may draw above
it. The overlay therefore shows for **unlocked** face auth (`sudo`, `doas`, manual
triggers), not during lock-screen unlock.

## Driving it from outside (optional)

```sh
noctalia msg plugin diasbaskara/faceid:watch all scan    # open
noctalia msg plugin diasbaskara/faceid:watch all close   # close
```

## Layout

- `plugin.toml` — manifest, the process setting, the service and the panel.
- `service.luau` — Howdy process watcher and panel open/close.
- `panel.luau` — the square looping overlay panel.
- `assets/` — the looking-for-face animation frames.
- `translations/en.json` — settings label.
