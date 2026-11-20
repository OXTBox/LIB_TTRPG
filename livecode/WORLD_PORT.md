# The old studio's world code: what became of each handler (OPUS_BUILD step 9, 19 Nov 2026)

Source: `TTRPGtudioapilib_02092026__stack.livecodescript` (Feb 2026, harvested in
`LIB_LLMOUT/Read/LIB_XTJSON/XTJSON_batch_11_13_2026/batch/TTRPG_STUDIO_020920229AM`).
Spec: `ref/ttrpg_world.py`; port: `livecode/lib_ttrpg_world.livecodescript`; vectors: `ref/world_vectors.json`.

**The big change:** the old code kept worlds in the stack's custom property sets (`World`, `nouns`,
`merchandise`, `Lists`, `user_selections`) and in globals. Now a world is one array the caller holds;
words are read from LIB_LISTS by name at run time; files go through LIB_DATA (`Games/TTRPG/worlds`).

| Old handler | Now |
|---|---|
| `init.RandomMapGenerator`, `entity.type.x.y.z.world`, `insert.location.entities` | `TTRPG.World.New` (an NPC / monster now on 25% / 20% of cells, not every cell) |
| `BuildActor`, `generate.container.and.AdventureGear`, `default.array.properties`, `random_object` | inside `New` / `Spawn` (gear from `Lists/Equipment`; the old shop list held one item) |
| `class.attributes.array.generator` | `TTRPG.World.Attributes` (the old one put the roll into the key name too) |
| `player.random.spawn`, `world.random.location.name` | `TTRPG.World.Spawn`, `TTRPG.World.CellAt` |
| `entities.at.colrowname`, `entities.at.col.row` | `TTRPG.World.CellOf` + `location` on each npc / monster |
| `GetVisibleRoomStateForPlayer` | `TTRPG.World.Tile` (also hides closed / locked contents and hidden containers) |
| `BuildPlayerTurnPrompt`, `BuildTileDescription`, `string.location.summary` | `TTRPG.World.View` (text), `TTRPG.World.TilePrompt` (`prompts/world_tile.txt`) |
| `ttrpg.entity.styler.prompt`, `nouns.npc.lore.text`, `npc.set.role.to.name` | `TTRPG.World.NPCPrompt` (`prompts/world_npc.txt`); role + lore from `roles/<Role>.txt` |
| `InterpregPlayerAction` (renamed; its helpers were never written) | `TTRPG.World.Act`: look, take, drop, open, close, unlock, search, go / n s e w |
| `AddItemToActor`, `RemoveItemFromActor`, `MoveItemBetweenContainers` | inside `Act` (take / drop) |
| `SaveWorldObjectToJSON` (two copies, the second shadowed the first), `SaveActorToJSON`, `SaveLocationToJSON`, `Load...FromJSON`, `SaveAllWorldObjectsToJSON` | `TTRPG.World.Save` / `Load`, `SaveObject` / `LoadObject` |
| `ttrpg.player.system.prompt` | not carried: the Studio's `prompts/player.txt` does this |
| `LM_Init` (URL typo `127.0.01`), `LM_BuildRequestJSON`, `LM_TestConnection`, `initTurn`, `BuildTurnPacket`, `GetPrompts`, `GetFirsgWorldAssets` | not carried: `lib_ttrpg_lm` (step 1) replaced them |
| menus, tabs, `UI.fill.*`, `select.*`, `custompropertyset(s).copy`, `wtf`, `init.globals` | not carried (UI of the old window; property-set copying is what LIB_LISTS replaced) |

New, not in the old code: walking between cells, `search` (hidden items come into view), closed and
locked boxes at locations, `SceneIdea` (a New Scene idea from the player's cell) and `CharacterAsk`
(an Add Character ask from an NPC). Word lists: the old `nouns` / `roles` / `Lists` sets were
already in LIB_LISTS (75 of 77 properties match by checksum; the rest are prompts and UI state).
