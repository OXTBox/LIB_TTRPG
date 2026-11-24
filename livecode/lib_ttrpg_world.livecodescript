script "lib_ttrpg_world"
######################################################################################
## lib_ttrpg_world (LIB_TTRPG, 19 Nov 2026): the old TTRPG Studio's world code (Feb 2026,
## TTRPGtudioapilib_02092026), carried in by OPUS_BUILD step 9. A port of ref/ttrpg_world.py
## (the spec: change behaviour there first, run its `test`, then here).
##
## The old code kept the world in the stack's custom property sets and globals; here a world is
## one array that the caller holds and passes in. Nothing is stored in a stack.
## Words come from LIB_LISTS BY NAME at run time (nouns/locations, nouns/monsters, nouns/ecosystem,
## nouns/containers, Lists/Equipment, Lists/example_location_descriptions, roles/<Role>.txt).
## Saving needs lib_ttrpg (TTRPG.Path) and lib_ttrpg_lm (TTRPG.JSON.Export / Parse).
##
##   TTRPG.World.New(pName, pCols, pRows)       a random world (array)
##   TTRPG.World.Spawn @pWorld, pName           a player on a random cell; the result = its name
##   TTRPG.World.Act @pWorld, pPlayer, pText    look / take / drop / open / close / search / go;
##                                              the result = the reply, empty = not a world action
##   TTRPG.World.View(pWorld, pPlayer)          what the player sees, as text
##   TTRPG.World.Tile(pWorld, pLocation)        the visible-only tile array (for prompts/world_tile.txt)
##   TTRPG.World.TilePrompt / NPCPrompt          prompts/world_tile.txt, world_npc.txt filled
##   TTRPG.World.SceneIdea(pWorld, pPlayer)     a one-line idea for TTRPG.Scene.New
##   TTRPG.World.CharacterAsk(pWorld, pNPC)     a one-line ask for TTRPG.Character.Make
##   TTRPG.World.Save pWorld / Load(pPath) / SaveObject pWorld, pKind, pName / LoadObject @pWorld, pKind, pPath
##   TTRPG.World.ListsRoot() / TTRPG.World.SetListsRoot pFolder / TTRPG.World.List(pName)
##   World panel (23 Nov): TTRPG.World.CellData(pWorld, pLoc) / SetCellData @pWorld, pLoc, pText (plain lines,
##   the DM's edit) / MapLines(pWorld, pPlayer) (@ & n m .) / Here(pWorld, pLoc, "npc"|"monsters") /
##   Describe pWorld, pLoc, pTarget, pMsg (Verbose: the DM model words the visible tile)
##   TTRPG.World.SelfTest(pVectorsPath)         ref/world_vectors.json + a generated world
## THE RULE: hidden items, locked contents and closed boxes never reach the view or the tile.
######################################################################################

local sListsRoot, sListCache

constant kAttributes = "Strength,Constitution,Dexterity,Intelligence,Wisdom,Charisma,AC,HP"
constant kNameNoise = "the,a,an,of,old,young,elder,brother,sister,father,mother,sir,lady,lord,captain"
constant kWays = "north,south,east,west"
constant kGround = "ground"
constant kPack = "Backpack"
constant kHeld = "held"
-- per cent chances (the old code put an NPC and a monster on every cell)
constant kNPCChance = 25
constant kMonsterChance = 20
constant kOpenChance = 50
constant kLockChance = 25
constant kHiddenChance = 50

-------------------------------------------------------------------- lists (LIB_LISTS, by name)

command TTRPG.World.SetListsRoot pFolder
   put pFolder into sListsRoot
   put empty into sListCache
end TTRPG.World.SetListsRoot

function TTRPG.World.ListsRoot
   local tMyFile, tTry
   if sListsRoot is not empty then return sListsRoot
   if $LIB_LISTS is not empty and there is a folder $LIB_LISTS then
      put $LIB_LISTS into sListsRoot
      return sListsRoot
   end if
   put the effective filename of me into tMyFile
   -- livecode/lib_ttrpg_world.livecodescript (2 up), or LIB_TTRPG/TTRPG_Studio.livecode (1 up)
   repeat with tTry = 2 down to 1
      if there is a folder (wwUp(tMyFile, tTry + 1) & "/LIB_LISTS") then
         put wwUp(tMyFile, tTry + 1) & "/LIB_LISTS" into sListsRoot
         return sListsRoot
      end if
   end repeat
   return empty
end TTRPG.World.ListsRoot

private function wwUp pFolder, pLevels
   set the itemDel to "/"
   repeat pLevels times
      delete item -1 of pFolder
   end repeat
   return pFolder
end wwUp

-- the non-empty lines of LIB_LISTS/<name>.txt
function TTRPG.World.List pName
   local tText, tOut, tLine
   if sListCache[pName] is not empty then return sListCache[pName]
   if TTRPG.World.ListsRoot() is empty then return empty
   put wwRead(TTRPG.World.ListsRoot() & "/" & pName & ".txt") into tText
   replace numToChar(13) with return in tText
   repeat for each line tLine in tText
      put word 1 to -1 of tLine into tLine
      if tLine is not empty then put tLine & return after tOut
   end repeat
   delete the last char of tOut
   put tOut into sListCache[pName]
   return tOut
end TTRPG.World.List

function TTRPG.World.Roles
   local tFolder, tOut, tF
   put TTRPG.World.ListsRoot() & "/roles" into tFolder
   if there is not a folder tFolder then return empty
   repeat for each line tF in files(tFolder)
      if tF ends with ".txt" then put char 1 to -5 of tF & return after tOut
   end repeat
   delete the last char of tOut
   sort lines of tOut
   return tOut
end TTRPG.World.Roles

function TTRPG.World.RoleLore pRole
   local tL
   put TTRPG.World.List("roles/" & pRole) into tL
   replace return with space in tL
   return tL
