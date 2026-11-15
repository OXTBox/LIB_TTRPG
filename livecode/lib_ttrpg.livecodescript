script "lib_ttrpg"
######################################################################################
## lib_ttrpg (LIB_TTRPG, iteration 1, 15 Nov 2026): the TTRPG Studio engine. No UI, no field
## names. A port of the Studio class and the text helpers of ref/ttrpg_ref.py (the spec: change
## behaviour there first, then here). Needs lib_ttrpg_lm (calls, JSON) and LIB_DATA (files).
##
## THE RULE: the code holds the secrets; the models only word things. Unrevealed clues, the
## truth and other characters' secrets never go into a narrator prompt.
##
##   TTRPG.Init pUI, pDataDir     pUI = long id that hears the messages below; pDataDir empty =
##                                LIB_DATA (Games/TTRPG, logs in Logs/TTRPG), else a test folder
##   TTRPG.Prompts.Load pFolder / TTRPG.Prompts.Use pArray
##   TTRPG.Scene.New pIdea        -> TTRPG.SceneReady
##   TTRPG.Turn.Begin pAction     -> TTRPG.Shown pLines, then TTRPG.Done
##   TTRPG.Turn.Redo              same ruling (roll, clue), new words only
##   TTRPG.Character.Make pAsk    -> TTRPG.CharacterMade pName (empty = the model gave none)
##   TTRPG.Scene.End              scene characters with keep = true become constant
##   TTRPG.Cancel, TTRPG.Busy(), TTRPG.Scene(), TTRPG.Chars(), TTRPG.Player(), TTRPG.Notes()
##   TTRPG.SelfTest(pVectors)     the text helpers against ref/vectors.json
##   TTRPG.OwnerTest()            the owner's test (needs a loaded model), PASS / FAIL lines
## pLines of TTRPG.Shown: one line each, speaker <tab> text; speaker "roll" / "clue" / "secret" are
## the die line, a found clue and a pressed-out secret ("Name: secret"), word for word, "DM" the narrator, else a character's name.
## A turn in async form: Begin -> referee form -> ttOnReferee (the ruling, pure code) ->
## narrator or voice -> ttOnWords (append, save, TTRPG.Shown) -> fold when due -> TTRPG.Done.
######################################################################################

local sUI, sDataDir, sPrompts, sCfg
local sScene, sBusy, sT, sLastShown, sOpenTries

constant kSkills = "Perception,Investigation,Arcana,History,Insight,Athletics,Stealth,Persuasion"
constant kTalkSkills = "Insight,Persuasion"
constant kNameNoise = "the,a,an,of,old,young,elder,brother,sister,father,mother,sir,lady,lord,captain"
constant kPressing = "(?i)persua|convinc|plead|press|insist|trust|lying|lie\b|truth|hiding|secret|insight|read (him|her|them)"
constant kRisky = "(?i)\b(try|attempt|climb|jump|force|break|sneak|swim|lift|push|pull|pick|dodge|run|grab|throw|attack|hit|kick)"
constant kAsking = "(?i)(what (do|will|would) you do|what now|what is your next|how do you (proceed|respond)|do you (want|wish|dare)|will you\b|you (can|could|may|might) (choose|either|try)|your options)"

-------------------------------------------------------------------- setup

command TTRPG.Init pUI, pDataDir
   put pUI into sUI
   put pDataDir into sDataDir
   put false into sBusy
   TTRPG.Cfg.Defaults
   TTRPG.LM.Init
   TTRPG.LM.SetLog TTRPG.Path("logs", ttStamp() & "_session.jsonl")
end TTRPG.Init

command TTRPG.Cfg.Defaults
   if sCfg["max_dm"] is empty then put 200 into sCfg["max_dm"]
   if sCfg["max_voice"] is empty then put 120 into sCfg["max_voice"]
   if sCfg["max_referee"] is empty then put 60 into sCfg["max_referee"]
   if sCfg["max_make"] is empty then put 500 into sCfg["max_make"]
   if sCfg["max_summary"] is empty then put 120 into sCfg["max_summary"]
   if sCfg["temp_dm"] is empty then put 0.8 into sCfg["temp_dm"]
   if sCfg["temp_voice"] is empty then put 0.9 into sCfg["temp_voice"]
   if sCfg["keep_turns"] is empty then put 3 into sCfg["keep_turns"]          -- exchanges shown word for word
   if sCfg["summary_every"] is empty then put 4 into sCfg["summary_every"]    -- fold this often
end TTRPG.Cfg.Defaults

command TTRPG.Cfg.Set pName, pValue
   TTRPG.Cfg.Defaults
   if pValue is a number then put pValue into sCfg[pName]
end TTRPG.Cfg.Set

function TTRPG.Cfg.Get pName
   TTRPG.Cfg.Defaults
   if pName is empty then return sCfg
   return sCfg[pName]
end TTRPG.Cfg.Get

-- where files go: LIB_DATA, or the test folder given to TTRPG.Init
function TTRPG.Path pSub, pName
   local tFolder
   if sDataDir is not empty then
      put sDataDir & "/" & pSub into tFolder
      ttMakeFolder tFolder
      return tFolder & "/" & pName
   end if
   if pSub is "logs" then return Data.Path("Logs", "TTRPG/" & pName)
   return Data.Path("Games", "TTRPG/" & pSub & "/" & pName)
end TTRPG.Path

private command ttMakeFolder pFolder
   local tSoFar, tPart
   if there is a folder pFolder then exit ttMakeFolder
   set the itemDel to "/"
   repeat for each item tPart in pFolder
      put tPart after tSoFar
      if tSoFar is not empty and there is not a folder tSoFar then create folder tSoFar
      put "/" after tSoFar
   end repeat
   set the itemDel to comma
end ttMakeFolder

-- "2026-11-15_143005"
private function ttStamp
   local tD
   put the seconds into tD
   convert tD to dateItems
   return item 1 of tD & "-" & format("%02d", item 2 of tD) & "-" & format("%02d", item 3 of tD) & "_" & \
         format("%02d%02d%02d", item 4 of tD, item 5 of tD, item 6 of tD)
end ttStamp

function TTRPG.Busy
   return sBusy is true
end TTRPG.Busy

-- Escape: drop the call in flight and whatever turn it belonged to
command TTRPG.Cancel
   TTRPG.LM.Cancel
   if sT["redo"] is true and sT["turn"] is an array then
      -- a cancelled regenerate puts the old turn back
      ttListAppend sScene["turns"], sT["turn"]
   end if
   put empty into sT
   put false into sBusy
end TTRPG.Cancel

private command ttTell pMsg, pParam
   if sUI is not empty and exists(sUI) then dispatch pMsg to sUI with pParam
end ttTell

private command ttDone
   put false into sBusy
   ttTell "TTRPG.Done"
end ttDone

-------------------------------------------------------------------- prompts

command TTRPG.Prompts.Load pFolder
   local tFiles, tF, tOld
   put the defaultFolder into tOld
   set the defaultFolder to pFolder
   put the files into tFiles
   set the defaultFolder to tOld
   repeat for each line tF in tFiles
      if tF ends with ".txt" then
         put word 1 to -1 of textDecode(URL ("binfile:" & pFolder & "/" & tF), "UTF-8") into sPrompts[char 1 to -5 of tF]
         replace numToChar(13) & numToChar(10) with numToChar(10) in sPrompts[char 1 to -5 of tF]
      end if
   end repeat
