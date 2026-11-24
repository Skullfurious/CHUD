# CHUD (Compass HUD): project standards

A compass bar addon for World of Warcraft Forever (Interface 16001). Single author, aimed at a polished release. Read this before changing anything.

## Fixed rules

1. **Saved themes are lossless between updates.** This is permanent and is not up for per-request override.
   - Never delete, rename, reorder or rewrite a user's saved themes (`db.themes`) in any update, migration, reset or fresh-start path. Only the user's own explicit Delete action removes one.
   - Every reset or wipe (`ns.Reset`, `/chud reset`, `/chud install`, the `SETUP_VERSION` fresh start, schema migrations, any new code) must carry `db.themes` across untouched.
   - Themes saved before a key existed must keep working. Missing keys fall back to defaults through `GetThemeData`; do not require old saves to be re-saved.
   - Do not repurpose or change the meaning of a stored theme key. Adding a key is fine. Removing one needs a migration that preserves the look the user saved.
   - Built-in theme changes must never overwrite a user's saved theme of the same name.
   - Preferences that are not part of a look stay out of themes (`EXCLUDE` in `Themes.lua`: lock state, width, CPU setting, `mk_native`, and similar). Do not put them back.
   - Any change touching themes, saved variables or resets needs a check that an existing saved theme survives it.
2. **Only change addons the user created.** Other addons are read, never modified. CHUD never writes to GatherLite, GatherMate2, RareScanner or Questie. Gathering data is imported by the player from the installed addon. The one exception: during an import CHUD may switch a GatherLite tracking type on and must restore it exactly afterwards (GatherLite loads a type only while it is tracked). Rare NPC data and kill tracking are built into `RareData.lua` (merged from RareScanner and Questie with permission, credited in README.md).
3. **`CHUD.toc` never lists a file from another addon, and CHUD ships as one addon with no companion addons.** A file from another addon causes a loading warning for anyone who does not have it. Data that is needed goes into CHUD itself.
   Forever also refuses addons that register for `COMBAT_LOG_EVENT_UNFILTERED` (the game shows a "blocked from an action" popup at login). Use target, loot and chat events instead. CHUD prints any blocked action of its own in chat (`ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN`).
4. **Do not push to GitHub, tag or create releases unless the user says so.**

## Where things live

Load order is in `CHUD.toc`: `CHUD.lua`, `Themes.lua`, `RareData.lua`, `Markers.lua`, `Highlight.lua`, `Fade.lua`, `Tooltip.lua`, `Settings.lua`, `Install.lua`.

- `CHUD.lua`: bar, compass, XP fill and tooltip hook, defaults (`ns.defaults`), saved-variable migration, `ns.Reset`, slash commands, default Blizzard XP bar hiding.
- `Themes.lua`: built-in themes, Daylight, theme keys, apply/match/save.
- `Markers.lua`: targets, active icons, Next Node pointer, reach and visit logic, gathering import, layout, demo markers.
- `Highlight.lua`: node highlight, soft-interact settings, reached or not-here decision.
- `Fade.lua`: fading rules and opacity.
- `Tooltip.lua`: CHUD's own XP tooltip.
- `Settings.lua`: settings page, marker menu, shared widgets (`ns.UI`).
- `Install.lua`: setup tour.
- `RareData.lua`: generated rare NPC table (`ns.RareData[uiMapID][npcID] = {level, name, {x,y,...}}`, coordinates are map percent x 100). Do not edit by hand.
- Never call the game's own UI functions (for example status bar managers) from addon code: it taints the game's code and blocks protected actions such as Edit Mode.

## Code standards

- Every function has a comment saying what it does. Keep comments accurate when code changes; delete stale ones.
- No unused code, settings, locals or dead branches. Remove an obsolete setting by adding its key to the `OBSOLETE` list.
- No new globals. Use locals and the shared `ns` table.
- Wrap game API calls that can fail in `pcall` or the `Try` helper. Values the game marks secret (`issecretvalue`) must not be compared, so check first and fall back to the last readable value.
- Keep per-frame work cheap: avoid allocations in `OnUpdate`, only call into the game when a value changed, and respect the Low-CPU Rendering setting.
- Defaults live in `ns.defaults`. New saved settings get a default there. Bumping `SCHEMA` or `SETUP_VERSION` is a deliberate release decision (`SETUP_VERSION` wipes settings and imported data once, keeping themes).
- Popups and dialogs opened from CHUD's menus must sit above them (`TOOLTIP` strata).
- Syntax-check every Lua file after editing. A Lua change needs `/reload` to take effect; a new file or a TOC change needs a full game restart.

## UI standards

- Every control has a tooltip, and the tooltip says exactly what the control does, including side effects and what it depends on.
- When a feature has no data behind it, say so on the control (orange label and explanation).
- Nothing imports data automatically. Imports happen from the setup tour or an explicit button.
- Only these commands are public: `/chud`, `unlock`, `lock`, `center`, `reset`, `install`. `/chud debug` stays hidden and out of the menus.
- Design for a premium feel: consistent spacing, no overlapping text, equal heights for side-by-side panels, smooth fades.
- Default settings are chosen for new users. Existing preferences are respected on update, except where a release deliberately resets them.

## Writing standards

- Public text (README, changelog, release notes, project page) is plain and factual. No emojis, no marketing tone, no filler.
- Avoid the "not X, but Y" sentence pattern.
- Release notes list changes only: a short summary, **New**, **Fixed**. No install section.

## Release checklist

1. Bump `## Version` in `CHUD.toc`.
2. Update `CHANGELOG.txt` and `README.md`.
3. Syntax-check and lint every file; confirm every file in the TOC exists.
4. Confirm saved themes survive the update.
5. Commit with the trailer lines the session requires. The release is a single commit.
6. Build the zip with one top-level `CHUD/` folder (from `git archive`, no `.git`).
7. Push, tag and publish only when the user asks.

## Working with the user

- The user tests in game and reports back. Say plainly what was and was not verified.
- Be direct and realistic. No flattery.
- Group questions as a bulleted list at the end of a message.
- When explaining multi-step work or command-line steps, explain why each step is taken, and explain flags.
