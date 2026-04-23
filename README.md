# zlynk-addons

World of Warcraft addons by Zlynk.

## Addons

| Addon | Description | Status |
|-------|-------------|--------|
| [ZlynkCombatText](addons/ZlynkCombatText) | Lightweight floating combat text | WIP |

## WoW 12.x (Midnight) API Notes

These addons target the Midnight client (12.0+). Blizzard removed the traditional combat log API (`COMBAT_LOG_EVENT_UNFILTERED`) and replaced much of the combat data system with "Secret Values" — opaque userdata that addons can display but cannot inspect or branch on.

**Available data sources for combat text:**
- `UNIT_COMBAT` — per-hit events with amounts (no spell ID, no source attribution)
- `C_DamageMeter` — server-side totals with spell IDs (no per-hit granularity)
- Secret value passthrough to `FontString:SetText()` (display only, no logic)

**Not available:**
- `COMBAT_LOG_EVENT_UNFILTERED` / `CombatLogGetCurrentEventInfo()` — gone
- Per-hit spell identification in addon Lua
- Conditional logic on combat values in instanced content (boss fights, M+)

See [CLAUDE.md](CLAUDE.md) for full API reference and implementation strategy.

## Development

Requires: Node.js, pnpm, git, WoW installed.

```sh
pnpm install        # Install tooling (turbo)
pnpm libs           # Fetch Ace3 libraries
pnpm link:addons    # Symlink addons into WoW AddOns folder
```

Then edit Lua files and `/reload` in-game. No build step needed.

### Commands

```sh
pnpm dev            # Full first-time setup (link + libs)
pnpm lint           # Luacheck (affected addons only)
pnpm format         # StyLua formatting
pnpm build          # Bundle shared packages into addons
pnpm gates          # Pre-push checks (lint + build)
```

## Releasing

Tag-based releases auto-publish to CurseForge and Wago via GitHub Actions:

```sh
git tag zlynkcombattext-v1.0.0
git push origin zlynkcombattext-v1.0.0
```

## License

MIT
