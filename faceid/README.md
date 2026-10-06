# Face ID (Noctalia plugin)

An iOS-style Face ID overlay for Noctalia. While
[Howdy](https://github.com/boltgolt/howdy) runs a face scan, a floating dialog
animates at the top of the screen with a gap under the bar — a breathing face
glyph with a sweeping scan bar — then morphs to a green check on success or a
red, shaking X on failure and fades away.

It is a **floating overlay dialog, not a bar widget**.

Plugin id: `diasbaskara/faceid`

## How it works

Noctalia entries run in isolated VMs and share plain values through
`noctalia.state`. Two entries cooperate:

- **`service.luau`** (headless) — the single owner of the scan phase. It runs a
  tiny `pgrep` loop via `noctalia.runStream()` (bracket trick so the loop's own
  command line never matches itself) and publishes `phase` / `phaseAt`. On the
  rising edge it opens the dialog; on the falling edge it resolves the result.
- **`panel.luau`** — a floating, non-interactive panel. It subscribes to `phase`
  and animates with `onFrameTick()`, so it runs at full frame rate. When the
  result has faded it closes itself.

The panel is declared non-interactive: `persistent = true`,
`dismiss_on_outside_click = false`, `keyboard_focus = "none"`, `layer = "overlay"`.
It never steals focus and is not dismissed by a stray click, and the overlay
layer lets it sit above fullscreen windows.

## How success/fail is decided

The service resolves the outcome when the Howdy process exits:

| situation | result | shown |
|---|---|---|
| session was locked, now unlocked | success | green check |
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
| `hold_ms` | int | `1400` | How long the result glyph stays before the dialog fades. |

## Lock screen

The overlay is a Noctalia surface on the `overlay` layer, so it should appear
above fullscreen windows. Whether it renders **above Noctalia's own lock
screen** depends on how the compositor orders an overlay layer-shell surface
against the lock surface; if the lock screen covers it, the same effect is
visible for `sudo`/`doas` scans, or a bar widget entry can be added back as a
fallback.

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
- `panel.luau` — the animated overlay dialog.
- `translations/en.json` — settings labels.
