# Notes for Claude

ProcFlare: proc alerts for WoW Forever (Lua 5.1). Author and rights holder: Bencepo. All rights reserved, no open-source license.

## Layout

- `ProcFlare.lua`: everything (aura scan, alerts, sounds, proc counter, settings window, minimap button, events).
- `Sounds/`: ProcFlare's own sounds, `<name>_<volume>.ogg` in four volume steps (25/50/75/100). Melee and caster sound packs are Ben's unique selling point.
- `Icons/minimap.tga`: in-game icon (addon list, minimap), 64x64 TGA from the Bencepo logo family. `media/logo.png`: logo for CurseForge, Wago and the website (not packaged).
- `Libs/`: LibStub, CallbackHandler, LibDataBroker, LibDBIcon, BencepoUI (shared settings window; bump its LibStub minor on changes).

## How it works

- A proc is any new buff on the player that lasts at most `maxDuration` (30 s), comes from the player and was not cast just before. No list to maintain.
- Clearcasting-like procs (`BIG`: druid, mage, shaman, warlock Shadow Trance) get the big pulsing icon, sound and screen flash.
- Forever hides buff details from addons in combat ("secret" values; reading them errors). Every aura read goes through `C_Secrets.ShouldUnitAuraIndexBeSecret` / `issecretvalue`. Known proc buffs per class (`WATCH`) are queried by spell id so they still show in combat.
- Procs of other classes are only active for the class being played.
- Reactive abilities after dodge/parry/block (Overpower, Revenge, Riposte ...) are optional.

## Rules

- English only: UI texts, commands, descriptions. No translations, no `Notes-xxXX` in the .toc. Settings in the BencepoUI window, not in Blizzard's options.
- `Libs/BencepoUI` is shared by all Bencepo addons and must be the same file in each (canonical copy: minor 3, Nov 2026, with `UI:ShowLink` and the footer for "Report a bug"). LibStub loads only the highest minor, so two different copies with the same minor make the result depend on load order. Change it in one repo, bump the minor, copy it to the others.
- CI runs luacheck and LuaLS with the WoW API annotations; LuaLS must report zero diagnostics or the release stops.
- Release: new version heading at the top of `CHANGELOG.md`, push to `main`; the workflow uploads to CurseForge and Wago. Ben wants fast releases: after his test and go, straight to release. The release reaches players right away.