end TTRPG.World.RoleLore

private function wwRead pPath
   if there is not a file pPath then return empty
   return textDecode(url ("binfile:" & pPath), "UTF-8")
end wwRead

private command wwWrite pPath, pText
   local tFolder
   put pPath into tFolder
   set the itemDel to "/"
   delete item -1 of tFolder
   set the itemDel to comma
   wwMakeFolder tFolder
   put textEncode(pText, "UTF-8") into url ("binfile:" & pPath)
end wwWrite

private command wwMakeFolder pFolder
   local tSoFar, tPart
   if there is a folder pFolder then exit wwMakeFolder
   set the itemDel to "/"
   repeat for each item tPart in pFolder
      put tPart after tSoFar
      if tSoFar is not empty and there is not a folder tSoFar then create folder tSoFar
      put "/" after tSoFar
   end repeat
   set the itemDel to comma
end wwMakeFolder

-------------------------------------------------------------------- small helpers (as the spec)

-- 'Old_Iron_Chest' -> 'Old Iron Chest'
function TTRPG.World.Words pName
   replace "_" with space in pName
   return word 1 to -1 of pName
end TTRPG.World.Words

private function wwUnder pName
   local tOut, tW
   repeat for each word tW in pName
      put tW & "_" after tOut
   end repeat
   delete the last char of tOut
   return tOut
end wwUnder

-- old naming: the word, spaces -> _, then _c<col>r<row>
function TTRPG.World.CellName pWord, pCol, pRow
   if pWord is empty then return "c" & pCol & "r" & pRow
   return wwUnder(pWord) & "_c" & pCol & "r" & pRow
end TTRPG.World.CellName

-- 'House_c3r12' -> "3,12", or empty (was entities.at.colrowname)
function TTRPG.World.CellOf pName
   local tC, tR
   if matchText(pName, "c([0-9]+)r([0-9]+)$", tC, tR) then return (tC + 0) & comma & (tR + 0)
   return empty
end TTRPG.World.CellOf