end TTRPG.Prompts.Load

command TTRPG.Prompts.Use pA
   put pA into sPrompts
end TTRPG.Prompts.Use

function TTRPG.Prompts
   return sPrompts
end TTRPG.Prompts

-- a prompt with its {blanks} filled
function TTRPG.Fill pName, pA
   local tText, k
   put sPrompts[pName] into tText
   if pA is an array then
      repeat for each key k in pA
         replace "{" & k & "}" with pA[k] in tText
      end repeat
   end if
   return tText
end TTRPG.Fill

-------------------------------------------------------------------- characters

function TTRPG.DefaultPlayer
   local tA, tSkill, tBonus
   put "player" into tA["id"]
   put "Wren" into tA["name"]
   put "constant" into tA["kind"]
   put "true" into tA["player"]
   put "a wiry traveller in a patched grey cloak" into tA["look"]
   put "dry and curious" into tA["voice"]
   put "to know what happened here" into tA["wants"]
   put empty into tA["secret"]
   put "2,3,3,1,1,0,2,1" into tBonus
   repeat with tSkill = 1 to 8
      put item tSkill of tBonus into tA["skills"][item tSkill of kSkills]
   end repeat
   return tA
end TTRPG.DefaultPlayer

-- the constant characters (player included), sorted by file name, as a list 1..n
function TTRPG.Constants
   local tFolder, tOld, tFiles, tF, tA, n, tOut
   put TTRPG.Path("characters", "x.json") into tFolder
   set the itemDel to "/"
   put item 1 to -2 of tFolder into tFolder
   set the itemDel to comma
   put the defaultFolder into tOld
   set the defaultFolder to tFolder
   put the files into tFiles
   set the defaultFolder to tOld
   sort lines of tFiles
   put 0 into n
   repeat for each line tF in tFiles
      if not (tF ends with ".json") then next repeat
      put TTRPG.JSON.Parse(textDecode(URL ("binfile:" & tFolder & "/" & tF), "UTF-8")) into tA
      if tA is an array then
         add 1 to n
         put tA into tOut[n]
      end if
   end repeat
   return tOut
end TTRPG.Constants

command TTRPG.Character.Save pA
   put "constant" into pA["kind"]
   if pA["id"] is empty then put TTRPG.Slug(pA["name"]) into pA["id"]
   delete variable pA["keep"]
   put textEncode(TTRPG.JSON.Export(pA), "UTF-8") into URL ("binfile:" & TTRPG.Path("characters", pA["id"] & ".json"))
end TTRPG.Character.Save

function TTRPG.Player
   local tAll, i
   put TTRPG.Constants() into tAll
   repeat with i = 1 to the number of elements of tAll
      if tAll[i]["player"] is "true" then return tAll[i]
   end repeat
   TTRPG.Character.Save TTRPG.DefaultPlayer()
   return TTRPG.DefaultPlayer()
end TTRPG.Player

-- the characters the window lists: the scene's, or (no scene yet) the constant ones but the player
function TTRPG.Chars
   local tAll, tOut, i, n
   if sScene["title"] is not empty then return sScene["characters"]
   put TTRPG.Constants() into tAll
   put 0 into n
   repeat with i = 1 to the number of elements of tAll
      if tAll[i]["player"] is not "true" then
         add 1 to n
         put tAll[i] into tOut[n]
      end if
   end repeat
   return tOut
end TTRPG.Chars

-- the window's character editor saved character pIdx of TTRPG.Chars()
command TTRPG.Char.Update pIdx, pA
   local tOld
   put TTRPG.Chars() into tOld
   put tOld[pIdx] into tOld
   if tOld is not an array then exit TTRPG.Char.Update
   if pA["name"] is not empty and pA["name"] is not tOld["name"] and tOld["kind"] is "scene" then put TTRPG.Slug(pA["name"]) into pA["id"]
   union pA with tOld
   if sScene["title"] is not empty then
      put pA into sScene["characters"][pIdx]
      ttSaveScene
   end if
   if pA["kind"] is "constant" then TTRPG.Character.Save pA
end TTRPG.Char.Update

-- a blank one, by hand; -> its index
function TTRPG.Char.New
   local tA
   put "New character" into tA["name"]
   put "new_character_" & the seconds into tA["id"]
   put "scene" into tA["kind"]
   repeat for each item k in "look,voice,wants,secret"
      put empty into tA[k]
   end repeat
   if sScene["title"] is empty then
      put "constant" into tA["kind"]
      TTRPG.Character.Save tA
      return the number of elements of TTRPG.Chars()
   end if
   ttListAppend sScene["characters"], tA
   ttSaveScene
   return the number of elements of sScene["characters"]
end TTRPG.Char.New

-- out of the scene; a constant one also loses its file
command TTRPG.Char.Delete pIdx
   local tA, tPath
   put TTRPG.Chars() into tA
   put tA[pIdx] into tA
   if tA is not an array or tA["player"] is "true" then exit TTRPG.Char.Delete
   if sScene["title"] is not empty then
      ttListDelete sScene["characters"], pIdx
      ttSaveScene
   end if
   if tA["kind"] is "constant" then
      put TTRPG.Path("characters", tA["id"] & ".json") into tPath
      if there is a file tPath then delete file tPath
   end if
end TTRPG.Char.Delete

command TTRPG.Character.Make pAsk
   local tA, tV
   if sBusy then return "busy"
   put true into sBusy
   put sScene["place"] into tV["place"]
   if tV["place"] is empty then put "somewhere in the world" into tV["place"]
   put pAsk into tV["ask"]
   put "make" into tA["role"]
   put TTRPG.LM.DM() into tA["model"]
   put TTRPG.Fill("character_make", tV) into tA["system"]
   put "Fill in the form." into tA["user"]
   put ttCharacterSchema() into tA["schema"]
   put 0.9 into tA["temperature"]
   put sCfg["max_make"] into tA["maxTokens"]
   put the long id of me into tA["target"]
   put "TTRPG.OnCharacter" into tA["msg"]
   TTRPG.LM.Form tA
   return empty
end TTRPG.Character.Make

on TTRPG.OnCharacter pA, pErr
   local tName
   if pA is an array and pA["name"] is not empty then
      put TTRPG.Slug(pA["name"]) into pA["id"]
      put "scene" into pA["kind"]
      if sScene["title"] is not empty then
         ttListAppend sScene["characters"], pA
         ttSaveScene
      else
         put "constant" into pA["kind"]
         TTRPG.Character.Save pA
      end if
      put pA["name"] into tName
   end if
   if pErr is not empty then ttTell "TTRPG.Status", "model error: " & pErr
   put false into sBusy
   ttTell "TTRPG.CharacterMade", tName
   ttTell "TTRPG.Done"
end TTRPG.OnCharacter

-------------------------------------------------------------------- a scene

function TTRPG.Scene
   return sScene
end TTRPG.Scene

-- for tests and a reopened scene
command TTRPG.Scene.Use pA
   put pA into sScene
end TTRPG.Scene.Use

