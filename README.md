# noctalia-plugins

Personal [Noctalia](https://noctalia.dev) plugin source. Add it once, then
enable the plugins you want:

```sh
noctalia msg plugins source add diasbaskara git https://github.com/diasbaskara/noctalia-plugins
noctalia msg plugins enable diasbaskara/ai-usage
```

## Plugins

| Plugin | What |
| --- | --- |
| `diasbaskara/ai-usage` ([ai-usage/](ai-usage/)) | One bar capsule listing several [ai-usagebar](https://github.com/akitaonrails/ai-usagebar) providers side by side (Claude, Cursor, Grok, Grok Bot, OpenCode) with a details panel. |
| `diasbaskara/faceid` ([faceid/](faceid/)) | iOS-style Face ID indicator for the bar: a face glyph with a sweeping scan bar while [Howdy](https://github.com/boltgolt/howdy) runs, morphing to a green check or a red X. |

## Adding another plugin

1. Copy an existing plugin dir as a template: `cp -r ai-usage my-plugin/`.
2. Edit `my-plugin/plugin.toml` (new `id = "diasbaskara/my-plugin"`, bump nothing else you don't need).
3. Validate: `noctalia plugins lint my-plugin`.
4. Add one `[[plugin]]` row to [catalog.toml](catalog.toml) (copy the ai-usage row, new id/name/version, fresh `updated_at`/`added_at` timestamps).
5. Commit, push, then `noctalia msg plugins update diasbaskara`.
