# Face ID (Noctalia plugin)

An iOS-style Face ID overlay for Noctalia. While
[Howdy](https://github.com/boltgolt/howdy) runs a face scan, a **square attached
panel** drops from the bar (the same placement the built-in control center uses)
and plays a two-part animation, then fades away.

- **Looking for face** — the scanning glyph while Howdy runs.
- **Success** — the morph to a checkmark when the face is recognized.
- **Failure** — a red, shaking X.

It is an attached panel, not a floating/detached dialog and not a bar widget.

Plugin id: `diasbaskara/faceid`

## How it works

Noctalia entries run in isolated VMs and share plain values through
`noctalia.state`. Two entries cooperate:

- **`service.luau`** (headless) — the single owner of the scan phase. It runs a
  tiny `pgrep` loop via `noctalia.runStream()` (bracket trick so the loop's own
  command line never matches itself) and publishes `phase` / `phaseAt`. On the
  rising edge it opens the panel; on the falling edge it resolves the result.
- **`panel.luau`** — an attached, non-interactive panel. It subscribes to
  `phase` and animates with `onFrameTick()`, so it runs at full frame rate. When
  the result has faded it closes itself.

The panel is declared `placement = "attached"` (hangs from the bar, like the
control center) with `dismiss_on_outside_click = false` and
`keyboard_focus = "none"`, so it never steals focus and is not dismissed by a
stray click. Attached panels cannot be persistent, so it uses the normal panel
slot while a scan runs.

## Artwork

The glyphs come from the [Face ID](https://lottiefiles.com/free-animation/face-id-4Z76hfSHSI)
animation on LottieFiles (blue `#006DF8`). Noctalia's `ui.image` only renders the
first frame of an animated image, so the two parts are exported to PNG frames and
played by swapping the image path each tick:

- `assets/look.png` — part 1, the looking-for-face glyph (scan state).
- `assets/success_00.png … success_21.png` — part 2, the morph to the check.

To re-export from the source animation, render it to frames and key out the
background, then crop the two ranges (the look part is static; motion starts at
the beginning of the success range).

## How success/fail is decided

The service resolves the outcome when the Howdy process exits:

| situation | result | shown |
|---|---|---|
| session was locked, now unlocked | success | check morph |
| session was locked, still locked | fail | red X |
| nothing was locked (`sudo`, `doas`, `su`) | unknown | brief neutral fade |

The success check **polls for up to ~1.25 s**, because the session unlocks a
moment after the Howdy process exits (PAM returns, then Noctalia releases the
lock). There is no in-process lock API, so the service asks the shell once per
scan edge (`noctalia msg status`, reading `locked`).

## Install

The plugin ships from this repo as a Noctalia source:

```sh
noctalia msg plugins source add diasbaskara git https://github.com/diasbaskara/noctalia-plugins
noctalia msg plugins update diasbaskara
noctalia msg plugins enable diasbaskara/faceid
```

That is all — the dialog opens and closes itself around each scan. There is
nothing to place on the bar.

## Settings

| Key | Type | Default | Meaning |
|---|---|---|---|
| `process_pattern` | string | `compare.py` | `pgrep -f` fragment that identifies a Howdy scan. |
| `hold_ms` | int | `1400` | How long the result stays before the dialog fades. |

## Lock screen

The overlay is a normal layer-shell surface, so it **cannot render over the lock
screen**: Noctalia locks via the compositor's secure `ext-session-lock`, and no
other client — plugin panel, desktop widget, or external overlay — may draw above
it. The HUD therefore shows for **unlocked** face auth (`sudo`, `doas`, manual
triggers), not during lock-screen unlock.

## Driving it from outside (optional)

The service accepts IPC events, useful for a custom trigger or an exact result
where the lock heuristic is not enough. Run in the user's session (not as root):

```sh
noctalia msg plugin diasbaskara/faceid:watch all scan
noctalia msg plugin diasbaskara/faceid:watch all success
noctalia msg plugin diasbaskara/faceid:watch all fail
noctalia msg plugin diasbaskara/faceid:watch all idle
```

A `pam_exec` hook placed *after* Howdy in the PAM stack runs only when the face
check fails — a clean way to report failures for `sudo`/`doas`:

```
auth optional pam_exec.so quiet /usr/local/bin/faceid-hook fail
```

The helper must switch to the target user (`runuser -u "$PAM_USER" -- …`) before
calling `noctalia msg`, because the IPC socket is owned by that user's session.

## Layout

- `plugin.toml` — manifest, plugin settings, the service and the panel.
- `service.luau` — Howdy process watcher, phase state owner, dialog opener.
- `panel.luau` — the square animated overlay panel.
- `assets/` — the two-part Face ID artwork.
- `translations/en.json` — settings labels.
