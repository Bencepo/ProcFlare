# ProcFlare

Lightweight proc alerts for WoW Forever.

- **Clearcasting:** big pulsing icon above your character as long as the buff is up, with the seconds left, a sound and a short blue flash at the screen edges. Works for Omen of Clarity (druid), Arcane Concentration (mage) and Elemental Focus (shaman).
- **Other procs:** weapon enchants such as Crusader, trinkets and talent procs show as small icons with a countdown and a softer sound. Nothing to set up: any new short buff that comes from you and that you did not cast yourself counts as a proc, so new weapons and trinkets are picked up on their own.
- **Procs on your target:** debuffs your weapon or talents put on your target, such as Icy Chill or Spell Vulnerability.
- **Mute what you do not need:** in move mode your recent procs are shown, right-click one to mute or unmute it.

## Settings

Everything is set with buttons, no commands needed:

- **Options > AddOns > ProcFlare**
- **Minimap button:** left-click options, shift-click move mode, right-click preview
- **Addon menu** next to the minimap

What you can change: sound pack (Melee or Caster, picked from your class), Clearcasting alert, its sound and the screen flash; volume and the game's sound channel it plays on; other procs and their sound; only your own procs; the longest buff that still counts as a proc (30 s by default); size; position.

## Limits

Procs that only deal damage (Fiery Weapon, Lifestealing) or grant an extra attack (Hand of Justice, Windfury) cannot be shown: Forever keeps the combat log from addons.

Forever hides buff data from addons in restricted content (some boss encounters, battlegrounds). There ProcFlare still tries to show Clearcasting, other procs are not shown.

## Goes well with SwingCast

[SwingCast](https://www.curseforge.com/wow/addons/swingcast) by the same author: spell icon, cast time, latency zone and a swing timer on the standard cast bar, tinted while Maul, Heroic Strike or Cleave is queued.

## AI disclosure

The code was written with the help of an AI assistant (Claude). Bencepo designed the features, tests everything in game and maintains the addon.

## License

All rights reserved, see [LICENSE](LICENSE).
