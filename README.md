# ProcFlare

Lightweight proc alerts for WoW Forever.

**Website and live demo:** https://bencepo.github.io/procflare/

- **Clearcasting:** big pulsing icon above your character as long as the buff is up, with the seconds left, a sound and a short blue flash at the screen edges. Works for Omen of Clarity (druid), Arcane Concentration (mage) and Elemental Focus (shaman), and for Shadow Trance from Nightfall (warlock, in purple).
- **Other procs:** weapon enchants such as Crusader, trinkets and talent procs show as small icons with a countdown and a softer sound. Nothing to set up: any new short buff that comes from you and that you did not cast yourself counts as a proc, so new weapons and trinkets are picked up on their own.
- **Reactive abilities:** Overpower and Revenge (warrior), Riposte (rogue), Mongoose Bite and Counterattack (hunter) show for the few seconds after a dodge, parry or block opens them.
- **Also in combat:** the known procs of your class (Flurry, Enrage, Vengeance, Redoubt, Remorseless Attacks, Quick Shots, Spirit Tap, Focused Casting, Nature's Grace) and Crusader are still found while the game hides buff details.
- **Procs on your target:** debuffs your weapon or talents put on your target, such as Icy Chill or Spell Vulnerability.
- **Proc counter (optional):** how often each proc fired in this fight and in the last fight. Starts over when you enter combat, or by hand.
- **Mute what you do not need:** in move mode your recent procs are shown, right-click one to mute or unmute it.

## Settings

Everything is set in ProcFlare's own window, no commands needed. Drag it anywhere: it stays open while you play, so every change shows at once.

- **`/pfl`** (or `/procflare`): opens the window. `/pfl test` preview, `/pfl move` move mode, `/pfl reset` new proc count, `/pfl counter` counter on or off, `/pfl debug` debug output on or off
- **Minimap button:** left-click the window, shift-click move mode, right-click preview
- **Addon menu** next to the minimap
- **Options > AddOns > ProcFlare** points to the window

What you can change: sound pack (Melee or Caster, picked from your class), Clearcasting alert, its sound and the screen flash; volume and the game's sound channel it plays on; other procs and their sound; only your own procs; the longest buff that still counts as a proc (30 s by default); size; position; proc counter and when it starts over.

## Limits

Procs that only deal damage (Fiery Weapon, Lifestealing) or grant an extra attack (Hand of Justice, Windfury) cannot be shown: Forever keeps the combat log from addons.

Forever hides buff data from addons in restricted content (some boss encounters, battlegrounds). There ProcFlare still tries to show Clearcasting, other procs are not shown.


## Feedback and bug reports

Found a bug or have an idea? [Open an issue](https://github.com/Bencepo/ProcFlare/issues/new/choose), it takes a minute. For bugs the Lua error text (from BugSack, or `/console scriptErrors 1`) and your ProcFlare version help the most. No GitHub account? Comment on [CurseForge](https://www.curseforge.com/wow/addons/procflare#comments). Every report gets read.

## More addons by Bencepo

All addons, live demos and the web pages: **https://bencepo.github.io**

Like the addons? Support them on Ko-fi: **https://ko-fi.com/bencepo**

## AI disclosure

The code was written with the help of an AI assistant (Claude). Bencepo designed the features, tests everything in game and maintains the addon.

## License

All rights reserved, see [LICENSE](LICENSE).
