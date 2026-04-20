# Zlynk Addons — Agent Context

## What This Is

Monorepo for World of Warcraft addons by Zlynk. Built for a clean development experience with CI/CD that auto-publishes to CurseForge and Wago on tag push. Addons are written in Lua 5.1 targeting the WoW client API.

## Tech Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Language | Lua 5.1 | WoW's embedded runtime |
| Framework | Ace3 | AceAddon + AceDB + AceConsole + AceConfig + AceEvent |
| Monorepo | Turborepo + pnpm workspaces | Affected-based CI, shared package orchestration |
| Linting | luacheck | Static analysis for Lua |
| Formatting | StyLua | 2 spaces, 100 col width |
| Packaging | BigWigsMods/packager | De facto standard for CurseForge/Wago releases |
| CI/CD | GitHub Actions | Lint on PR, package + publish on tag |

## Project Structure

```
zlynk-addons/
├── addons/              # Each addon is a self-contained WoW addon
│   └── ZlynkCombatText/ # Folder name = addon name in WoW
├── packages/            # Shared Lua libraries bundled into addons at build time
│   └── zlynk-lib/       # Common utilities (event helpers, UI utils)
├── libs/                # Ace3 + community libs (gitignored, fetched by scripts/fetch-libs.sh)
├── scripts/             # Dev automation (link, fetch-libs, build, scaffold)
└── .github/workflows/   # CI (lint) + Release (package + publish)
```

### Addon Structure Convention

Every addon in `addons/` follows this layout:

```
ZlynkAddonName/
├── package.json           # Turbo task definitions
├── ZlynkAddonName.toc     # WoW manifest (folder name MUST match .toc filename)
├── .pkgmeta               # BigWigsMods packager config (externals, ignore, etc.)
├── embeds.xml             # Library loader (Ace3 includes)
├── Core/                  # Bootstrap, database, core event handling
├── Modules/               # Feature modules (one file per feature)
├── Config/                # AceConfig options tables + slash commands
├── Media/                 # Textures, fonts, sounds
└── vendor/                # Build output: shared libs copied here (gitignored)
```

## Ace3 Patterns

### Namespace Pattern

Every Lua file starts with:
```lua
local addonName, ns = ...
```
`ns` is the addon's private namespace table, shared across all files. Use it instead of globals.

### AceAddon Bootstrap

```lua
local Addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = Addon
```

### AceDB (Saved Variables)

- Define defaults in `Core/Database.lua` under `ns.defaults`
- Initialize with `LibStub("AceDB-3.0"):New("AddonNameDB", ns.defaults, true)`
- Access settings via `ns.db.profile.*`
- Always support profiles via AceDBOptions

### AceConfig (Settings UI)

- Define options tables as functions returning the table (for lazy evaluation)
- Register with `LibStub("AceConfig-3.0"):RegisterOptionsTable(...)`
- Add to Blizzard Settings with `LibStub("AceConfigDialog-3.0"):AddToBlizOptions(...)`
- Slash commands open settings by default, with sub-commands for quick toggles

### Module Pattern (for larger addons)

```lua
local Module = Addon:NewModule("ModuleName", "AceEvent-3.0")
function Module:OnEnable() ... end
function Module:GetOptions() return { ... } end  -- merged into main options
```

## Dev Workflow

### First-time setup

```sh
pnpm install          # Install turbo
pnpm libs             # Fetch Ace3 libraries (git clone from GitHub, no SVN needed)
pnpm link:addons      # Symlink addons into WoW AddOns folder
```

### Development loop

1. Edit Lua files in your editor
2. Save
3. `/reload` in-game
4. Changes are live immediately (no build step for Lua)

### Quick reference

```sh
pnpm dev              # Full setup (link + libs) for new clones
pnpm link:addons      # Symlink addons into WoW AddOns directory
pnpm libs             # Fetch/update Ace3 libraries
pnpm lint             # Luacheck via turbo (affected filtering)
pnpm format           # StyLua formatting
pnpm build            # Copy shared packages into addon vendor/ dirs
pnpm gates            # Pre-push: lint + build
```

### Enabling Lua errors in-game

Run this once in WoW:
```
/console scriptErrors 1
```