command TTRPG.Scene.New pIdea
   local tA, tV
   if sBusy then return "busy"
   put true into sBusy
   put empty into sScene
   put pIdea into tV["idea"]
   put 4 into tV["nclues"]
   put "make" into tA["role"]
   put TTRPG.LM.DM() into tA["model"]
   put TTRPG.Fill("scene_make", tV) into tA["system"]
   put "Fill in the form." into tA["user"]
   put ttSceneSchema() into tA["schema"]
   put 0.9 into tA["temperature"]
   put sCfg["max_make"] into tA["maxTokens"]
   put the long id of me into tA["target"]
   put "TTRPG.OnSceneMade" into tA["msg"]
   put pIdea into sT["idea"]
   TTRPG.LM.Form tA
   return empty
end TTRPG.Scene.New

on TTRPG.OnSceneMade pD, pErr
   local tS, tAll, i, n, tC, tNpc
   if pErr is not empty then ttTell "TTRPG.Status", "model error: " & pErr
   if pD is not an array or pD["title"] is empty or pD["clues"] is not an array then
      -- the model gave no form: a plain scene, so play can start anyway
      put empty into pD
      put char 1 to 40 of sT["idea"] into pD["title"]
      put "Someone was here moments ago and left in a hurry." into pD["truth"]
      put "You stand in " & sT["idea"] & "." into pD["place"]
      put "It is quiet, too quiet." into pD["happening"]
      put "Something here has been disturbed." into pD["wrong"]
      put "the floor" into pD["clues"][1]["where"]
      put "Perception" into pD["clues"][1]["skill"]
      put "Fresh wet footprints lead away." into pD["clues"][1]["fact"]
      put "the walls" into pD["clues"][2]["where"]
      put "Investigation" into pD["clues"][2]["skill"]
      put "A mark was scratched here in haste." into pD["clues"][2]["fact"]
   end if
   repeat for each item i in "title,truth,place,happening,wrong"
      put pD[i] into tS[i]
   end repeat
   put sT["idea"] into tS["idea"]
   put empty into tS["summary"]
   put empty into tS["turns"]
   put 0 into tS["folded"]
   put empty into tS["clues"]
   put empty into tS["characters"]
   put 0 into n
   put TTRPG.Constants() into tAll
   repeat with i = 1 to the number of elements of tAll
      if tAll[i]["player"] is not "true" then
         add 1 to n
         put tAll[i] into tS["characters"][n]
      end if
   end repeat
   put ttStamp() & "_" & TTRPG.Slug(tS["title"]) & ".json" into tS["file"]
   repeat with i = 1 to the number of elements of pD["clues"]
      put pD["clues"][i] into tC
      put i into tS["clues"][i]["id"]
      put tC["where"] into tS["clues"][i]["where"]
      put tC["skill"] into tS["clues"][i]["skill"]
      put tC["fact"] into tS["clues"][i]["fact"]
      put "false" into tS["clues"][i]["found"]
      put 0 into tS["clues"][i]["tries"]
   end repeat
   put pD["npc"] into tNpc
   if tNpc is an array and tNpc["name"] is not empty then
      put "scene" into tNpc["kind"]
      put TTRPG.Slug(tNpc["name"]) into tNpc["id"]
      ttListAppend tS["characters"], tNpc
   end if
   put tS into sScene
   put 0 into sOpenTries
   ttOpenAsk
end TTRPG.OnSceneMade

private command ttOpenAsk
   local tA, tV
   put sScene["place"] into tV["place"]
   put sScene["happening"] into tV["happening"]
   put TTRPG.WhoLine(sScene) into tV["who"]
   put sScene["wrong"] into tV["wrong"]
   put TTRPG.Player() into tV["player"]
   put tV["player"]["look"] into tV["player"]
   put "dm" into tA["role"]
   put TTRPG.LM.DM() into tA["model"]
   put TTRPG.Fill("dm_open") into tA["system"]
   put TTRPG.Fill("dm_open_user", tV) into tA["user"]
   put 0.7 into tA["temperature"]
   put sCfg["max_dm"] into tA["maxTokens"]
   put the long id of me into tA["target"]
   put "TTRPG.OnOpening" into tA["msg"]
   TTRPG.LM.Chat tA
end ttOpenAsk

on TTRPG.OnOpening pText, pErr
   local tText
   add 1 to sOpenTries
   put TTRPG.CleanNarration(pText, 5) into tText
   if the number of lines of TTRPG.Sentences(tText) < 3 then
      if sOpenTries < 3 and sBusy then
         ttOpenAsk
         exit TTRPG.OnOpening
      end if
      -- the model would not: say the facts plainly
      put sScene["place"] && sScene["happening"] && sScene["wrong"] into tText
   end if
   if pErr is not empty then ttTell "TTRPG.Status", "model error: " & pErr
   put tText into sScene["opening"]
   ttSaveScene
   put empty into sT
   put false into sBusy
   ttTell "TTRPG.SceneReady"
   ttTell "TTRPG.Done"
end TTRPG.OnOpening

private command ttSaveScene
   if sScene["file"] is empty then exit ttSaveScene
   put textEncode(TTRPG.JSON.Export(sScene), "UTF-8") into URL ("binfile:" & TTRPG.Path("scenes", sScene["file"]))
end ttSaveScene

function TTRPG.ScenePath
   if sScene["file"] is empty then return empty
   return TTRPG.Path("scenes", sScene["file"])
end TTRPG.ScenePath

-- scene characters with keep = true (or named in pKeep, one a line) become constant
command TTRPG.Scene.End pKeep
   local i, tC
   if sScene["title"] is empty then exit TTRPG.Scene.End
   repeat with i = 1 to the number of elements of sScene["characters"]
      put sScene["characters"][i] into tC
      if tC["kind"] is "scene" and (tC["keep"] is "true" or tC["name"] is among the lines of pKeep) then
         TTRPG.Character.Save tC
         put "constant" into sScene["characters"][i]["kind"]
      end if
   end repeat
   put "true" into sScene["ended"]
   ttSaveScene
end TTRPG.Scene.End

-- the /notes view: it is the owner's game, he may peek
function TTRPG.Notes
   local tOut, i, tC, tMark
   if sScene["title"] is empty then return "No scene yet."
   put "TRUTH: " & sScene["truth"] & return & return & "CLUES" & return into tOut
   repeat with i = 1 to the number of elements of sScene["clues"]
      put sScene["clues"][i] into tC
      if tC["found"] is "true" then
         put "[x]" into tMark
      else
         put "[ ]" into tMark
      end if
      put tMark && tC["id"] & ". " & tC["where"] && "(" & tC["skill"] & ", tries " & tC["tries"] & "): " & tC["fact"] & return after tOut
   end repeat
   put return & "CHARACTERS" & return after tOut
   repeat with i = 1 to the number of elements of sScene["characters"]
      put sScene["characters"][i] into tC
      put tC["name"] && "(" & tC["kind"] & ") wants " & tC["wants"] & "; hides " & tC["secret"] after tOut
      if tC["revealed"] is "true" then put " (revealed)" after tOut
      put return after tOut
   end repeat
   put return & "SUMMARY (" & sScene["folded"] & " turns folded): " & sScene["summary"] after tOut
   return tOut
