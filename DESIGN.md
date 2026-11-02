# Warcamp — design and code contract

An idle / AFK game that lives inside WoW. You run a camp of recruits (NOT your real characters),
send them on timed missions (gathering, questing, dungeons, raids), craft gear, trade on a market,
upgrade buildings and collect mounts and pets. You check in now and then — while waiting for a queue,
on a flight path, between pulls — collect, re-assign, log off. Fully WoW-styled: Blizzard frame
templates and atlases, real item icons and tooltips styling, real coin text, 3D creature models
for recruits, enemies, bosses, mounts and pets.

Tone: serious WoW feel (Horde/Alliance flavour from the player's faction). Pace: mixed — gathering
and quests 5 min to 2 h, dungeons 1–4 h, raids 8–12 h weekly, buildings 10 min to 24 h.

This file is the contract between the data, engine and UI code. If you need something the contract
does not give, add it in a way that keeps every signature below working, and say so in your report.

## Hard rules (this client: retail 12.1.x "Midnight")

- Lua 5.1 only: no `goto`, no `//`, no bitwise operators, no `<const>`, no integer/float distinction.
- One namespace: every file starts `local ADDON, ns = ...`. No globals except `WarcampDB` (SavedVariables),
  the slash command globals, `BINDING_*` if any, and the AddonCompartment function names.
- **Never call `Frame:UnregisterEvent`** (it triggers the "blocked from Blizzard UI" popup on this client).
  Register every event at file scope in Main.lua, never from inside an event handler; gate with booleans.
- Never register `COMBAT_LOG_EVENT_UNFILTERED`; never read auras. Never call `SetCVar`, never touch
  key bindings, never play sounds, never raise screen alerts / raid warnings / pings. The game is quiet:
  the only "notification" is a ready-count on the minimap button and in the window.
- Every WoW API that might be missing or take a bad ID goes through `pcall` and degrades (model → icon,
  atlas → plain texture, EJ art → none).
- No OnUpdate work while the window is hidden, except one cheap 5-second ticker for the minimap count.
- Time is `time()` (epoch seconds, survives logout). Never `GetTime()` for game state.
- Gold is stored in **copper** (integer). Show with `GetCoinTextureString(copper)` / `C_CurrencyInfo.GetCoinTextureString`.
- Dense UI (the user's explicit preference): rows 18–22 px, a lot visible at once, a model or summary
  next to every list. Blizzard look, never at the cost of density.

## Files and load order (Warcamp.toc)

```
Core\Init.lua          ns.Util, ns.On/ns.Fire event bus, ns.Atlas helper, constants   (leader)
Data\Classes.lua       D.CLASSES, D.THREATS, D.ROLES, D.TRAITS, D.LOOKS              (data)
Data\Names.lua         D.NAMES                                                        (data)
Data\Items.lua         D.ITEMS, D.GEAR_SLOTS, D.GEAR_BASES, D.QUALITY                  (data)
Data\World.lua         D.TIERS, D.ZONES                                               (data)
Data\Instances.lua     D.DUNGEONS, D.RAIDS                                            (data)
Data\Camp.lua          D.BUILDINGS, D.RECIPES, D.BUFFS                                (data)
Data\Collection.lua    D.MOUNTS, D.PETS, D.ACHIEVEMENTS                               (data)
Engine\State.lua       db init/migration, ids, RNG, log, stats                        (engine)
Engine\Heroes.lua      recruit generation, xp/levels, gear, power                     (engine)
Engine\Board.lua       mission offers (gather/quest/dungeon/raid), preview/chance      (engine)
Engine\Tasks.lua       start/collect/cancel, repeat, offline catch-up                 (engine)
Engine\Economy.lua     inventory, market prices, crafting, buildings, inn             (engine)
Engine\Progress.lua    achievements, collection, buffs, prestige ("New Era")           (engine)
UI\Kit.lua             widget library                                                 (ui-kit)
UI\Frame.lua           main window, tab host, header bar                              (ui-kit)
UI\Camp.lua            Camp tab                                                       (ui-kit)
UI\Heroes.lua          Heroes tab                                                     (ui-a)
UI\Missions.lua        Missions tab (gather + quest)                                  (ui-a)
UI\Dungeons.lua        Dungeons & Raids tab                                           (ui-a)
UI\Crafting.lua        Crafting tab                                                   (ui-b)
UI\Market.lua          Market tab                                                     (ui-b)
UI\Collection.lua      Collection + Achievements tab                                  (ui-b)
UI\Minimap.lua         minimap button + compartment                                   (ui-kit)
Main.lua               events, login catch-up, slash commands, /warcamp verify            (leader)
Tests\*.lua            headless harness (not in toc)                                  (engine)
```

`ns.D` is the data root. `ns.Game` is the engine object. `ns.UI` is the UI root.

## Core\Init.lua (exists; written by the leader)

- `ns.D = {}`, `ns.Game = {}`, `ns.UI = {}`.
- `ns.On(event, fn)`, `ns.Fire(event, ...)` — synchronous bus. Engine fires, UI listens.
  Events: `"CHANGED"` (arg: what = "tasks"|"heroes"|"inventory"|"gold"|"buildings"|"collection"|"log"|"inn"|"all"),
  `"REPORT"` (arg: report table from a collect, for the UI to show a loot summary).
- `ns.Util.Duration(secs)` → "2h 05m", "14m", "45s". `ns.Util.Clock(t)` → "14:05".
- `ns.Util.Copy(t)`, `ns.Util.Clamp(x,a,b)`, `ns.Util.Round(x)`, `ns.Util.Count(t)`, `ns.Util.Shuffle(t, rng)`.
- `ns.Atlas(tex, name, useAtlasSize)` → true if the atlas exists and was set, else false (caller then sets a fallback).
- `ns.QUALITY_COLOR(q)` → r,g,b and hex for item quality 0–5 (uses `C_Item.GetItemQualityColor` / `ITEM_QUALITY_COLORS`).
- `ns.ItemIcon(itemID, fallback)` → icon fileID via `C_Item.GetItemIconByID`, pcall'd, else fallback, else question mark.

## Data contract (ns.D)

All keys are UPPER_SNAKE strings unless noted. Real Blizzard IDs (itemID, mountID, speciesID, journal
instance ID, creature display ID, mapID) must be **real** — research them (wago.tools db2 tables,
wowhead, warcraft.wiki.gg). Any ID you are not sure about gets `-- ?` at the end of its line. `/warcamp verify`
will check every ID in game and list the bad ones, so it is fine to be wrong occasionally, not fine to invent.

```lua
D.ROLES = { TANK = {name="Tank", atlas="roleicon-tank"}, HEALER = {...}, DAMAGER = {...} }

D.THREATS[key] = { name="Magic Debuff", icon=<fileID or path>, desc="..." }   -- ~9 of them
D.CLASSES[classFile] = {          -- Blizzard class tokens: WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST,
  name = "Warrior",               -- DEATHKNIGHT, SHAMAN, MAGE, WARLOCK, MONK, DRUID, DEMONHUNTER, EVOKER
  roles = {"TANK","DAMAGER"},
  counters = {"MASSIVE_STRIKE","WILD_AGGRESSION"},   -- 2–3 threat keys this class counters
  gather = "MINING",              -- the gathering profession this class is a little better at (+10%)
}
D.TRAITS[key] = { name, desc, icon, kind="GATHER_YIELD"|"SPEED"|"XP"|"GOLD"|"CHANCE"|"LOOT"|..., value=0.15,
                  filter = nil | "MINING" | "DUNGEON" | ... }   -- 20+ traits, a few negative ones
D.LOOKS[classFile] = { {display=<creatureDisplayID>, race="Human", sex="M", faction="Alliance"|"Horde"|"Neutral",
                         npc="NPC it comes from"}, ... }  -- 6–10 per class, mix of races & both sexes & factions
D.NAMES[race] = { M={...}, F={...}, last={...} }   -- original fantasy names, 30+ per list, no real WoW characters

D.QUALITY = { [1]="Common", [2]="Uncommon", [3]="Rare", [4]="Epic", [5]="Legendary" }
D.ITEMS[key] = { name, itemID=<real>, icon=<fallback path>, quality, tier=<1..12>,
                 kind="ORE"|"HERB"|"LEATHER"|"FISH"|"CLOTH"|"BAR"|"POTION"|"FOOD"|"MISC"|"RARE",
                 price=<base copper> }
D.GEAR_SLOTS = { "HEAD","SHOULDER","CHEST","HANDS","LEGS","FEET","WEAPON","TRINKET" }   -- order = paperdoll
D.GEAR_BASES[tier][slot] = { {itemID=<real>, name="..."}, ... }  -- 2–4 real items per slot per tier, used for icon + name

D.TIERS[i] = {                   -- 12 tiers, one per expansion, i = 1..12
  key="CLASSIC", name="Classic", expansion=0 (LE_EXPANSION_*),
  level={1,10}, ilvl={5,40},      -- hero levels & item levels covered by this tier
  mats = { ORE=key, HERB=key, LEATHER=key, FISH=key, CLOTH=key },  -- item keys gathered/looted here
  rare = key,                     -- rare drop for the tier (e.g. a gem / Primal / Spark)
}
D.ZONES[i] = { key, name, tier, level=<recommended>, mapID=<real uiMapID>,
               mobs = { {display=<id>, name="Defias Bandit"}, ... },     -- 3–6 per zone, the enemies you see
               quests = { "The Defias Brotherhood", ... },               -- 6+ flavour mission names, original wording ok
               gather = {"MINING","HERBALISM","SKINNING","FISHING"} }    -- which nodes this zone has
                                                                          -- 3 zones per tier (36 zones)
D.DUNGEONS[i] = { key, name, tier, level, journalID=<EJ journalInstanceID>,
                  bosses = { {name=, display=<id>, threats={"MAGIC_DEBUFF","GROUP_DAMAGE"}}, ... }, -- 3–5
                  mount = nil | {mountID=<real>, chance=0.01}, pet = nil | {speciesID=<real>, chance=0.03} }
                  -- 2–3 dungeons per tier, real ones
D.RAIDS[i]    = same shape, 1 per tier, more bosses, mount/pet chances
D.BUILDINGS[key] = { name, icon, desc, maxLevel,
                     levels = { [1]={gold=, items={[key]=n}, time=<secs>, effect="+1 mission slot"}, ... } }
                     -- TOWN_HALL (gates others), BARRACKS (hero cap), MINE, HERB_GARDEN, LUMBER? no — keep:
                     -- TOWN_HALL, BARRACKS, INN, MINE, GARDEN, FORGE, ALCHEMY_LAB, KITCHEN, STABLES,
                     -- TRAINING_GROUNDS, TRADING_POST, TREASURY
D.RECIPES[key] = { name, building="FORGE"|"ALCHEMY_LAB"|"KITCHEN", buildingLevel, tier,
                   inputs={[itemKey]=n}, gold=<copper>, time=<secs>,
                   output = {item=key, n=1} | {gear=slot|"ANY", tier=t, quality=3} }
D.BUFFS[key] = { name, icon, desc, kind="SPEED"|"XP"|"GOLD"|"CHANCE"|"YIELD", value, duration }
D.MOUNTS = { {mountID=<real>, source="Stratholme" or "Achievement: ..."}, ... }  -- union of all drop/reward mounts
D.PETS   = { {speciesID=<real>, source=...}, ... }
D.ACHIEVEMENTS[i] = { key, name, desc, points, icon, stat="GOLD_EARNED"|"TASKS"|..., value=<n>, reward=nil|{mountID=}|{title=} }
```

## Engine contract (ns.Game)

State lives in `WarcampDB` (account-wide). The engine owns it; UI code reads hero/task/gear tables
directly (read only) and changes anything only through these functions. Every mutating function fires
`ns.Fire("CHANGED", what)` and returns `ok, err` (err = short player-facing string) unless noted.

```lua
Game:Init()                 -- after ADDON_LOADED: create/migrate WarcampDB, seed first recruits (3, quality 2)
Game:Update(now?)           -- idempotent catch-up to now: finish buildings, passive production (Mine/Garden,
                            -- capped by storage), repeat-loops of repeating tasks (capped at 12 h offline),
                            -- expire buffs/offers, refresh inn/board. Cheap when nothing is due.
Game:Welcome()              -- report table of what happened while away (since last session); nil if < 5 min

-- heroes
Game:GetHeroes()            -- array of hero tables, sorted (level desc, then name)
Game:GetHero(id)
Game:HeroIlvl(h)  Game:HeroPower(h)  Game:HeroXPNeeded(h)  Game:HeroStatus(h) -> "IDLE"|"BUSY"|"READY"
Game:HeroLook(h)            -- {display=, race=, sex=} from D.LOOKS
Game:MaxHeroes()  Game:MaxLevel()
Game:GetRecruitOffers()     -- {offers={ {hero-like table, cost=<copper>} x3 }, refreshAt=<t>}
Game:Recruit(i)  Game:RerollRecruits()  Game:RerollCost()  Game:Dismiss(heroId)
Game:Equip(heroId, gearId)  Game:Unequip(heroId, slot)  Game:AutoEquip(heroId)  -- best ilvl per slot
Game:GetGearBag()           -- array of gear tables not equipped, ilvl desc
Game:SellGear(gearId)       -- returns copper gained

hero = { id, name, race, sex, class, role, quality=2..4, level, xp, look=<index>, gear={[slot]=gear},
         traits={key,...}, skills={MINING=n, HERBALISM=n, SKINNING=n, FISHING=n}, taskId=nil|id, recruitedAt }
gear = { id, slot, tier, ilvl, quality, name, itemID }

-- missions
Game:GetZones()             -- array of {zone=D.ZONES[i], unlocked=bool, reason}
Game:GetBoard(kind, zoneKey)-- kind "GATHER"|"QUEST": offers for that zone; "DUNGEON"|"RAID": zoneKey ignored
offer = { key, kind, name, desc, tier, level, ilvl, minHeroes, maxHeroes, roles=nil|{TANK=1,HEALER=1,DAMAGER=3},
          duration, threats={key,...}, display=<model id for the enemy/boss>, zone=key|nil, instance=key|nil,
          profession="MINING"|nil, rewards={gold=, xp=, items={[key]=n}, gear={chance=, ilvl=, quality=},
          mount=nil|{mountID,chance}, pet=nil|{speciesID,chance}}, locked=bool, lockReason=string|nil,
          weeklyDone=bool (raids) }
Game:Preview(offerKey, heroIds) -- {ok, reason, chance=0..1, duration, countered={[threat]=true},
                                --  missingRoles={...}, xpEach, rewards=<scaled>, notes={"Miner's Luck +15% ore", ...}}
Game:Start(offerKey, heroIds, repeatIt) -- task|nil, err
Game:Suggest(offerKey)      -- array of heroIds: best idle party for that offer (for an "Auto-fill" button)
Game:GetTasks()             -- array of active tasks, soonest endAt first (includes CRAFT and BUILD)
task = { id, kind, offerKey, name, heroes={ids}, startAt, endAt, chance, repeatIt, display, icon }
Game:TaskReady(task, now)   Game:ReadyCount(now)
Game:Collect(taskId)        -- report|nil, err   (fires "REPORT")
Game:CollectAll()           -- merged report
Game:Cancel(taskId)         -- heroes return, nothing gained
report = { success=bool (or counts), gold, xp={[heroId]=n}, levelUps={[heroId]=newLevel}, items={[key]=n},
           gear={gear,...}, mounts={mountID,...}, pets={speciesID,...}, achievements={key,...}, lines={"..."} }

-- economy
Game:Gold()  Game:Count(itemKey)  Game:GetInventory()   -- array {key, count, item}
Game:Price(itemKey, now)    -- buy, sell (copper). Deterministic drifting price, same online/offline.
Game:PriceHistory(itemKey, n, span) -- array of n sell prices across the last span seconds (sparkline)
Game:Buy(itemKey, n)  Game:Sell(itemKey, n|"ALL")
Game:GetRecipes()           -- array {recipe=D.RECIPES[k], key, canCraft, maxCraftable, reason}
Game:Craft(recipeKey, n)    -- queues as a CRAFT task (building queue, one at a time per building)
Game:GetBuildings()         -- array of info tables, see below
Game:GetBuilding(key)       -- {key, def, level, max, upgrading, endAt, cost={gold,items}, canUpgrade, reason,
                            --  effect, nextEffect, storage=nil|{have,cap,itemKey}}
Game:Upgrade(key)
Game:CollectStorage(key)    -- Mine/Garden passive output into inventory

-- progress
Game:GetBuffs()             -- array {key, def, expiresAt}
Game:GrantBuff(key)         -- used by Main.lua for real-world triggers
Game:GetCollection()        -- {mounts={[mountID]=t}, pets={[speciesID]=t}}
Game:GetAchievements()      -- array {def, earnedAt|nil, progress, goal}; Game:AchievementPoints()
Game:GetStats()  Game:GetLog()                -- log newest first {t, text}
Game:EraInfo()              -- {era, legacy, canAdvance, reason, bonus}   Game:AdvanceEra()
```

### Balance targets (engine owns the numbers)

- Session 1 (first 15 min): several 1–5 min tasks, first level-ups, first building upgrade, a 4th recruit.
- Day 1: tier 2 reached, first dungeon cleared. Week 1: ~tier 6. Full tier 12 + final raid ≈ 4–5 weeks
  of checking in 3–6 times a day. Then New Era (prestige): reset heroes/gold/buildings/inventory, keep
  collection + achievements, gain Legacy → permanent % bonuses, each era 15–20% faster.
- Success chance: party power vs offer ilvl/level, + countered threats, + correct roles. A fail still gives
  some XP and a little gold; never loses heroes. Chance shown to the player before Start.
- Offline repeat cap 12 h — the reason to check in twice a day.
- Mounts/pets are rare (0.5–3 %) and are the long-term chase; the Collection tab shows all the chase.

## UI contract (ns.UI)

```lua
ns.UI.RegisterTab{ key="HEROES", title="Heroes", order=2, build=function(panel) end, refresh=function(panel) end }
ns.UI.Show(tabKey?)  ns.UI.Toggle()  ns.UI.IsShown()  ns.UI.Refresh()  -- Refresh: visible tab only, once per frame
ns.UI.Kit.*              -- shared widgets, documented at the top of UI\Kit.lua
```
Window ~ 940 x 600, `PortraitFrameTemplate`/`ButtonFrameTemplate` style, movable, position saved, ESC closes
(`tinsert(UISpecialFrames, name)`), scale option. Header bar inside the frame: gold, ready count +
"Collect all", active buffs. Tabs at the bottom: Camp, Heroes, Missions, Dungeons, Crafting, Market, Collection.
Panels are built lazily on first show. Each tab refreshes on `CHANGED` only while visible; timers/progress
bars tick with one 0.5 s ticker that runs only while the window is shown.

## Contract additions made during the build

- Report fields: single collect `taskName`, `kind`, `tierUp`; merged `success`/`fail`/`tasks` counts and
  `buildings={{key,level}}`; Welcome `away`, `since`, `welcome=true`, `ready`.
- Functions: `SetRepeat(taskId,on)`, `UseItem(itemKey)`, `AutoEquipAll()`, `OfferPower(offer)`, `GetTask(id)`,
  `RecruitCost(q)`, `OfflineCap()`, `TierUnlockReason(t)`, `TierGateLevel(t)`, `TierHallLevel(t)`, `StatValue(stat)`,
  plus helpers the UI reads through Kit.Call: `Slots`, `SkillCap`, `GearValue`, `ZoneByKey`, `InstanceByKey`,
  `ZoneBoard`, `BuildingLevel`, `Bonus`, `CraftIlvl`, `MarketBonus`.
- `Buy`/`Sell`/`CollectStorage` return `ok, err, amount`; `Recruit` returns `ok, err, heroId`.
  `EraInfo` adds `gain`, `nextBonus`; `Preview` adds `xpBy`, `power`, `offerPower`;
  offers add `rewards.rare`, `rewards.gear.n`, `bosses`; buildings add `cost.time`.
- `Game.faction` is set by Main.lua before Init so recruits use the player's faction looks.
- UI: `RegisterTab` also takes `tick(panel, now)`; `ns.UI.ShowReport`, `Status`, `SetScale`, `Hide`,
  `UpdateMinimap`, `SetMinimapShown`.
- Rules: Collect all restarts repeating tasks; buildings finish on their own, crafts need Collect; one
  construction at a time (two from Town Hall 6); one craft per building; quest offers are used up on start;
  raids cannot repeat; a tier unlocks by clearing a dungeon of the current tier with a party averaging the
  tier's top level − 1, and needs Town Hall ≥ tier.

## Save safety (added for the public release)

- `Core\Serialize.lua`: `U.Serialize`, `U.Deserialize` (own parser, never `loadstring` on pasted text),
  `U.Base64Encode/Decode`, `U.Checksum`.
- `Engine\Save.lua`: `ExportString`, `ParseImport`, `ImportString`, `MakeBackup`, `GetBackup`,
  `RestoreBackup`, `ResetAll`, `Sanitize(db)`.
- `WarcampDB.ui`, `.backup` and `.verify` are per install: never exported, never replaced by an import.
- On every load: backup if `db.version < DB_VERSION`, then migrations, then `Sanitize` (drops keys the
  data no longer has, fixes NaN / inf numbers, frees heroes whose task is gone), then `ResetRun` fills gaps.
- **Changing the save layout:** bump `Game.DB_VERSION` and add `Game.MIGRATIONS[n]`. Never rename
  `WarcampDB`. Removing a data key is safe (Sanitize drops it); renaming one needs a migration.
- Allowed globals besides the rule above: `WarcampFrame` and `WarcampSaveFrame` (named for
  `UISpecialFrames`, so Escape closes them).
- `UI\Options.lua`: canvas page under Options > AddOns, plus the export / import window.
- **Append only:** anything the save stores as an index (`D.TIERS`, `D.LOOKS[class]` entries, building
  `levels`) may only be appended to. Reordering changes existing recruits and camps.