## CI/CD

### Pull Requests

`ci.yml` runs luacheck on affected addons only (turbo `--filter=...[origin/main]`).

### Releases

Tag-based releases via BigWigsMods/packager:

```sh
git tag zlynkcombattext-v1.0.0
git push origin zlynkcombattext-v1.0.0
```

Tag format: `<addonnamelowercase>-v<semver>`. The release workflow:
1. Parses the tag to identify which addon to package
2. Runs BigWigsMods/packager with that addon's `.pkgmeta`
3. Uploads to CurseForge, Wago, and GitHub Releases

### Secrets required

- `CF_API_KEY` — CurseForge API token (from authors.curseforge.com)
- `WAGO_API_TOKEN` — Wago Addons API token
- `GITHUB_TOKEN` — Automatic (for GitHub Releases)

### TOC Metadata

Each addon's `.toc` includes platform IDs for the packager:
```
## X-Curse-Project-ID: <id>
## X-Wago-ID: <id>
```
Set these after registering the addon on each platform.

## Code Style

- **2 spaces**, no tabs
- **100 character** column width
- **No globals** — use `local` for everything; access shared state via `ns` table
- **Descriptive names** — `camelCase` for locals/functions, `PascalCase` for modules/classes
- **One module per file** — each file does one thing
- **No inline comments for obvious code** — only comment non-obvious logic

## WoW API Conventions

- Never pollute the global namespace — always use `local`
- Use `ns` (addon namespace table) for cross-file communication within an addon
- Register events via AceEvent, not raw `frame:RegisterEvent()`
- Use `C_Timer.After` / `C_Timer.NewTicker` for timers, not OnUpdate scripts
- Frame names: only name frames that need to be accessed globally (most don't)
- Use `BackdropTemplate` mixin for frames needing backgrounds (post-9.0)

## WoW 12.x (Midnight) API Restrictions

All addons in this repo target the Midnight client (12.0+). The combat API landscape changed drastically in 12.0.0. Code must work within these constraints.

**Full reference:** See [docs/midnight-combat-api.md](docs/midnight-combat-api.md) for complete API documentation, available data sources, secret values patterns, and proven architecture.

**Key constraints:**
- `COMBAT_LOG_EVENT_UNFILTERED` is gone — do not use
- Combat values may be "secret" (opaque userdata) — cannot compare or do math, only pass to `SetText()`
- Threshold filtering on secrets is possible via `C_CurveUtil.GetCurveValueAtPoint()` step curves
- `UNIT_COMBAT("target")` leaks all damage on target, not just yours — requires cast correlation for attribution
- `COMBAT_TEXT_UPDATE` + `C_CombatText.GetCurrentEventInfo()` is the primary outgoing source (matched against pending cast queue)
- `UNIT_COMBAT("player")` is reliable for incoming damage
- Instance/PvP detection APIs (`GetInstanceInfo`, `IsActiveBattlefieldArena`, `C_PvP.IsBattleground`) work normally
- All combat value access must be pcall-wrapped

## Shared Libraries (packages/zlynk-lib)

Shared Lua utilities live in `packages/zlynk-lib/src/`. On `pnpm build`, these are copied into each addon's `vendor/` directory. This allows code sharing without WoW addon dependencies.

Load order: include vendor files in your `.toc` before any code that uses them.

## Library Management

- **Local dev**: `pnpm libs` shallow-clones [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3) from GitHub and extracts the libraries we need. Only requires git.
- **CI/release**: The `.pkgmeta` files reference SVN URLs (repos.wowace.com). The BigWigsMods/packager GitHub Action handles SVN internally — you never need SVN installed locally.
- **libs/ is gitignored**: Always fetched fresh. The `addons/*/libs` entries are symlinks to the root `libs/` directory.

## Adding a New Addon

1. Create `addons/ZlynkNewName/` with the standard structure
2. Add a `package.json` with lint + build scripts
3. Register the addon on CurseForge/Wago, get project IDs
4. Update the `.toc` with `X-Curse-Project-ID` and `X-Wago-ID`
5. Run `pnpm link:addons` to symlink it into WoW
6. Release with `git tag zlynknewname-v1.0.0 && git push --tags`
