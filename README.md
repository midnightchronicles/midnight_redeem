# Midnight Redeem

> A modern, escrow-friendly FiveM redeem system with a live admin dashboard, automated daily rewards, permissions, logging, and optional AI-assisted code generation.

## Features
- Single-use, multi-use, unlimited, and scheduled redeem codes.
- Rewards for items, money, vehicles, or mixed bundles.
- Live admin dashboard with search, templates, statistics, permissions, and transcript tools.
- Automated daily rewards with configurable cadence and per-user limits.
- Owner / manager / staff permission system with framework-admin onboarding support.
- Discord and FiveManage logging with route-based webhooks and SDK fallback support.
- Version checker powered by `fxmanifest.lua` and GitHub releases.
- 23 locale packs, persistent theme settings, and a configurable content filter.
- Optional Shadow AI assistant for generating reward setups faster.

## Requirements
- Latest FiveM server artifact with `fx_version 'cerulean'`
- Lua 5.4
- [`oxmysql`](https://github.com/overextended/oxmysql)
- [`ox_lib`](https://github.com/overextended/ox_lib)
- [`community_bridge`](https://github.com/The-Order-Of-The-Sacred-Framework/community_bridge)

## Optional Integrations
- [`fmsdk`](https://docs.fivemanage.com/sdk/fivem/logs) for native FiveManage logging support
- [`zdiscord`](https://github.com/zfbx/zdiscord) for the bundled `/generateredeem` Discord command

## Installation
1. Place `midnight_redeem` inside your server's resources folder.
2. Make sure dependencies start before this resource:

```cfg
ensure ox_lib
ensure oxmysql
ensure community_bridge
ensure midnight_redeem
```

Start your framework and inventory resources in the correct order for your `community_bridge` setup.

3. Add Discord and FiveManage logging convars to `server.cfg`:

```cfg
# Midnight Redeem logging
setr mredeem:webhook_default "https://discord.com/api/webhooks/..."
setr mredeem:webhook_admin   "https://discord.com/api/webhooks/..."
setr mredeem:webhook_daily   "https://discord.com/api/webhooks/..."
setr FIVEMANAGE_LOGS_API_KEY "your_fivemanage_key"   # optional fallback for direct API
```

4. If you want to use Shadow AI, add the AI convars to `server.cfg`:

```cfg
# Midnight Redeem - Shadow AI
set MREDEEM_AI_API_KEY    "sk-..."
set MREDEEM_AI_PROVIDER   "openai"
set MREDEEM_AI_MODEL      "gpt-4.1-mini"
set MREDEEM_AI_WEB_SEARCH "1"   # 1 = enable web search, 0 = disable
```

5. Start the server once, or run `refresh` followed by `ensure midnight_redeem`, so the resource can create and migrate all `midnight_*` database tables automatically.
6. Review and customize configuration:
- **In-game (owners):** Settings → **Config** tab — edit general settings, daily rewards, prefilled templates, and content filter at runtime (saved to the database, persists across restarts).
- **`server/runtime_config.lua`** — factory defaults embedded at the top of this file; written to the database on first resource start. After that the database is the source of truth.
- **`server/permissions.lua`** — owner identifiers, permission model, and default role behavior.
7. Optional: copy `zdiscord_command_file/generateredeem.js` into `zdiscord/server/commands/` if you want staff to generate codes from Discord.
8. Restart `midnight_redeem` after changing embedded defaults in `runtime_config.lua` or `permissions.lua`. Most other settings can be changed live from the Config tab.

> The resource masks webhook URLs in debug output and prints which FiveManage path is active during startup.

## Quick Start
1. Add your owner identifiers to `server/permissions.lua`.
2. Start the resource.
3. Join the server with a listed owner account.
4. Run `/midnight_admin_init` once to seed your first owner entry.
5. Open the admin panel with `/adminredeem`.

## ACE Permissions
`midnight_redeem` now checks `community_bridge` admin status first and falls back to ACE if framework admin detection returns false or fails. This is useful for Qbox setups and mixed permission environments.

Add this line to `server.cfg` or, if you manage ACEs separately on Qbox, to `permissions.cfg`:

```cfg
add_ace group.admin midnight_redeem.admin allow
```

Then make sure your admins are actually in that ACE group, for example:

```cfg
add_principal identifier.license:YOUR_LICENSE_HERE group.admin
```

Notes:
- With `REQUIRE_PERMISSION = false`, any player recognized by `community_bridge` or ACE can use admin-only Midnight Redeem actions.
- With `REQUIRE_PERMISSION = true`, `community_bridge` or ACE can get the player through the admin gate, and Midnight Redeem's own role system still controls actions such as `/redeemrole`, delete permissions, and other manager/owner features.
- For Qbox servers, put the ACE in whichever file you already use for your permission principals. Many servers use `permissions.cfg`.

## Configuration

### Runtime config (in-game)
Owners can open **Settings → Config** and edit live settings in four sub-tabs. Changes are stored in the `midnight_runtime_config` database table.

| Tab | What it controls |
|-----|------------------|
| **General** | Debug, framework, commands, SQL cleanup, dashboard refresh, logging |
| **Daily Rewards** | Enable flag, reward times, uses, per-user limit, window hours, rotation JSON |
| **Prefilled** | Reward categories, quick templates, and AI code templates (JSON) |
| **Content Filter** | Blocked words by category |

**Chat Settings** (same section, owner-only) controls Shadow AI enable flag, rate limits, transcript retention, welcome message, and transcript maintenance actions.

Provider, model, and web search remain in `server.cfg` (`MREDEEM_AI_*` convars).

### `server/runtime_config.lua`
Factory defaults are embedded at the top of this file and written to `midnight_runtime_config` on first start. After seeding, edit config in-game or in the database. Use **Reset Tab to Defaults** in the Config UI to restore a section to the embedded factory values.

To change factory defaults for new installs, edit the embedded `Config.*` block near the top of `runtime_config.lua` (before the database helpers).

### `server/permissions.lua`
- Add your owner identifiers to `OWNER_LICENSES`.
- Set `REQUIRE_PERMISSION = false` if you want to trust `community_bridge` admin detection or ACE (`midnight_redeem.admin`) instead of the built-in RBAC system.
- Set `DEFAULT_ROLE` to the role that framework admins or ACE admins should receive on first access.
- Adjust `PERMISSION_ACTIONS_CONFIG` to control who can use each protected action.

Example:

```lua
REQUIRE_PERMISSION = true

DEFAULT_ROLE = "staff"

PERMISSION_ACTIONS_CONFIG = {
    CREATE_CODES = { "owner", "manager", "staff" },
    EDIT_CODES = { "owner", "manager" },
    DELETE_CODES = { "owner", "manager" },
    BULK_DELETE = { "owner", "manager" },
    VIEW_DASHBOARD = { "owner", "manager", "staff" },
    VIEW_TRANSCRIPTS = { "owner", "manager", "staff" },
    MANAGE_PERMISSIONS = { "owner", "manager" },
    COLOR_SETTINGS = { "owner", "manager", "staff" },
    FULL_ACCESS = { "owner" }
}
```
---
side note all admins will auto get assigned with the staff role
---

## Logging
- `SendToDiscord` routes logs to `mredeem:webhook_default`, `mredeem:webhook_admin`, or `mredeem:webhook_daily`.
- If `fmsdk` is available, FiveManage logging uses the SDK automatically.
- If `fmsdk` is not available, the resource falls back to `FIVEMANAGE_LOGS_API_KEY`.
- Daily reward announcements always use the `daily` Discord webhook.

## Version Checking
- The installed version is read directly from `fxmanifest.lua`.
- On startup, the resource checks the latest GitHub release.
- Three states are supported: up to date, update available, and ahead of public release.
- The installed version is shown in the UI and in startup console output.

## Commands

| Command | Access | Description |
| --- | --- | --- |
| `/redeemcode` | All players | Opens the player redeem prompt. |
| `/adminredeem` | Staff+ or framework admins | Opens the Midnight Redeem admin dashboard. |
| `/midnight_admin_init` | Listed owners only | Seeds the first owner record for your server. |
| `/redeemrole <player_id> <role>` | Manager+ | Changes a player's role. |
| `/checkowner` | Any player | Checks whether your identifier is listed as an owner. |
| `/refreshdashboard` | Console or trusted admin | Forces a dashboard cache refresh and pushes updated stats to open UIs. |
| `/mrperf` | Console or staff | Prints performance and cache metrics. |
| `cleanupcodes` | Server console | Removes expired codes older than the configured retention window. |
| `clearcodes` | Server console | Deletes all codes from the database. |

## Exports

All server exports are available through `exports['midnight_redeem']:<ExportName>(...)`.

### `GenerateRedeemCode`
Creates a redeem code programmatically from another resource or automation.

```lua
local rewards = json.encode({
    { item = "credit_voucher", amount = 1 },
    { money = true, amount = 5000, option = "bank" }
})

exports['midnight_redeem']:GenerateRedeemCode(
    0,            -- source (0 for server-side automation)
    rewards,      -- rewards JSON
    10,           -- uses
    7,            -- expiry days or "Never"
    "FINANCE2025",
    1,            -- optional per-user limit
    "Automation", -- optional createdBy override
    nil,          -- optional time restrictions
    nil           -- optional player restriction
)
```

### `hasPermission`
Checks whether a player can perform an action such as `CREATE_CODES` or `MANAGE_PERMISSIONS`.

```lua
if exports['midnight_redeem']:hasPermission(source, "MANAGE_PERMISSIONS") then
    -- permitted
end
```

### `getUserRole`
Returns the caller's saved role.

```lua
local role = exports['midnight_redeem']:getUserRole(source) or "staff"
```

### `getUserPermissionLevel`
Returns the numeric permission tier for the caller.

```lua
local level = exports['midnight_redeem']:getUserPermissionLevel(source) or 0
```

### `setUserRole`
Updates a player's role after permission checks pass.

```lua
local success, message = exports['midnight_redeem']:setUserRole(source, targetPlayer, "manager")
```

### `grantOwnerPermission`
Used by `/midnight_admin_init`, but can also be called from your own setup tooling.

```lua
local ok, err = exports['midnight_redeem']:grantOwnerPermission(source)
```

### `removeUserPermissions`
Deletes a stored permission record.

```lua
exports['midnight_redeem']:removeUserPermissions(source)
```

### `getAllUserPermissions`
Returns all stored permission entries used by the dashboard.

```lua
local users = exports['midnight_redeem']:getAllUserPermissions()
```

### Configuration exports from `server/permissions.lua`
- `GetOwnerLicenses()`
- `GetRequirePermission()`
- `GetDefaultRole()`
- `GetPermissionActionsConfig()`

> Client exports: none. The UI communicates through callbacks and events.

## UI Overview
- Dashboard statistics for total, active, expired, and fully redeemed codes
- Code creation, editing, bulk delete, and template workflows
- Permission management with search and role editing
- Daily reward management and monitoring
- Shadow AI chat, transcript browsing, and version information
- Theme and locale preferences stored in the NUI

## Optional Discord Command
If you use `zdiscord`:

1. Copy `zdiscord_command_file/generateredeem.js` into `zdiscord/server/commands/`.
2. Ensure `zdiscord` starts after `midnight_redeem`.
3. Reload both resources or restart the server.
4. Use `/generateredeem` in Discord.

## Support
[Join the support Discord](https://discord.gg/8YpYsafebn)