-- lower-case words of letters (and ' when pApos)
private function wwSaid pText, pApos
   local tOut, tCur, c
   put toLower(pText) into pText
   repeat for each char c in pText
      if (charToNum(c) >= 97 and charToNum(c) <= 122) or (pApos and c is "'") then
         put c after tCur
      else if tCur is not empty then
         put tCur & return after tOut
         put empty into tCur
      end if
   end repeat
   if tCur is not empty then put tCur & return after tOut
   delete the last char of tOut
   return tOut
end wwSaid

private function wwNameWords pName
   local tOut, tW
   repeat for each line tW in wwSaid(TTRPG.World.Words(pName), false)
      if tW is among the items of kNameNoise or the number of chars of tW <= 2 then next repeat
      put tW & return after tOut
   end repeat
   delete the last char of tOut
   if tOut is empty then return toLower(TTRPG.World.Words(pName))
   return tOut
end wwNameWords

private function wwOrdered pKeys
   sort lines of pKeys ascending text
   return pKeys
end wwOrdered

-- lines in the world's order (the panel lists with it)
function TTRPG.World.Ordered pKeys
   return wwOrdered(pKeys)
end TTRPG.World.Ordered

-- the name whose words the text says most of; ties -> first in order; none -> empty
function TTRPG.World.BestMatch pNames, pText
   local tSaid, tBest, tScore, tN, tS, tW
   put wwSaid(pText, false) into tSaid
   put 0 into tScore
   repeat for each line tN in wwOrdered(pNames)
      put 0 into tS
      repeat for each line tW in wwNameWords(tN)
         if tW is among the lines of tSaid then add 1 to tS
      end repeat
      if tS > tScore then
         put tN into tBest
         put tS into tScore
      end if
   end repeat
   return tBest
end TTRPG.World.BestMatch

-- lines -> "a, b and c"
function TTRPG.World.JoinAnd pLines
   local n, tOut, k
   put the number of lines of pLines into n
   if n is 0 then return empty
   if n is 1 then return line 1 of pLines
   repeat with k = 1 to n - 1
      put line k of pLines & ", " after tOut
   end repeat
   delete char -2 to -1 of tOut
   return tOut & " and " & line n of pLines
end TTRPG.World.JoinAnd

private function wwPick pLines
   if pLines is empty then return empty
   return line random(the number of lines of pLines) of pLines
end wwPick

private function wwChance pPct
   return random(100) <= pPct
end wwChance

-------------------------------------------------------------------- making a world (random)

-- was class.attributes.array.generator: 3 + d15 for each
function TTRPG.World.Attributes
   local tA, tName
   repeat for each item tName in kAttributes
      put 3 + random(15) into tA[tName]
   end repeat
   return tA
end TTRPG.World.Attributes

-- was generate.container.and.AdventureGear: 2-3 pieces of gear, each visible or not
private function wwContainer pName, pGear, pKind
   local tC, tItem, k
   put pName into tC["name"]
   put true into tC["open"]
   put false into tC["locked"]
   put true into tC["visible"]
   if pKind is "place" then
      put wwChance(kOpenChance) into tC["open"]
      put (not tC["open"]) and wwChance(kLockChance) into tC["locked"]
   end if
   repeat random(2) + 1 times
      if pGear is empty then exit repeat
      put wwPick(pGear) into tItem
      put tItem into tC["items"][tItem]["name"]
      put not wwChance(kHiddenChance) into tC["items"][tItem]["visible"]
   end repeat
   return tC
end wwContainer

-- was init.RandomMapGenerator + entity.type.x.y.z.world + insert.location.entities
function TTRPG.World.New pName, pCols, pRows
   local tW, tKinds, tBeasts, tMoods, tBoxes, tGear, tDescs, tPeople
   local r, c, tKind, tLoc, tBox, tRole, tN
   if pName is empty then put "Example_01_World" into pName
   if pCols is not a number then put 16 into pCols
   if pRows is not a number then put 16 into pRows
   put TTRPG.World.List("nouns/locations") into tKinds
   put TTRPG.World.List("nouns/monsters") into tBeasts
   put TTRPG.World.List("nouns/ecosystem") into tMoods
   put TTRPG.World.List("nouns/containers") into tBoxes
   put TTRPG.World.List("Lists/Equipment") into tGear
   put TTRPG.World.List("Lists/example_location_descriptions") into tDescs
   put TTRPG.World.Roles() into tPeople
   put wwUnder(pName) into tW["name"]
   put pCols into tW["cols"]
   put pRows into tW["rows"]
   repeat with r = 1 to pRows
      repeat with c = 1 to pCols
         put wwPick(tKinds) into tKind
         if tKind is empty then put "Place" into tKind
         put TTRPG.World.CellName(tKind, c, r) into tLoc
         put wwPick(tBoxes) into tBox
         if tBox is empty then put "Chest" into tBox
         put tLoc into tW["locations"][tLoc]["name"]
         put tKind into tW["locations"][tLoc]["kind"]
         put c into tW["locations"][tLoc]["col"]
         put r into tW["locations"][tLoc]["row"]
         put wwPick(tMoods) into tW["locations"][tLoc]["ecosystem"]
         put wwPick(tDescs) into tW["locations"][tLoc]["description"]
         put wwContainer(tBox, tGear, "place") into tW["locations"][tLoc]["containers"][tBox]
         if tPeople is not empty and wwChance(kNPCChance) then
            put wwPick(tPeople) into tRole
            put TTRPG.World.CellName(tRole, c, r) into tN
            put tN into tW["npc"][tN]["name"]
            put tRole into tW["npc"][tN]["role"]
            put TTRPG.World.RoleLore(tRole) into tW["npc"][tN]["lore"]
            put tLoc into tW["npc"][tN]["location"]
            put TTRPG.World.Attributes() into tW["npc"][tN]["attributes"]
            put wwContainer(kHeld, tGear, "actor") into tW["npc"][tN]["containers"][kHeld]
         end if
         if tBeasts is not empty and wwChance(kMonsterChance) then
            put wwPick(tBeasts) into tKind
            put TTRPG.World.CellName(tKind, c, r) into tN
            put tN into tW["monsters"][tN]["name"]
            put tKind into tW["monsters"][tN]["kind"]
            put tLoc into tW["monsters"][tN]["location"]
            put TTRPG.World.Attributes() into tW["monsters"][tN]["attributes"]
         end if
      end repeat
   end repeat
   return tW
end TTRPG.World.New

-- was player.random.spawn: a new PlayerN on a random cell, with a Backpack of gear
command TTRPG.World.Spawn @pWorld, pName
   local tP
   if pName is empty then put "Player" & (the number of lines of the keys of pWorld["player"] + 1) into pName
   put pName into tP["name"]
   put TTRPG.World.CellAt(pWorld, random(pWorld["cols"]), random(pWorld["rows"])) into tP["location"]
   put TTRPG.World.Attributes() into tP["attributes"]
   put wwContainer(kPack, TTRPG.World.List("Lists/Equipment"), "actor") into tP["containers"][kPack]
   put tP into pWorld["player"][pName]
   return pName
end TTRPG.World.Spawn

-------------------------------------------------------------------- reading a world

-- the location on a cell, or empty
function TTRPG.World.CellAt pWorld, pCol, pRow
   local tK, tWant
   put pCol & comma & pRow into tWant
   repeat for each line tK in wwOrdered(the keys of pWorld["locations"])
      if TTRPG.World.CellOf(tK) is tWant then return tK
   end repeat
   return empty
end TTRPG.World.CellAt

-- names of the npc / monsters standing on a location
private function wwHere pWorld, pLoc, pKind
   local tOut, tK
   repeat for each line tK in the keys of pWorld[pKind]
      if pWorld[pKind][tK]["location"] is pLoc then put tK & return after tOut
   end repeat
   delete the last char of tOut
   return wwOrdered(tOut)
end wwHere

-- was GetVisibleRoomStateForPlayer: only what can be seen. Locked shows as closed.
function TTRPG.World.Tile pWorld, pLoc
   local tL, tOut, tCN, tC, tI, tN
   put pWorld["locations"][pLoc] into tL
   put pLoc into tOut["name"]
   put tL["kind"] into tOut["kind"]
   put tL["ecosystem"] into tOut["ecosystem"]
   put tL["description"] into tOut["description"]
   repeat for each line tCN in the keys of tL["containers"]
      put tL["containers"][tCN] into tC
      if tC["visible"] is not true then next repeat
      if tCN is kGround and the keys of tC["items"] is empty then next repeat
      put tCN into tOut["containers"][tCN]["name"]
      put (tC["open"] is true) into tOut["containers"][tCN]["open"]
      if tC["open"] is true and tC["locked"] is not true then
         repeat for each line tI in the keys of tC["items"]
            if tC["items"][tI]["visible"] is true then put tI into tOut["containers"][tCN]["items"][tI]["name"]
         end repeat
      end if
   end repeat
   repeat for each line tN in wwHere(pWorld, pLoc, "npc")
      put tN into tOut["npc"][tN]["name"]
      put TTRPG.World.Words(pWorld["npc"][tN]["role"]) into tOut["npc"][tN]["role"]
   end repeat
   repeat for each line tN in wwHere(pWorld, pLoc, "monsters")
      put tN into tOut["monsters"][tN]["name"]
      put pWorld["monsters"][tN]["kind"] into tOut["monsters"][tN]["kind"]
   end repeat
   return tOut
end TTRPG.World.Tile

function TTRPG.World.Exits pWorld, pLoc
   local tCR, tOut, tWay, tTo
   put TTRPG.World.CellOf(pLoc) into tCR
   if tCR is empty then return empty
   repeat for each item tWay in kWays
      put wwStep(pWorld, tCR, tWay) into tTo
      if tTo is not empty then put tWay & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end TTRPG.World.Exits

private function wwStep pWorld, pCR, pWay
   local tC, tR
   put item 1 of pCR into tC
   put item 2 of pCR into tR
   switch pWay
      case "north"
         subtract 1 from tR
         break
      case "south"
         add 1 to tR
         break
      case "east"
         add 1 to tC
         break
      case "west"
         subtract 1 from tC
         break
   end switch
   return TTRPG.World.CellAt(pWorld, tC, tR)
end wwStep

private function wwWhoHere pTile
   local tWho, tK
   repeat for each line tK in wwOrdered(the keys of pTile["npc"])
      put TTRPG.World.Words(pTile["npc"][tK]["role"]) & return after tWho
   end repeat
   repeat for each line tK in wwOrdered(the keys of pTile["monsters"])
      put TTRPG.World.Words(pTile["monsters"][tK]["kind"]) & return after tWho
   end repeat
   delete the last char of tWho
   return tWho
end wwWhoHere

-- what the player sees, as text (was BuildPlayerTurnPrompt)
function TTRPG.World.View pWorld, pPlayer
   local tP, tLoc, tT, tCR, tOut, tKind, tWho, tL, tCN, tI, tIts, tWays
   put pWorld["player"][pPlayer] into tP
   put tP["location"] into tLoc
   put TTRPG.World.Tile(pWorld, tLoc) into tT
   put TTRPG.World.CellOf(tLoc) into tCR
   if tCR is empty then put "0,0" into tCR
   put TTRPG.World.Words(tT["kind"]) into tKind
   if tKind is empty then put TTRPG.World.Words(tLoc) into tKind
   put "You are at:" && tKind && "(column" && item 1 of tCR & ", row" && item 2 of tCR & ")" into tOut
   if tT["description"] is not empty then put return & tT["description"] after tOut
   if tT["ecosystem"] is not empty then put return & "The air carries a sense of" && tT["ecosystem"] & "." after tOut
   put wwWhoHere(tT) into tWho
   if tWho is empty then
      put return & "Nobody else is here." after tOut
   else
      put return & "Here:" && TTRPG.World.JoinAnd(tWho) & "." after tOut
   end if
   put empty into tL
   repeat for each line tCN in wwOrdered(the keys of tT["containers"])
      if tT["containers"][tCN]["open"] is true then
         put TTRPG.World.Words(tCN) && "(open)" & return after tL
      else
         put TTRPG.World.Words(tCN) && "(closed)" & return after tL
      end if
   end repeat
   delete the last char of tL
   if tL is empty then
      put return & "No containers." after tOut
   else
      put return & "Containers:" && TTRPG.World.JoinAnd(tL) & "." after tOut
   end if
   put empty into tL
   repeat for each line tCN in wwOrdered(the keys of tT["containers"])
      repeat for each line tI in wwOrdered(the keys of tT["containers"][tCN]["items"])
         put TTRPG.World.Words(tI) && "in the" && TTRPG.World.Words(tCN) & return after tL
      end repeat
   end repeat
   delete the last char of tL
   if tL is empty then
      put return & "You see nothing to take." after tOut
   else
      put return & "You can see:" && TTRPG.World.JoinAnd(tL) & "." after tOut
   end if
   put empty into tL
   repeat for each line tCN in wwOrdered(the keys of tP["containers"])
      put empty into tIts
      repeat for each line tI in wwOrdered(the keys of tP["containers"][tCN]["items"])
         put TTRPG.World.Words(tI) & return after tIts
      end repeat
      delete the last char of tIts
      if tIts is empty then put "empty" into tIts
      else put TTRPG.World.JoinAnd(tIts) into tIts
      put TTRPG.World.Words(tCN) & ":" && tIts & "; " after tL
   end repeat
   delete char -2 to -1 of tL
   if tL is empty then
      put return & "You carry nothing." after tOut
   else
      put return & "You carry:" && tL & "." after tOut
   end if
   put TTRPG.World.Exits(pWorld, tLoc) into tWays
   if tWays is empty then
      put return & "No way out." after tOut
   else
      put return & "Ways out:" && TTRPG.World.JoinAnd(tWays) & "." after tOut
   end if
   return tOut
end TTRPG.World.View

-- a one-line idea for the Studio's New Scene, from the player's cell
function TTRPG.World.SceneIdea pWorld, pPlayer
   local tT, tIdea, tWho
   put TTRPG.World.Tile(pWorld, pWorld["player"][pPlayer]["location"]) into tT
   put TTRPG.World.Words(tT["kind"]) into tIdea
   if tIdea is empty then put "a place" into tIdea
   if tT["ecosystem"] is not empty then put ", " & tT["ecosystem"] after tIdea
   if tT["description"] is not empty then put ": " & tT["description"] after tIdea
   put wwWhoHere(tT) into tWho
   if tWho is not empty then put " With" && TTRPG.World.JoinAnd(tWho) & "." after tIdea
   return tIdea
end TTRPG.World.SceneIdea

-- a one-line ask for the Studio's Add Character, from an NPC's role and lore
function TTRPG.World.CharacterAsk pWorld, pNPC
   local tAsk
   put TTRPG.World.Words(pWorld["npc"][pNPC]["role"]) into tAsk
   if tAsk is empty then put TTRPG.World.Words(pNPC) into tAsk
   if pWorld["npc"][pNPC]["lore"] is not empty then put ": " & pWorld["npc"][pNPC]["lore"] after tAsk
   return tAsk
end TTRPG.World.CharacterAsk

-- prompts/world_tile.txt (was describe_a_tile) with the VISIBLE tile only (needs TTRPG.Prompts loaded)
function TTRPG.World.TilePrompt pWorld, pLoc
   local tA
   put TTRPG.JSON.Export(TTRPG.World.Tile(pWorld, pLoc)) into tA["tile"]
   return TTRPG.Fill("world_tile", tA)
end TTRPG.World.TilePrompt

-- prompts/world_npc.txt (was ttrpg.entity.styler.prompt + nouns.npc.lore.text)
function TTRPG.World.NPCPrompt pWorld, pNPC
   local tA
   put TTRPG.World.Words(pWorld["npc"][pNPC]["role"]) into tA["role"]
   put tA["role"] into tA["name"]
   if tA["name"] is empty then put TTRPG.World.Words(pNPC) into tA["name"]
   put pWorld["npc"][pNPC]["lore"] into tA["lore"]
   return TTRPG.Fill("world_npc", tA)
end TTRPG.World.NPCPrompt

-------------------------------------------------------------------- the World panel (23 Nov): plain data + a text map
-- Owner (23 Nov): no "You are at..." prose in the panel; the cell is plain data the DM (or later a model)
-- edits; a Verbose switch has the DM model word it (from the visible tile only: TTRPG.World.Describe).
-- The DM sees everything here, hidden things marked (like DM Notes); NPCs and monsters are listed apart.

-- names of the npc / monsters on a location (pKind "npc" or "monsters"), in order
function TTRPG.World.Here pWorld, pLoc, pKind
   return wwHere(pWorld, pLoc, pKind)
end TTRPG.World.Here

-- the cell as plain lines: kind / ecosystem / description / box: Name (flags) / in Box: Item (hidden)
function TTRPG.World.CellData pWorld, pLoc
   local tL, tOut, tCN, tC, tF, tI
   put pWorld["locations"][pLoc] into tL
   if tL is not an array then return empty
   put "kind: " & tL["kind"] & return & "ecosystem: " & tL["ecosystem"] & return & "description: " & tL["description"] into tOut
   repeat for each line tCN in wwOrdered(the keys of tL["containers"])
      put tL["containers"][tCN] into tC
      if tC["open"] is true then put "open" into tF
      else put "closed" into tF
      if tC["locked"] is true then put ", locked" after tF
      if tC["visible"] is not true then put ", hidden" after tF
      put return & "box: " & tCN & " (" & tF & ")" after tOut
      repeat for each line tI in wwOrdered(the keys of tC["items"])
         put return & "in " & tCN & ": " & tI after tOut
         if tC["items"][tI]["visible"] is not true then put " (hidden)" after tOut
      end repeat
   end repeat
   return tOut
end TTRPG.World.CellData

private function wwFlags pText
   local tOut, tF
   repeat for each item tF in pText
      put toLower(word 1 to -1 of tF) into tF
      if tF is not empty then put tF & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end wwFlags

private command wwBox @pBoxes, pName
   if pBoxes[pName] is an array then exit wwBox
   put pName into pBoxes[pName]["name"]
   put true into pBoxes[pName]["open"]
   put false into pBoxes[pName]["locked"]
   put true into pBoxes[pName]["visible"]
end wwBox

-- CellData text back into the cell: its boxes become exactly those listed. The result = lines not understood.
command TTRPG.World.SetCellData @pWorld, pLoc, pText
   local tBad, tBoxes, tLine, tKey, tVal, tName, tFlags, tItem
   if pWorld["locations"][pLoc] is not an array then return "no such cell: " & pLoc
   replace numToChar(13) with empty in pText
   repeat for each line tLine in pText
      put word 1 to -1 of tLine into tLine
      if tLine is empty then next repeat
      put empty into tFlags
      if matchText(tLine, "(?i)^(kind|ecosystem|description)\s*:\s*(.*)$", tKey, tVal) then
         put word 1 to -1 of tVal into pWorld["locations"][pLoc][toLower(tKey)]
      else if matchText(tLine, "(?i)^box\s*:\s*(.+?)\s*(?:\(([^()]*)\))?$", tName, tFlags) then
         put wwFlags(tFlags) into tFlags
         wwBox tBoxes, tName
         put ("locked" is among the lines of tFlags) into tBoxes[tName]["locked"]
         put not ("closed" is among the lines of tFlags or tBoxes[tName]["locked"]) into tBoxes[tName]["open"]
         put not ("hidden" is among the lines of tFlags) into tBoxes[tName]["visible"]
      else if matchText(tLine, "(?i)^in\s+(.+?)\s*:\s*(.+?)\s*(?:\(([^()]*)\))?$", tName, tItem, tFlags) then
         wwBox tBoxes, tName
         put tItem into tBoxes[tName]["items"][tItem]["name"]
         put not ("hidden" is among the lines of wwFlags(tFlags)) into tBoxes[tName]["items"][tItem]["visible"]
      else
         put tLine & return after tBad
      end if
   end repeat
   delete the last char of tBad
   delete variable pWorld["locations"][pLoc]["containers"]
   if tBoxes is an array then put tBoxes into pWorld["locations"][pLoc]["containers"]
   return tBad
end TTRPG.World.SetCellData

-- the world as rows of marks, one a cell, a space between: @ you, & people and monsters, n people,
-- m monsters, . a place, blank = no cell
function TTRPG.World.MapLines pWorld, pPlayer
   local tCells, tWho, tK, tKind, tCR, tYou, tOut, r, c, tRow, tM
   repeat for each line tK in the keys of pWorld["locations"]
      put TTRPG.World.CellOf(tK) into tCR
      if tCR is not empty then put true into tCells[tCR]
   end repeat
   repeat for each item tKind in "npc,monsters"
      repeat for each line tK in the keys of pWorld[tKind]
         put TTRPG.World.CellOf(pWorld[tKind][tK]["location"]) into tCR
         if tCR is not empty and tKind is not among the items of tWho[tCR] then put tKind & comma after tWho[tCR]
      end repeat
   end repeat
   put TTRPG.World.CellOf(pWorld["player"][pPlayer]["location"]) into tYou
   repeat with r = 1 to pWorld["rows"]
      put empty into tRow
      repeat with c = 1 to pWorld["cols"]
         put c & comma & r into tCR
         if tCR is tYou then
            put "@" into tM
         else if tCells[tCR] is not true then
            put space into tM
         else if tWho[tCR] is "npc,monsters," or tWho[tCR] is "monsters,npc," then
            put "&" into tM
         else if tWho[tCR] is "npc," then
            put "n" into tM
         else if tWho[tCR] is "monsters," then
            put "m" into tM
         else
            put "." into tM
         end if
         put tM & space after tRow
      end repeat
      delete the last char of tRow
      put tRow & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end TTRPG.World.MapLines

-- Verbose: the DM model words the VISIBLE tile (prompts/world_tile.txt). The reply comes as
-- dispatch pMsg to pTarget with pText, pError. The result: "busy", "no model", or empty.
command TTRPG.World.Describe pWorld, pLoc, pTarget, pMsg
   local tA
   if TTRPG.LM.DM() is empty then return "no model"
   put "world" into tA["role"]
   put TTRPG.LM.DM() into tA["model"]
   put TTRPG.World.TilePrompt(pWorld, pLoc) into tA["system"]
   put "Describe the location." into tA["user"]
   put 0.8 into tA["temperature"]
   put TTRPG.Cfg.Get("max_dm") into tA["maxTokens"]
   put pTarget into tA["target"]
   put pMsg into tA["msg"]
   TTRPG.LM.Chat tA
   return the result
end TTRPG.World.Describe

-------------------------------------------------------------------- changing a world

-- was InterpregPlayerAction (never finished). The result = the reply; empty = not a world action
command TTRPG.World.Act @pWorld, pPlayer, pText
   local tLoc, tSaid, tVerb, tWay, tW, tCR, tTo, tSeen, tCN, tC, tInside, tI, tWhere, tItem, tFound
   if pWorld["player"][pPlayer] is not an array then return empty
   put pWorld["player"][pPlayer]["location"] into tLoc
   put wwSaid(pText, true) into tSaid
   if tSaid is empty then return empty
   put line 1 of tSaid into tVerb
   if tVerb is "pick" and line 2 of tSaid is "up" then put "take" into tVerb
   if tVerb is among the items of "look,l" then return TTRPG.World.View(pWorld, pPlayer)
   -- walking
   if tVerb is among the items of "go,walk,move,head" or tVerb is among the items of kWays or tVerb is among the items of "n,s,e,w" then
      put wwWay(tVerb) into tWay
      if tWay is empty then
         repeat for each line tW in line 2 to -1 of tSaid
            if wwWay(tW) is not empty then
               put wwWay(tW) into tWay
               exit repeat
            end if
         end repeat
      end if
      if tWay is empty then
         put TTRPG.World.JoinAnd(TTRPG.World.Exits(pWorld, tLoc)) into tW
         return "Which way?" && toUpper(char 1 of tW) & char 2 to -1 of tW & "."
      end if
      put TTRPG.World.CellOf(tLoc) into tCR
      if tCR is not empty then put wwStep(pWorld, tCR, tWay) into tTo
      if tTo is empty then return "You cannot go" && tWay && "from here."
      put tTo into pWorld["player"][pPlayer]["location"]
      return TTRPG.World.View(pWorld, pPlayer)
   end if
   repeat for each line tCN in the keys of pWorld["locations"][tLoc]["containers"]
      if pWorld["locations"][tLoc]["containers"][tCN]["visible"] is true then put tCN & return after tSeen
   end repeat
   delete the last char of tSeen
   -- open / close
   if tVerb is among the items of "open,close,shut,unlock" then
      put TTRPG.World.BestMatch(tSeen, pText) into tCN
      if tCN is empty then return "You see nothing like that to" && tVerb & "."
      put pWorld["locations"][tLoc]["containers"][tCN] into tC
      if tVerb is "open" then
         if tC["open"] is true then return "The" && TTRPG.World.Words(tCN) && "is already open."
         if tC["locked"] is true then return "The" && TTRPG.World.Words(tCN) && "is locked."
         put true into pWorld["locations"][tLoc]["containers"][tCN]["open"]
         repeat for each line tI in wwOrdered(the keys of tC["items"])
            if tC["items"][tI]["visible"] is true then put TTRPG.World.Words(tI) & return after tInside
         end repeat
         delete the last char of tInside
         if tInside is empty then return "You open the" && TTRPG.World.Words(tCN) & ". It looks empty."
         return "You open the" && TTRPG.World.Words(tCN) & ". Inside:" && TTRPG.World.JoinAnd(tInside) & "."
      end if
      if tVerb is "unlock" then
         if tC["locked"] is not true then return "The" && TTRPG.World.Words(tCN) && "is not locked."
         return "You have no key for the" && TTRPG.World.Words(tCN) & "."
      end if
      if tC["open"] is not true then return "The" && TTRPG.World.Words(tCN) && "is already closed."
      put false into pWorld["locations"][tLoc]["containers"][tCN]["open"]
      return "You close the" && TTRPG.World.Words(tCN) & "."
   end if
   -- take
   if tVerb is among the items of "take,grab,get,pick" then
      repeat for each line tCN in tSeen
         put pWorld["locations"][tLoc]["containers"][tCN] into tC
         if tC["open"] is not true or tC["locked"] is true then next repeat
         repeat for each line tI in the keys of tC["items"]
            if tC["items"][tI]["visible"] is true and tWhere[tI] is empty then put tCN into tWhere[tI]
         end repeat
      end repeat
      put TTRPG.World.BestMatch(the keys of tWhere, pText) into tItem
      if tItem is empty then return "You see nothing like that to take."
      put tWhere[tItem] into tCN
      put pWorld["locations"][tLoc]["containers"][tCN]["items"][tItem] into tI
      delete variable pWorld["locations"][tLoc]["containers"][tCN]["items"][tItem]
      wwPut pWorld, pPlayer, tItem, tI
      return "You take the" && TTRPG.World.Words(tItem) && "from the" && TTRPG.World.Words(tCN) & "."
   end if
   -- drop
   if tVerb is among the items of "drop,leave" then
      repeat for each line tCN in the keys of pWorld["player"][pPlayer]["containers"]
         repeat for each line tI in the keys of pWorld["player"][pPlayer]["containers"][tCN]["items"]
            if tWhere[tI] is empty then put tCN into tWhere[tI]
         end repeat
      end repeat
      put TTRPG.World.BestMatch(the keys of tWhere, pText) into tItem
      if tItem is empty then return "You carry nothing like that."
      put pWorld["player"][pPlayer]["containers"][tWhere[tItem]]["items"][tItem] into tI
      delete variable pWorld["player"][pPlayer]["containers"][tWhere[tItem]]["items"][tItem]
      if pWorld["locations"][tLoc]["containers"][kGround] is not an array then
         put kGround into pWorld["locations"][tLoc]["containers"][kGround]["name"]
         put true into pWorld["locations"][tLoc]["containers"][kGround]["open"]
         put false into pWorld["locations"][tLoc]["containers"][kGround]["locked"]
         put true into pWorld["locations"][tLoc]["containers"][kGround]["visible"]
      end if
      if tI is not an array then put tItem into tI["name"]
      put true into tI["visible"]
      put tI into pWorld["locations"][tLoc]["containers"][kGround]["items"][tItem]
      return "You drop the" && TTRPG.World.Words(tItem) & "."
   end if
   -- search: hidden things in open, unlocked containers come into view
   if tVerb is among the items of "search,examine" then
      repeat for each line tCN in wwOrdered(tSeen)
         put pWorld["locations"][tLoc]["containers"][tCN] into tC
         if tC["open"] is not true or tC["locked"] is true then next repeat
         repeat for each line tI in wwOrdered(the keys of tC["items"])
            if tC["items"][tI]["visible"] is not true then
               put true into pWorld["locations"][tLoc]["containers"][tCN]["items"][tI]["visible"]
               put TTRPG.World.Words(tI) && "in the" && TTRPG.World.Words(tCN) & return after tFound
            end if
         end repeat
      end repeat
      delete the last char of tFound
      if tFound is empty then return "You search and find nothing new."
      return "You search and find" && TTRPG.World.JoinAnd(tFound) & "."
   end if
   return empty
end TTRPG.World.Act

private function wwWay pW
   if pW is among the items of kWays then return pW
   switch pW
      case "n"
         return "north"
      case "s"
         return "south"
      case "e"
         return "east"
      case "w"
         return "west"
   end switch
   return empty
end wwWay

-- into the player's Backpack (made when missing)
private command wwPut @pWorld, pPlayer, pItem, pIt
   if pWorld["player"][pPlayer]["containers"][kPack] is not an array then
      put kPack into pWorld["player"][pPlayer]["containers"][kPack]["name"]
      put true into pWorld["player"][pPlayer]["containers"][kPack]["open"]
      put false into pWorld["player"][pPlayer]["containers"][kPack]["locked"]
      put true into pWorld["player"][pPlayer]["containers"][kPack]["visible"]
   end if
   put pItem into pIt["name"]
   put true into pIt["visible"]
   put pIt into pWorld["player"][pPlayer]["containers"][kPack]["items"][pItem]
end wwPut

-------------------------------------------------------------------- files (LIB_DATA Games/TTRPG/worlds)

command TTRPG.World.Save pWorld
   local tPath
   put TTRPG.Path("worlds", pWorld["name"] & ".json") into tPath
   wwWrite tPath, TTRPG.JSON.Export(pWorld)
   return tPath
end TTRPG.World.Save

function TTRPG.World.Load pPath
   return TTRPG.JSON.Parse(wwRead(pPath))
end TTRPG.World.Load

-- one actor / location on its own (was the two SaveWorldObjectToJSON, SaveActorToJSON, SaveLocationToJSON)
command TTRPG.World.SaveObject pWorld, pKind, pName
   local tPath
   if pWorld[pKind][pName] is not an array then return empty
   put TTRPG.Path("worlds/" & pWorld["name"] & "/" & pKind, pName & ".json") into tPath
   wwWrite tPath, TTRPG.JSON.Export(pWorld[pKind][pName])
   return tPath
end TTRPG.World.SaveObject

command TTRPG.World.LoadObject @pWorld, pKind, pPath
   local tA
   put TTRPG.World.Load(pPath) into tA
   if tA["name"] is empty then return empty
   put tA into pWorld[pKind][tA["name"]]
   return tA["name"]
end TTRPG.World.LoadObject

-------------------------------------------------------------------- self test

function TTRPG.World.SelfTest pVectorsPath
   local tV, tOut, tFails, k, tW, tWant, tGot, tReply, tName, tT, tStep
   put TTRPG.JSON.Parse(wwRead(pVectorsPath)) into tV
   if tV is not an array then return "FAIL could not read" && pVectorsPath
   repeat with k = 1 to the number of lines of the keys of tV["cell_of"]
      put tV["cell_of"][k][2][1] & comma & tV["cell_of"][k][2][2] into tWant
      if tWant is comma then put empty into tWant
      wwCheck tOut, tFails, "cell_of" && tV["cell_of"][k][1], TTRPG.World.CellOf(tV["cell_of"][k][1]), tWant
   end repeat
   repeat with k = 1 to the number of lines of the keys of tV["best_match"]
      put empty into tName
      repeat with tT = 1 to the number of lines of the keys of tV["best_match"][k][1]
         put tV["best_match"][k][1][tT] & return after tName
      end repeat
      delete the last char of tName
      wwCheck tOut, tFails, "best_match" && tV["best_match"][k][2], TTRPG.World.BestMatch(tName, tV["best_match"][k][2]), tV["best_match"][k][3]
   end repeat
   repeat with k = 1 to the number of lines of the keys of tV["join_and"]
      put empty into tName
      repeat with tT = 1 to the number of lines of the keys of tV["join_and"][k][1]
         put tV["join_and"][k][1][tT] & return after tName
      end repeat
      delete the last char of tName
      wwCheck tOut, tFails, "join_and" && k, TTRPG.World.JoinAnd(tName), tV["join_and"][k][2]
   end repeat
   put tV["start"] into tW
   repeat with k = 1 to the number of lines of the keys of tV["steps"]
      put tV["steps"][k] into tStep
      TTRPG.World.Act tW, "Player1", tStep["action"]
      put the result into tReply
      wwCheck tOut, tFails, "act" && k && tStep["action"], tReply, tStep["reply"]
      wwCheck tOut, tFails, "world after" && k && tStep["action"], wwFlat(tW, empty), wwFlat(tStep["world"], empty)
   end repeat
   wwCheck tOut, tFails, "scene_idea", TTRPG.World.SceneIdea(tV["start"], "Player1"), tV["scene_idea"]
   wwCheck tOut, tFails, "character_ask", TTRPG.World.CharacterAsk(tV["start"], "Old_Miller_c1r1"), tV["character_ask"]
   wwCheck tOut, tFails, "tile", wwFlat(TTRPG.World.Tile(tV["start"], "Old_Mill_c1r1"), empty), wwFlat(tV["tile"], empty)
   wwCheck tOut, tFails, "cell_data", TTRPG.World.CellData(tV["start"], "Old_Mill_c1r1"), tV["cell_data"]
   put tV["start"] into tW
   TTRPG.World.SetCellData tW, "Old_Mill_c1r1", tV["edit"]["text"]
   put the result into tReply
   put empty into tName
   repeat with tT = 1 to the number of lines of the keys of tV["edit"]["bad"]
      put tV["edit"]["bad"][tT] & return after tName
   end repeat
   delete the last char of tName
   wwCheck tOut, tFails, "set_cell_data: lines not understood", tReply, tName
   wwCheck tOut, tFails, "set_cell_data: the cell", wwFlat(tW["locations"]["Old_Mill_c1r1"], empty), wwFlat(tV["edit"]["cell"], empty)
   TTRPG.World.SetCellData tW, "Old_Mill_c1r1", TTRPG.World.CellData(tW, "Old_Mill_c1r1")
   put the result into tReply
   wwCheck tOut, tFails, "cell_data -> set_cell_data round trip", tReply & wwFlat(tW["locations"]["Old_Mill_c1r1"], empty), wwFlat(tV["edit"]["cell"], empty)
   put tV["start"] into tW
   put 3 into tW["cols"]
   put 2 into tW["rows"]
   put empty into tName
   repeat with tT = 1 to the number of lines of the keys of tV["map"]
      put tV["map"][tT] & return after tName
   end repeat
   delete the last char of tName
   wwCheck tOut, tFails, "map_lines", TTRPG.World.MapLines(tW, "Player1"), tName
   -- a generated world (words from LIB_LISTS; counted, never printed)
   if TTRPG.World.ListsRoot() is empty then
      put "FAIL LIB_LISTS not found" & return after tOut
      add 1 to tFails
   else
      put TTRPG.World.New("Test_World", 16, 16) into tW
      TTRPG.World.Spawn tW
      put the result into tName
      wwCheck tOut, tFails, "generated: 256 locations", the number of lines of the keys of tW["locations"], 256
      put 0 into tGot
      repeat for each line tT in the keys of tW["locations"]
         if TTRPG.World.CellOf(tT) is not (tW["locations"][tT]["col"] & comma & tW["locations"][tT]["row"]) then add 1 to tGot
         if the number of lines of the keys of tW["locations"][tT]["containers"] is not 1 then add 1 to tGot
      end repeat
      repeat for each item tStep in "npc,monsters,player"
         repeat for each line tT in the keys of tW[tStep]
            if tW["locations"][tW[tStep][tT]["location"]] is not an array then add 1 to tGot
         end repeat
      end repeat
      wwCheck tOut, tFails, "generated: names, containers, everyone stands somewhere", tGot, 0
      wwCheck tOut, tFails, "spawned Player1", tName, "Player1"
      wwCheck tOut, tFails, "view has 'You are at'", word 1 to 3 of TTRPG.World.View(tW, tName), "You are at:"
      put "generated:" && the number of lines of the keys of tW["npc"] && "npc," && the number of lines of the keys of tW["monsters"] && "monsters" & return after tOut
   end if
   if tFails is empty then put 0 into tFails
   return tOut & "world self test:" && tFails && "fails"
end TTRPG.World.SelfTest

private command wwCheck @pOut, @pFails, pName, pGot, pWant
   if pGot is pWant then
      put "ok  " & pName & return after pOut
   else
      put "FAIL " & pName & return & "   got:  " & line 1 to 3 of pGot & return & "   want: " & line 1 to 3 of pWant & return after pOut
      add 1 to pFails
   end if
end wwCheck

-- an array as sorted "path=value" lines; empty values left out (as the spec's norm)
private function wwFlat pA, pPath
   local tOut, tK
   if pA is not an array then
      if pA is empty then return empty
      return pPath & "=" & pA
   end if
   repeat for each line tK in the keys of pA
      put wwFlat(pA[tK], pPath & "/" & tK) & return after tOut
   end repeat
   filter lines of tOut without empty
   sort lines of tOut
   return tOut
end wwFlat
