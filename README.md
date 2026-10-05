# AI Usage Multi (Noctalia plugin)

One bar capsule listing **several** [ai-usagebar](https://github.com/akitaonrails/ai-usagebar)
providers side by side — e.g. Claude, Cursor, Grok and OpenCode Go — with a
details panel. Powered by `ai-usagebar usage --json`; the plugin never touches
credentials or provider APIs.

Plugin id: `diasbaskara/ai-usage`

## Install as a Noctalia source

```sh
noctalia msg plugins source add ai-usage git https://github.com/diasbaskara/noctalia-ai-usage
noctalia msg plugins enable diasbaskara/ai-usage
```

Then add a widget to the bar (`Settings → Bar`) or in `settings.toml`:

```toml
[widget.ai_multi]
type = "diasbaskara/ai-usage:bar"
vendors = "anthropic,cursor,supergrok,opencode-go"

[bar.default]
start = [ "ai_multi", "clock", "workspaces", "media" ]
```

Reload: `noctalia msg config-reload`.

## Settings

- `refresh_minutes` (plugin): poll interval, default 2.
- `vendors` (widget): comma-separated provider ids in display order.
  Run `ai-usagebar vendors` for the full list.
- `show_glyph`, `show_reset` (widget): icons and reset countdowns.

Which providers appear in the report is controlled by
`~/.config/ai-usagebar/config.toml` (`enabled = true`).

## Layout

- `service.luau` — single poller owning `ai-usagebar usage --json`.
- `bar.luau` — capsule: one chip per configured provider.
- `panel.luau` — per-provider meters, resets and fetch errors.