end TTRPG.Notes

-------------------------------------------------------------------- one turn

command TTRPG.Turn.Begin pAction
   local tA, tV, tNames, tSpots, tSchema, i, tC
   if sBusy then return "busy"
   if sScene["title"] is empty or sScene["ended"] is "true" then return "no scene"
   put word 1 to -1 of pAction into pAction
   if pAction is empty then return "empty"
   put true into sBusy
   put empty into sT
   put pAction into sT["action"]
   put TTRPG.Player() into sT["player"]
   -- the referee sees names and SPOT NAMES only, never the clues
   repeat with i = 1 to the number of elements of sScene["characters"]
      put sScene["characters"][i]["name"] & return after tNames
   end repeat
   repeat with i = 1 to the number of elements of sScene["clues"]
      put sScene["clues"][i] into tC
      if tC["found"] is not "true" then put tC["id"] & ": " & tC["where"] & return after tSpots
   end repeat
   delete the last char of tNames
   delete the last char of tSpots
   put "{" & quote & "type" & quote & ":" & quote & "object" & quote & "," & quote & "properties" & quote & ":{" & \
         quote & "kind" & quote & ":" & ttEnum("talk" & return & "look" & return & "do") & "," & \
         quote & "who" & quote & ":" & ttEnum(ttJoin(tNames, return, "nobody")) & "," & \
         quote & "spot" & quote & ":" & ttEnum(ttJoin(ttSpotIds(), return, "none")) & "," & \
         quote & "skill" & quote & ":" & ttEnum(ttLinesOf(kSkills)) & "}," & \
         quote & "required" & quote & ":[" & quote & "kind" & quote & "," & quote & "who" & quote & "," & \
         quote & "spot" & quote & "," & quote & "skill" & quote & "]}" into tSchema
   put tNames into tV["names"]
   replace return with ", " in tV["names"]
   if tV["names"] is empty then put "(nobody)" into tV["names"]
   put tSpots into tV["spots"]
   if tV["spots"] is empty then put "(none)" into tV["spots"]
   put pAction into tV["action"]
   put "referee" into tA["role"]
   put TTRPG.LM.DM() into tA["model"]
   put TTRPG.Fill("referee") into tA["system"]
   put TTRPG.Fill("referee_user", tV) into tA["user"]
   put tSchema into tA["schema"]
   put 0 into tA["temperature"]
   put sCfg["max_referee"] into tA["maxTokens"]
   put the long id of me into tA["target"]
   put "TTRPG.OnReferee" into tA["msg"]
   TTRPG.LM.Form tA
   return empty
end TTRPG.Turn.Begin

-- Regenerate: the same ruling (same roll, same clue), only new words; a failure cannot be re-rolled
command TTRPG.Turn.Redo
   local n
   if sBusy then return "busy"
   put the number of elements of sScene["turns"] into n
   if n is 0 or sScene["ended"] is "true" then return "nothing to redo"
   put true into sBusy
   put empty into sT
   put sScene["turns"][n] into sT["turn"]
   put true into sT["redo"]
   put sT["turn"]["action"] into sT["action"]
   put sT["turn"]["ruling"] into sT["ruling"]
   put TTRPG.Player() into sT["player"]
   ttListDelete sScene["turns"], n
   ttWords
   return empty
end TTRPG.Turn.Redo

private function ttSpotIds
   local i, tOut
   repeat with i = 1 to the number of elements of sScene["clues"]
      if sScene["clues"][i]["found"] is not "true" then put sScene["clues"][i]["id"] & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end ttSpotIds

on TTRPG.OnReferee pR, pErr
   if not sBusy then exit TTRPG.OnReferee           -- cancelled
   if pR is not an array then
      put "do" into pR["kind"]
      put "nobody" into pR["who"]
      put "none" into pR["spot"]
      put "Perception" into pR["skill"]
   end if
   if pErr is not empty then ttTell "TTRPG.Status", "referee error: " & pErr
   put TTRPG.Rule(pR, sT["action"], sT["player"]) into sT["ruling"]
   ttWords
end TTRPG.OnReferee

-- What happens: the referee's form + code. The narrator only words it. Changes sScene's clues.
function TTRPG.Rule pR, pAction, pPlayer
   local tKind, tSkill, tWho, tNamed, i, tC, tRuling, tBonus, tOpen, tIdx, tMatched, tDC, tOk
   put pR["kind"] into tKind
   if tKind is not among the items of "talk,look,do" then put "do" into tKind
   put pR["skill"] into tSkill
   if tSkill is not among the items of kSkills then put "Perception" into tSkill
   put 0 into tWho
   put 0 into tNamed
   repeat with i = 1 to the number of elements of sScene["characters"]
      put sScene["characters"][i] into tC
      if tNamed is 0 and TTRPG.IsNamed(tC["name"], pAction) then put i into tNamed
      if tWho is 0 and tC["name"] is pR["who"] then put i into tWho
   end repeat
   if tKind is "talk" and tWho is 0 then
      if tNamed > 0 then
         put tNamed into tWho
      else if the number of elements of sScene["characters"] is 1 then
         put 1 into tWho
      end if
   end if
   if tKind is not "talk" and tNamed > 0 and (pAction contains quote or pAction contains "?") then
      -- the referee missed plain speech to a named character
      put "talk" into tKind
      put tNamed into tWho
   end if
   if tKind is "talk" and tWho is 0 then put "do" into tKind
   put pPlayer["skills"][tSkill] into tBonus
   if tBonus is not a number then put 0 into tBonus
   put tKind into tRuling["kind"]
   put tSkill into tRuling["skill"]
   put 0 into tOpen
   repeat with i = 1 to the number of elements of sScene["clues"]
      if sScene["clues"][i]["found"] is not "true" then
         if tOpen is 0 then put i into tOpen          -- the next open clue
         if sScene["clues"][i]["id"] is pR["spot"] then put i into tIdx
      end if
   end repeat
   switch
      case tKind is "talk"
         put sScene["characters"][tWho]["id"] into tRuling["who"]
         if tSkill is among the items of kTalkSkills and sScene["characters"][tWho]["secret"] is not empty \
               and matchText(pAction, kPressing) then
            get ttRoll(tRuling, tSkill, tBonus, 13)
         end if
         put empty into tRuling["result"]
         break
      case tKind is "look" and tOpen > 0
         put (tIdx is not empty) into tMatched
         if not tMatched then put tOpen into tIdx      -- Lazy DM: the next clue turns up where the player looks
         put sScene["clues"][tIdx] into tC
         if tMatched then
            put 8 into tDC
         else
            put 11 into tDC
         end if
         put max(5, tDC - 3 * tC["tries"]) into tDC
         if ttRoll(tRuling, tSkill, tBonus, tDC) then
            put "true" into sScene["clues"][tIdx]["found"]
            put tC["id"] into tRuling["clue"]
            put "The player discovers exactly this, and nothing more: " & tC["fact"] into tRuling["result"]
            if not tMatched then
               put " (Place this discovery where the player is looking.)" after tRuling["result"]
            end if
         else
            put tC["tries"] + 1 into sScene["clues"][tIdx]["tries"]
            put "The player finds nothing new this time. Say what they see instead; hint that a closer or different look might help." into tRuling["result"]
         end if
         break
      case tKind is "look"
         put "There is nothing more hidden here. The player sees only what is already known." into tRuling["result"]
         break
      default
         put true into tOk
         if matchText(pAction, kRisky) then put ttRoll(tRuling, tSkill, tBonus, 10) into tOk
         if tOk then
            put "The action works; describe its plain, immediate effect." into tRuling["result"]
         else
            put "The action fails; describe the small setback. Nobody is badly hurt." into tRuling["result"]
         end if
   end switch
   return tRuling
