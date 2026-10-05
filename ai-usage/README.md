# AI Usage Multi (Noctalia plugin)

One bar capsule listing **several** [ai-usagebar](https://github.com/akitaonrails/ai-usagebar)
providers side by side — e.g. Claude, Cursor, Grok, Grok Bot and OpenCode — with
a details panel. Powered by `ai-usagebar usage --json`; the plugin never touches
credentials or provider APIs.

Plugin id: `diasbaskara/ai-usage`

## Install as a Noctalia source

```sh
noctalia msg plugins source add diasbaskara git https://github.com/diasbaskara/noctalia-plugins
noctalia msg plugins enable diasbaskara/ai-usage
```

Then add a widget to the bar (`Settings → Bar`) or in `settings.toml`:

```toml
[widget.ai_multi]
type = "diasbaskara/ai-usage:bar"
vendors = "anthropic,cursor,supergrok,opencode-go,grokbot"

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

The panel is header / content / footer: title and refresh on top, a provider
sidebar beside the selected provider's limit cards, and the global
"use X first" suggestion as a footer card.

Bar chips and the sidebar are both ordered by soonest upcoming reset; a
provider with no reset data keeps its configured order at the end.

- `service.luau` — single poller owning `ai-usagebar usage --json`.
- `bar.luau` — capsule: one chip per configured provider, reset-sorted.
- `panel.luau` — sidebar, limit cards, error cards with login actions.
- `icons/` — brand marks, theme-paired (`x.svg` dark, `x-light.svg` light).
