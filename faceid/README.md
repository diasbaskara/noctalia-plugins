# Face ID (Noctalia plugin)

An iOS-style Face ID indicator for the Noctalia bar. While
[Howdy](https://github.com/boltgolt/howdy) runs a face scan it shows a face glyph
with a sweeping scan bar, then morphs to a green check on success or a red X on
failure and fades away.

Plugin id: `diasbaskara/faceid`

## How it works

Noctalia entries run in isolated VMs and share plain values through
`noctalia.state`. Two entries cooperate:

- **`service.luau`** (headless) — the single owner of the scan phase. It runs a
  tiny `pgrep` loop through `noctalia.runStream()` and publishes
  `phase` / `phaseAt` / `detail`. On the edge where the Howdy process exits it
  resolves the result.
- **`bar.luau`** — a pure subscriber. It watches `phase` and draws the capsule.
  The bar has no frame-tick API, so animation is driven by `update()` at ~40 ms
  while active and idle ticks in between.

Because the widget hides itself when idle, it takes no bar space until a scan
starts.

### How success/fail is decided

The service resolves the outcome when the Howdy process exits:

| situation | result | shown |
|---|---|---|
| session was locked, now unlocked | success | green check |
| session was locked, still locked | fail | red X |
| nothing was locked (`sudo`, `doas`, `su`) | unknown | brief neutral fade |

There is no in-process lock API, so the service asks the shell once per scan
edge (`noctalia msg status`, reading `locked`). For privileged-command face
auth the result is not observable from outside Howdy, hence the neutral fade.

## Install

The plugin ships from this repo as a Noctalia source:

```sh
noctalia msg plugins source add diasbaskara git https://github.com/diasbaskara/noctalia-plugins
noctalia msg plugins update diasbaskara
noctalia msg plugins enable diasbaskara/faceid
```

Then add the widget to a bar. Easiest: **middle-click the bar → Settings** and add
**Face ID**, or edit the bar config directly.

In `~/.config/noctalia/settings.json`, add an entry to one of the bar widget
arrays (`bar.widgets.left`, `center`, or `right`):

```json
{ "id": "plugin:diasbaskara/faceid" }
```

Reload with `noctalia msg config-reload`.

## Settings

| Key | Type | Default | Meaning |
|---|---|---|---|
| `process_pattern` | string | `compare.py` | `pgrep -f` fragment that identifies a Howdy scan. |
| `hold_ms` | int | `1400` | How long the result glyph stays before fading. |
| `label` | string | `""` | Optional text next to the glyph (widget entry setting). |

## Driving it from outside (optional)

The service accepts IPC events, which is useful if you want a custom trigger or
an exact result where the lock heuristic is not enough. The command must run in
the user's session (not as root):

```sh
noctalia msg plugin diasbaskara/faceid:watch all scan
noctalia msg plugin diasbaskara/faceid:watch all success
noctalia msg plugin diasbaskara/faceid:watch all fail
noctalia msg plugin diasbaskara/faceid:watch all idle
```

A `pam_exec` hook placed *after* Howdy in the PAM stack runs only when the face
check fails, which is a clean way to report failures for `sudo`/`doas`:

```
auth optional pam_exec.so quiet /usr/local/bin/faceid-hook fail
```

The helper has to switch to the target user (`runuser -u "$PAM_USER" -- …`)
before calling `noctalia msg`, because the IPC socket is owned by that user's
session.

## Layout

- `plugin.toml` — manifest, plugin settings, the service and the bar widget.
- `service.luau` — Howdy process watcher and phase state owner.
- `bar.luau` — the Face ID capsule and its animation.
- `translations/en.json` — settings labels.