end TTRPG.Rule

-- d20 + bonus against pDC; writes success and the roll line into pRuling
private function ttRoll @pRuling, pSkill, pBonus, pDC
   local d, tOk, tSign, tWord
   put random(20) into d
   put (d + pBonus >= pDC) into tOk
   if pBonus >= 0 then
      put "+" into tSign
   else
      put "-" into tSign
   end if
   if tOk then
      put "success" into tWord
   else
      put "failure" into tWord
   end if
   put tOk into pRuling["success"]
   put pSkill & ": " & d && tSign && abs(pBonus) && "=" && (d + pBonus) && "against" && pDC & ", " & tWord into pRuling["roll"]
   return tOk
end ttRoll

-- the voice (talk) or the narrator (everything else) words the ruling
private command ttWords
   local tA, tV, tR, tC, i, tKnown, tGuard
   put sT["ruling"] into tR
   put sT["player"]["name"] into tV["player"]
   put sT["action"] into tV["action"]
   put sScene["place"] into tV["place"]
   put TTRPG.RecentText(sScene, sT["player"]["name"]) into tV["recent"]
   put the long id of me into tA["target"]
   put "TTRPG.OnWords" into tA["msg"]
   if tR["kind"] is "talk" then
      put ttCharById(tR["who"]) into tC
      if tR["success"] is "true" then
         put "The player has earned your trust or seen through you: let your secret slip now." into tGuard
      else
         put "Do not give your secret away; you may hint that you have one." into tGuard
      end if
      -- the character's own persona only: never the clues, the truth or anyone else's secret
      repeat for each item i in "name,look,voice,wants,secret"
         put tC[i] into tV[i]
      end repeat
      put tGuard into tV["guard"]
      put "voice" into tA["role"]
      put TTRPG.LM.Voices() into tA["model"]
      put TTRPG.Fill("voice", tV) into tA["system"]
      put TTRPG.Fill("voice_user", tV) into tA["user"]
      put sCfg["temp_voice"] into tA["temperature"]
      put sCfg["max_voice"] into tA["maxTokens"]
   else
      -- only clues ALREADY found, never the open ones; the new one comes in RESULT alone
      repeat with i = 1 to the number of elements of sScene["clues"]
         if sScene["clues"][i]["found"] is "true" and sScene["clues"][i]["id"] is not tR["clue"] then
            put sScene["clues"][i]["fact"] & space after tKnown
         end if
      end repeat
      repeat with i = 1 to the number of elements of sScene["characters"]
         if sScene["characters"][i]["revealed"] is "true" then put sScene["characters"][i]["secret"] & space after tKnown
      end repeat
      put word 1 to -1 of tKnown into tV["known"]
      if tV["known"] is empty then put "nothing yet" into tV["known"]
      put TTRPG.WhoLine(sScene) into tV["who"]
      put sScene["summary"] into tV["summary"]
      if tV["summary"] is empty then put "The scene has just begun." into tV["summary"]
      put tR["result"] into tV["result"]
      put "dm" into tA["role"]
      put TTRPG.LM.DM() into tA["model"]
      put TTRPG.Fill("dm_turn") into tA["system"]
      put TTRPG.Fill("dm_turn_user", tV) into tA["user"]
      put sCfg["temp_dm"] into tA["temperature"]
      put sCfg["max_dm"] into tA["maxTokens"]
   end if
   TTRPG.LM.Chat tA
end ttWords

private function ttCharById pId
   local i
   repeat with i = 1 to the number of elements of sScene["characters"]
      if sScene["characters"][i]["id"] is pId then return sScene["characters"][i]
   end repeat
   return empty
end ttCharById

on TTRPG.OnWords pText, pErr
   local tR, tC, tShown, tText, tTurn, tSaid, i
   if not sBusy then exit TTRPG.OnWords              -- cancelled
   put sT["ruling"] into tR
   if pErr is not empty then ttTell "TTRPG.Status", "model error: " & pErr
   if tR["roll"] is not empty then put "roll" & tab & tR["roll"] & return after tShown
   if tR["kind"] is "talk" then
      put ttCharById(tR["who"]) into tC
      put TTRPG.CleanSpeech(pText, tC["name"]) into tText
      if tText is empty then put "..." into tText
      put tC["name"] & tab & tText & return after tShown
      put tC["name"] into tSaid
      if tR["success"] is "true" and tC["secret"] is not empty then
         -- small models rarely let it slip even when told to (TUNING.md, W2): the code shows it,
         -- word for word, as it does a found clue; from now on it is known, not hidden
         repeat with i = 1 to the number of elements of sScene["characters"]
            if sScene["characters"][i]["id"] is tR["who"] then put "true" into sScene["characters"][i]["revealed"]
         end repeat
         put "secret" & tab & tC["name"] & ": " & tC["secret"] & return after tShown
      end if
   else
      put TTRPG.CleanNarration(pText, 4) into tText
      if tR["clue"] is not empty and tR["success"] is "true" then
         if tText is empty then put "You find something." into tText
         put "DM" & tab & tText & return after tShown
         -- the clue itself, word for word: small models blur it
         repeat with i = 1 to the number of elements of sScene["clues"]
            if sScene["clues"][i]["id"] is tR["clue"] then put "clue" & tab & sScene["clues"][i]["fact"] & return after tShown
         end repeat
      else
         if tText is empty then put "Nothing changes." into tText
         put "DM" & tab & tText & return after tShown
      end if
      put "DM" into tSaid
   end if
   delete the last char of tShown
   put sT["action"] into tTurn["action"]
   put tR into tTurn["ruling"]
   put tSaid into tTurn["speaker"]
   put tText into tTurn["reply"]
   ttListAppend sScene["turns"], tTurn
   ttSaveScene
   put tShown into sLastShown
   put empty into sT
   ttTell "TTRPG.Shown", tShown
   TTRPG.Fold
end TTRPG.OnWords

function TTRPG.LastShown
   return sLastShown
end TTRPG.LastShown

-- Rolling summary: exchanges older than the last keep_turns are folded into the summary,
-- summary_every at a time. Ends the turn (TTRPG.Done) either way.
command TTRPG.Fold
   local tOld, tNotes, i, tA, tPlayer
   put the number of elements of sScene["turns"] - sCfg["keep_turns"] into tOld
   if tOld - sScene["folded"] < sCfg["summary_every"] then
      ttDone
      exit TTRPG.Fold
   end if
   put TTRPG.Player() into tPlayer
   put tPlayer["name"] into tPlayer
   put sScene["summary"] into tNotes
   repeat with i = sScene["folded"] + 1 to tOld
      put return & tPlayer & ": " & sScene["turns"][i]["action"] & return & \
            sScene["turns"][i]["speaker"] & ": " & sScene["turns"][i]["reply"] after tNotes
   end repeat
   put tOld into sT["foldTo"]
   put "summary" into tA["role"]
   put TTRPG.LM.DM() into tA["model"]
   put TTRPG.Fill("summary") into tA["system"]
   put word 1 to -1 of tNotes into tA["user"]
   put 0.2 into tA["temperature"]
   put sCfg["max_summary"] into tA["maxTokens"]
   put the long id of me into tA["target"]
   put "TTRPG.OnSummary" into tA["msg"]
   TTRPG.LM.Chat tA
