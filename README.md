# zlynk-addons

World of Warcraft addons by Zlynk.

## Addons

| Addon | Description | Status |
|-------|-------------|--------|
| [ZlynkCombatText](addons/ZlynkCombatText) | Lightweight floating combat text | WIP |

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
