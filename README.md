# Warcamp

An idle game that lives inside World of Warcraft. Run a camp of recruits (not your real characters):
send them gathering, questing, into dungeons and raids, craft gear, trade on the market, upgrade
buildings and collect mounts and pets. Check in while you wait for a queue or fly across a zone,
collect, send them out again, and carry on playing.

Fully WoW styled: Blizzard frames and atlases, real item icons, 3D models for recruits, enemies,
bosses, mounts and pets.

## Use

- `/warcamp` (or `/wcamp`) opens the camp; the minimap button and the addon compartment do too.
- `/warcamp options` opens Options > AddOns > Warcamp.
- `/warcamp export` / `/warcamp import` copy your camp to and from a text string.
- `/warcamp help` lists everything.

## Your save

Progress is stored account-wide in `WTF/Account/<account>/SavedVariables/Warcamp.lua`. Updating the
addon never touches that file. Before an update changes the save layout, and before any import,
restore or reset, the current camp is kept as a backup you can restore from the options page.

## Development

`Tests/` holds a headless harness (not shipped):

```
lua Tests/run.lua real
lua Tests/ui_smoke.lua
```

`DESIGN.md` is the code contract between data, engine and UI.

## License

All Rights Reserved. See `LICENSE`.