end TTRPG.Fold

on TTRPG.OnSummary pText, pErr
   if not sBusy then exit TTRPG.OnSummary
   if pText is not empty then
      put ttSquash(pText) into sScene["summary"]
      put sT["foldTo"] into sScene["folded"]
      ttSaveScene
   end if
   put empty into sT
   ttDone
end TTRPG.OnSummary

-------------------------------------------------------------------- text helpers

-- "Name (look); Name (look)" or "nobody else"
function TTRPG.WhoLine pScene
   local i, tOut
   repeat with i = 1 to the number of elements of pScene["characters"]
      put "; " & pScene["characters"][i]["name"] & " (" & pScene["characters"][i]["look"] & ")" after tOut
   end repeat
   if tOut is empty then return "nobody else"
   return char 3 to -1 of tOut
end TTRPG.WhoLine

-- the last keep_turns exchanges, or the opening when there are none yet
function TTRPG.RecentText pScene, pPlayer
   local n, i, tOut, tFrom
   put the number of elements of pScene["turns"] into n
   if n is 0 then return pScene["opening"]
   put max(1, n - TTRPG.Cfg.Get("keep_turns") + 1) into tFrom
   repeat with i = tFrom to n
      put space & pPlayer & ": " & pScene["turns"][i]["action"] && pScene["turns"][i]["speaker"] & ": " & pScene["turns"][i]["reply"] after tOut
   end repeat
   return char 2 to -1 of tOut
end TTRPG.RecentText

-- whitespace runs -> one space, trimmed (Python ' '.join(text.split()))
private function ttSquash pText
   return word 1 to -1 of replaceText(pText, "\s+", " ")
end ttSquash

-- sentences, one a line. A sentence ends at . ! ? (a run of them, then closing quotes or
-- brackets) followed by a space or the end; the last piece may have no end mark.
function TTRPG.Sentences pText
   local t, n, i, tCur, tOut, tCloser
   put ttSquash(pText) into t
   put the number of chars of t into n
   put quote & "')]" & numToCodepoint(8221) into tCloser
   put 1 into i
   repeat while i <= n
      put char i of t after tCur
      if char i of t is among the chars of ".!?" then
         repeat while i < n and char i + 1 of t is among the chars of ".!?"
            add 1 to i
            put char i of t after tCur
         end repeat
         repeat while i < n and char i + 1 of t is among the chars of tCloser
            add 1 to i
            put char i of t after tCur
         end repeat
         if i = n or char i + 1 of t is space then
            if word 1 to -1 of tCur is not empty then put word 1 to -1 of tCur & return after tOut
            put empty into tCur
         end if
      end if
      add 1 to i
   end repeat
   if word 1 to -1 of tCur is not empty then put word 1 to -1 of tCur & return after tOut
   delete the last char of tOut
   return tOut
end TTRPG.Sentences

-- drop a cut-off last sentence (a reply that hit its token limit)
function TTRPG.WholeSentences pText
   local n, i, tEnd, tCloser
   put the number of chars of pText into n
   put quote & "')]" into tCloser
   put 0 into tEnd
   repeat with i = 1 to n
      if char i of pText is among the chars of ".!?" then
         if i < n and char i + 1 of pText is among the chars of tCloser and (i + 1 = n or ttIsSpace(char i + 2 of pText)) then
            put i + 1 into tEnd
         else if i = n or ttIsSpace(char i + 1 of pText) then
            put i into tEnd
         end if
      end if
   end repeat
   if tEnd is 0 then return pText
   return char 1 to tEnd of pText
end TTRPG.WholeSentences

private function ttIsSpace c
   return c is space or c is tab or c is numToChar(10) or c is numToChar(13)
end ttIsSpace

-- the narrator's reply as shown: no markdown, no option lists, no closing question, a few sentences
function TTRPG.CleanNarration pText, pMax
   local tLine, tKeep, tOut, s, n, tBare
   put replaceText(pText, "[*_#`]+", empty) into pText
   put replaceText(pText, "(?i)^\s*(DM|Narrator|RESULT|Narration)\s*:\s*", empty) into pText
   replace numToChar(13) & numToChar(10) with numToChar(10) in pText
   replace numToChar(13) with numToChar(10) in pText
   repeat for each line tLine in pText
      if matchText(tLine, "^\s*(\d+[.)]|[-*" & numToCodepoint(8226) & "]|[A-Da-d][.)])\s+") then exit repeat   -- a list of choices: stop before it
      if word 1 to -1 of tLine is not empty then put word 1 to -1 of tLine & space after tKeep
   end repeat
   put 0 into n
   repeat for each line s in TTRPG.Sentences(tKeep)
      put s into tBare
      repeat while the last char of tBare is quote or the last char of tBare is numToCodepoint(8221)
         delete the last char of tBare
      end repeat
      if matchText(s, kAsking) or the last char of tBare is "?" then next repeat
      add 1 to n
      if n > pMax then exit repeat
      put s & space after tOut
   end repeat
   return word 1 to -1 of tOut
end TTRPG.CleanNarration

-- a character's reply as shown: their words only
function TTRPG.CleanSpeech pText, pName
   local tOut, s, n
   if matchText(pText, "\*[^*\n]+\*") then put replaceText(pText, "[*_#`]+[^*_#`\n]*[*_#`]+", " ") into pText
   put replaceText(pText, "\([^)]*\)", " ") into pText
   replace "\E" with empty in pName
   put replaceText(word 1 to -1 of pText, "(?i)^\s*\Q" & pName & "\E\s*((says|replies|speaks|answers)( aloud)?)?\s*[:,]\s*", empty) into pText
   put replaceText(pText, "[" & quote & numToCodepoint(8220) & numToCodepoint(8221) & "]", empty) into pText
   put 0 into n
   repeat for each line s in TTRPG.Sentences(ttSquash(pText))
      add 1 to n
      if n > 3 then exit repeat
      put s & space after tOut
   end repeat
   return word 1 to -1 of tOut
end TTRPG.CleanSpeech

function TTRPG.Slug pText
   put replaceText(toLower(pText), "[^a-z0-9]+", "_") into pText
   repeat while char 1 of pText is "_"
      delete char 1 of pText
   end repeat
   repeat while the last char of pText is "_"
      delete the last char of pText
   end repeat
   put char 1 to 40 of pText into pText
   if pText is empty then return "x"
   return pText
end TTRPG.Slug

-- the words of a name a player would use: "Elder Elias" -> elias (one a line)
function TTRPG.NameWords pName
   local w, tOut
   repeat for each word w in replaceText(toLower(pName), "[^a-z]+", " ")
      if w is not among the items of kNameNoise and the number of chars of w > 2 then put w & return after tOut
   end repeat
   delete the last char of tOut
   if tOut is empty then return toLower(pName)
   return tOut
end TTRPG.NameWords

function TTRPG.IsNamed pName, pAction
   local tSaid, w
   put space & replaceText(toLower(pAction), "[^a-z]+", " ") & space into tSaid
   repeat for each line w in TTRPG.NameWords(pName)
      if tSaid contains (space & w & space) then return true
   end repeat
   return false
end TTRPG.IsNamed

-------------------------------------------------------------------- lists and schemas

-- arrays keyed 1..n stand for lists
private command ttListAppend @pList, pV
   local n
   if pList is not an array then put empty into pList
   put the number of elements of pList + 1 into n
   put pV into pList[n]
end ttListAppend

private command ttListDelete @pList, pIdx
   local n, i
   put the number of elements of pList into n
   if pIdx < 1 or pIdx > n then exit ttListDelete
   repeat with i = pIdx to n - 1
      put pList[i + 1] into pList[i]
   end repeat
   delete variable pList[n]
   if the number of elements of pList is 0 then put empty into pList
end ttListDelete

private function ttLinesOf pItems
   replace comma with return in pItems
   return pItems
end ttLinesOf

private function ttJoin pLines, pDel, pLast
   if pLines is empty then return pLast
   return pLines & pDel & pLast
end ttJoin

-- a JSON string-enum (one value a line): a list, even with one entry
private function ttEnum pLines
   local v, tOut
   repeat for each line v in pLines
      put "," & TTRPG.JSON.Quote(v) after tOut
   end repeat
   return "{" & quote & "type" & quote & ":" & quote & "string" & quote & "," & quote & "enum" & quote & ":[" & char 2 to -1 of tOut & "]}"
end ttEnum

private function ttStr
   return "{" & quote & "type" & quote & ":" & quote & "string" & quote & "}"
end ttStr

private function ttCharacterSchema
   local k, tP, tR
   repeat for each item k in "name,look,voice,wants,secret"
      put "," & quote & k & quote & ":" & ttStr() after tP
      put "," & quote & k & quote after tR
   end repeat
   return "{" & quote & "type" & quote & ":" & quote & "object" & quote & "," & quote & "properties" & quote & ":{" & char 2 to -1 of tP & "}," & \
         quote & "required" & quote & ":[" & char 2 to -1 of tR & "]}"
end ttCharacterSchema

private function ttSceneSchema
   local tP, k, tR, tClue
   repeat for each item k in "title,truth,place,happening,wrong"
      put "," & quote & k & quote & ":" & ttStr() after tP
   end repeat
   put "{" & quote & "type" & quote & ":" & quote & "object" & quote & "," & quote & "properties" & quote & ":{" & \
         quote & "where" & quote & ":" & ttStr() & "," & quote & "skill" & quote & ":" & ttEnum(ttLinesOf(kSkills)) & "," & \
         quote & "fact" & quote & ":" & ttStr() & "}," & quote & "required" & quote & ":[" & \
         quote & "where" & quote & "," & quote & "skill" & quote & "," & quote & "fact" & quote & "]}" into tClue
   put "," & quote & "clues" & quote & ":{" & quote & "type" & quote & ":" & quote & "array" & quote & "," & \
         quote & "minItems" & quote & ":3," & quote & "maxItems" & quote & ":4," & quote & "items" & quote & ":" & tClue & "}" after tP
   put "," & quote & "npc" & quote & ":" & ttCharacterSchema() after tP
   repeat for each item k in "title,truth,place,happening,wrong,clues,npc"
      put "," & quote & k & quote after tR
   end repeat
   return "{" & quote & "type" & quote & ":" & quote & "object" & quote & "," & quote & "properties" & quote & ":{" & char 2 to -1 of tP & "}," & \
         quote & "required" & quote & ":[" & char 2 to -1 of tR & "]}"
end ttSceneSchema

-- for the tests: the schemas as built
function TTRPG.Schemas
   return ttSceneSchema() & return & ttCharacterSchema()
end TTRPG.Schemas

-------------------------------------------------------------------- tests

-- ref/vectors.json: every input and expected output of the Python text helpers.
-- -> one line a check (PASS / FAIL), then ALL PASS or "n FAILED"
function TTRPG.SelfTest pVectorsPath
   local tV, tOut, tFails, i, tCase, tGot, tWant, k, tA, tB, tJ
   put TTRPG.JSON.Parse(textDecode(URL ("binfile:" & pVectorsPath), "UTF-8")) into tV
   if tV is not an array then return "FAIL vectors not read: " & TTRPG.JSON.Error()
   put 0 into tFails
   repeat with i = 1 to the number of elements of tV["clean_narration_max4"]
      put tV["clean_narration_max4"][i] into tCase
      ttCheck tOut, tFails, "clean_narration " & i, TTRPG.CleanNarration(tCase[1], 4), tCase[2]
   end repeat
   repeat with i = 1 to the number of elements of tV["clean_speech"]
      put tV["clean_speech"][i] into tCase
      ttCheck tOut, tFails, "clean_speech " & i, TTRPG.CleanSpeech(tCase[2], tCase[1]), tCase[3]
   end repeat
   repeat with i = 1 to the number of elements of tV["sentences"]
      put tV["sentences"][i] into tCase
      put empty into tWant
      repeat with k = 1 to the number of elements of tCase[2]
         put tCase[2][k] & return after tWant
      end repeat
      delete the last char of tWant
      ttCheck tOut, tFails, "sentences " & i, TTRPG.Sentences(tCase[1]), tWant
   end repeat
   repeat with i = 1 to the number of elements of tV["whole_sentences"]
      put tV["whole_sentences"][i] into tCase
      ttCheck tOut, tFails, "whole_sentences " & i, TTRPG.WholeSentences(tCase[1]), tCase[2]
   end repeat
   repeat with i = 1 to the number of elements of tV["slug"]
      put tV["slug"][i] into tCase
      ttCheck tOut, tFails, "slug " & i, TTRPG.Slug(tCase[1]), tCase[2]
   end repeat
   repeat with i = 1 to the number of elements of tV["name_words"]
      put tV["name_words"][i] into tCase
      put empty into tWant
      repeat with k = 1 to the number of elements of tCase[2]
         put tCase[2][k] & return after tWant
      end repeat
      delete the last char of tWant
      ttCheck tOut, tFails, "name_words " & i, TTRPG.NameWords(tCase[1]), tWant
   end repeat
   repeat with i = 1 to the number of elements of tV["is_named"]
      put tV["is_named"][i] into tCase
      ttCheck tOut, tFails, "is_named " & i, TTRPG.IsNamed(tCase[1], tCase[2]), tCase[3]
   end repeat
   -- JSON round trip: true / false stay booleans, lists stay lists, text survives
   put "true" into tA["found"]
   put "false" into tA["player"]
   put 3 into tA["tries"]
   put "one" into tA["clues"][1]
   put "it said " & quote & "go" & quote & return & "then\left" & tab & "x" into tA["text"]
   put empty into tA["turns"]
   put TTRPG.JSON.Export(tA) into tJ
   put TTRPG.JSON.Parse(tJ) into tB
   ttCheck tOut, tFails, "json booleans", tB["found"] & "," & tB["player"], "true,false"
   ttCheck tOut, tFails, "json writes true bare", (tJ contains (quote & "found" & quote & ": true")), true
   ttCheck tOut, tFails, "json list", tB["clues"][1], "one"
   ttCheck tOut, tFails, "json text", tB["text"], tA["text"]
   ttCheck tOut, tFails, "json empty list", (tJ contains (quote & "turns" & quote & ": []")), true
   put TTRPG.JSON.Parse("[" & quote & "\" & "u00c9" & "\" & "ud83d" & "\" & "ude00" & quote & "]") into tB
   put tB[1] into tB
   ttCheck tOut, tFails, "json unicode escape", tB, numToCodepoint(201) & numToCodepoint(128512)
   ttCheck tOut, tFails, "json bad text", TTRPG.JSON.Parse("{" & quote & "a" & quote & ":}") is empty and TTRPG.JSON.Error() is not empty, true
   put TTRPG.JSON.Parse(line 1 of TTRPG.Schemas()) into tB
   ttCheck tOut, tFails, "scene schema parses", tB["required"][6], "clues"
   put TTRPG.JSON.Parse(line 2 of TTRPG.Schemas()) into tB
   ttCheck tOut, tFails, "character schema parses", tB["properties"]["secret"]["type"], "string"
   if tFails is 0 then
      put "ALL PASS" after tOut
   else
      put tFails && "FAILED" after tOut
   end if
   return tOut
end TTRPG.SelfTest

private command ttCheck @pOut, @pFails, pName, pGot, pWant
   if pGot is pWant then
      put "PASS  " & pName & return after pOut
   else
      add 1 to pFails
      replace return with "|" in pGot
      replace return with "|" in pWant
      put "FAIL  " & pName & "  got [" & pGot & "] want [" & pWant & "]" & return after pOut
   end if
end ttCheck

private command ttWaitIdle
   local tUntil
   put the milliseconds + 600000 into tUntil
   repeat while sBusy and the milliseconds < tUntil
      wait 50 milliseconds with messages
   end repeat
end ttWaitIdle

-- the owner's test, steps 2, 3, 4 and 6, run by script (cmd_test in ttrpg_ref.py).
-- Needs TTRPG.Init and a loaded model (TTRPG.LM.LoadModels or TTRPG.LM.UseModels).
function TTRPG.OwnerTest
   local tOut, tFails, n, tLeaked, i, tFound, tNow, tNpc, tBefore, tCalls, tRoles, tLast, k, tActs, tAll, tOk, tSearches
   put 0 into tFails
   TTRPG.Scene.New "a flooded crypt under a chapel"
   ttWaitIdle
   put the number of lines of TTRPG.Sentences(sScene["opening"]) into n
   put "OPENING: " & sScene["opening"] & return after tOut
   ttCheck tOut, tFails, "2 opening is 3 to 5 sentences (" & n & ")", (n >= 3 and n <= 5), true
   ttCheck tOut, tFails, "2 opening has no options or questions", (not matchText(sScene["opening"], kAsking) and not (sScene["opening"] contains "?")), true
   repeat with i = 1 to the number of elements of sScene["clues"]
      if sScene["opening"] contains sScene["clues"][i]["fact"] then put i & space after tLeaked
   end repeat
   ttCheck tOut, tFails, "2 opening gives no clue away", tLeaked, empty
   ttCheck tOut, tFails, "scene has 3+ clues and a character", (the number of elements of sScene["clues"] >= 3 and the number of elements of sScene["characters"] >= 1), true
   put 0 into tFound
   repeat with tSearches = 1 to 4                      -- a failed roll is allowed; keep looking
      TTRPG.Turn.Begin "I search the walls for carvings"
      ttWaitIdle
      put "  " & TTRPG.LastShown() & return after tOut
      put 0 into tNow
      repeat with k = 1 to the number of elements of sScene["clues"]
         if sScene["clues"][k]["found"] is "true" then add 1 to tNow
      end repeat
      ttCheck tOut, tFails, "3 search " & tSearches & " gives at most one clue (" & tNow & " found)", (tNow - tFound <= 1), true
      if tNow > tFound then
         put tNow into tFound
         exit repeat
      end if
   end repeat
   if tSearches > 4 then put 4 into tSearches
   ttCheck tOut, tFails, "3 a clue was found within 4 searches", tFound, 1
   repeat with i = 1 to the number of elements of sScene["characters"]
      if sScene["characters"][i]["player"] is not "true" then
         put sScene["characters"][i] into tNpc
         exit repeat
      end if
   end repeat
   put the number of lines of TTRPG.LM.Calls() into tBefore
   TTRPG.Turn.Begin "I ask " & tNpc["name"] & ", " & quote & "What happened down here?" & quote
   ttWaitIdle
   put "  " & TTRPG.LastShown() & return after tOut
   put line tBefore + 1 to -1 of TTRPG.LM.Calls() into tCalls
   set the itemDel to tab
   repeat for each line tLast in tCalls
      put item 1 of tLast & space after tRoles
   end repeat
   put line -1 of TTRPG.LastShown() into tLast
   ttCheck tOut, tFails, "4 the character answers: " & char 1 to 60 of item 2 of tLast, (item 1 of tLast is tNpc["name"] and the number of chars of item 2 of tLast > 3), true
   ttCheck tOut, tFails, "4 the DM does not answer for it (" & tRoles & ")", ("dm" is among the words of tRoles), false
   ttCheck tOut, tFails, "4 the Voices model spoke", ("voice" & tab & TTRPG.LM.Voices() is among the lines of tCalls), true
   TTRPG.Turn.Redo
   ttWaitIdle
   put line -1 of TTRPG.LastShown() into tLast
   ttCheck tOut, tFails, "regenerate keeps the turn count and the speaker", (the number of elements of sScene["turns"] is tSearches + 1 and item 1 of tLast is tNpc["name"]), true
   set the itemDel to comma
   put "I wade further in,I listen,I hold up my lantern,I wait,I touch the water,I look up,I step back" into tActs
   repeat with k = 1 to sCfg["summary_every"] + sCfg["keep_turns"]
      TTRPG.Turn.Begin item ((k - 1) mod 7 + 1) of tActs
      ttWaitIdle
   end repeat
   ttCheck tOut, tFails, "5 rolling summary was made: " & char 1 to 80 of sScene["summary"], (sScene["summary"] is not empty), true
   TTRPG.Scene.End tNpc["name"]
   put TTRPG.Constants() into tAll
   put false into tOk
   repeat with i = 1 to the number of elements of tAll
      if tAll[i]["name"] is tNpc["name"] then put true into tOk
   end repeat
   ttCheck tOut, tFails, "6 promoted character is still there", tOk, true
   ttCheck tOut, tFails, "6 session log is saved " & TTRPG.LM.LogPath(), (there is a file TTRPG.LM.LogPath() and URL ("binfile:" & TTRPG.LM.LogPath()) is not empty), true
   if tFails is 0 then
      put "ALL PASS" after tOut
   else
      put tFails && "FAILED" after tOut
   end if
   return tOut
end TTRPG.OwnerTest
