######################################################################################
## STACK SCRIPT: "TTRPG_Studio" (LIB_TTRPG, iteration 1, 15 Nov 2026)
## UI handlers only: the engine is lib_ttrpg, the model calls lib_ttrpg_lm. Built by
## build_studio.livecodescript; this text is the stack script it sets.
## Card 1 "About" (rule 17), card 2 "Studio":
##   LEFT    Models: DM and Voices option menus (Voices starts on "Same as DM"),
##           Refresh / Load / Unload, one status line.
##   MIDDLE  the Scene (title + opening), the chat log, the input (Return sends), "thinking...".
##   RIGHT   Characters (click = edit; New, Delete, Keep after scene, Save), your character's sheet (18 skills).
##   SKILLS  18 buttons over the input: a click starts the line "I use <skill>: " (the engine honours it).
##   TOP     New Scene, Add Character, Regenerate (Ctrl+R), DM Notes, End Scene, About.
##   Escape  pauses (rule 18): cancels a running call and shows the developer options.
## Card 3 "World" (owner, 23 Nov; the TOP button World): the map of cells (click = see/edit, next to @ = walk),
##   the cell as plain data (Apply), Verbose = the DM model words it, Here (-> Add as character), Scene here.
##   While a world is loaded, St.Send tries TTRPG.World.Act first (no model needed); during a scene,
##   look / search go to the DM (they find the clues).
## The libraries are found next to the stack (livecode/, or ../LIB_TTRPG/livecode/ from LIB_TEST);
## if not, the copies the builder put in as substacks are used. Same for the prompts.
######################################################################################

local sDir, sCharIdx, sEscAt, sLogHTML, sLibs
local sWorld, sWPlayer, sWCell, sWDirty, sHereKeys, sHereIdx, sWords, sWordsKey, sWordsLoc

on openStack
   St.Init
end openStack

on St.Init
   local tPath, tLib, tFolder, tA
   put the effective filename of this stack into tPath
   set the itemDel to "/"
   put item 1 to -2 of tPath into sDir
   set the itemDel to comma
   put empty into sLibs
   St.UseLib "lib_ttrpg_lm.livecodescript", "TTRPG_Studio_lm"
   St.UseLib "lib_ttrpg.livecodescript", "TTRPG_Studio_engine"
   St.UseLib "lib_ttrpg_world.livecodescript", "TTRPG_Studio_world"
   put St.Find("../LIB_DATA/livecode/lib_data.livecodescript") into tLib
   if tLib is empty then
      start using stack "TTRPG_Studio_data"
      put "data: copy inside the stack" & return after sLibs
   else
      start using stack tLib
      put "data: " & tLib & return after sLibs
   end if
   TTRPG.Init the long id of this stack, empty
   put St.Find("prompts") into tFolder
   if tFolder is empty then put St.Find("../LIB_TTRPG/prompts") into tFolder
   if tFolder is not empty and there is a folder tFolder then
      TTRPG.Prompts.Load tFolder
      put "prompts: " & tFolder & return after sLibs
   else
      set the customPropertySet of this stack to "Prompts"
      put the customProperties of this stack into tA
      set the customPropertySet of this stack to empty
      TTRPG.Prompts.Use tA
      put "prompts: copy inside the stack" & return after sLibs
   end if
   put empty into sLogHTML
   lock screen
   go card "Studio"
   set the visible of group "Pause" of card "Studio" to false
   set the visible of field "Notes" of card "Studio" to false
   set the visible of field "Thinking" of card "Studio" to false
   put empty into field "Log" of card "Studio"
   put "No scene yet. Load a model, then press New Scene." into field "SceneText" of card "Studio"
   St.FillPlayer
   St.FillChars
   St.WorldShow
   unlock screen
   St.Status "Looking for LM Studio..."
   send "St.Refresh" to me in 20 milliseconds
end St.Init

-- the library file next to the stack, else its copy inside the stack
on St.UseLib pFile, pCopy
   local tLib
   put St.Find("livecode/" & pFile) into tLib
   if tLib is empty then put St.Find("../LIB_TTRPG/livecode/" & pFile) into tLib
   if tLib is empty then
      start using stack pCopy
      put pFile & ": copy inside the stack" & return after sLibs
   else
      start using stack tLib
      put pFile & ": " & tLib & return after sLibs
   end if
end St.UseLib

function St.Find pRel
   local tPath
   put sDir & "/" & pRel into tPath
   if there is a file tPath or there is a folder tPath then return tPath
   return empty
end St.Find

function St.Libs
   return sLibs
end St.Libs

on closeStackRequest
   if sWDirty is true then
      answer "The world has changes that are not saved." with "Close anyway" or "Save World"
      if it is "Save World" then St.WorldSave
   end if
   try
      TTRPG.Cancel
      TTRPG.LM.UnloadMine          -- only what this stack loaded: a model found loaded may be Spark at work
   catch tErr
   end try
   set the destroyStack of this stack to true
   close stack (the mainStack of this stack)
end closeStackRequest

-------------------------------------------------------------------- clicks

on St.Click pName
   switch pName
      case "NewScene"
         St.NewScene
         break
      case "AddCharacter"
         St.AddCharacter
         break
      case "Regenerate"
         St.Regenerate
         break
      case "Notes"
         St.Notes
         break
      case "EndScene"
         St.EndScene
         break
      case "About"
         go card "About"
         break
      case "World"
         go card "World"
         St.WorldShow
         break
      case "WorldBack"
         go card "Studio"
         break
      case "WorldNew"
         St.WorldNew
         break
      case "WorldLoad"
         St.WorldLoad
         break
      case "WorldSave"
         St.WorldSave
         break
      case "SceneHere"
         St.SceneHere
         break
      case "Verbose"
         St.WorldWords
         break
      case "CellApply"
         St.CellApply
         break
      case "CellRevert"
         St.WorldShow
         break
      case "HereAdd"
         St.HereAdd
         break
      case "Start"
         go card "Studio"
         break
      case "Refresh"
         St.Refresh
         break
      case "Load"
         St.Load
         break
      case "Unload"
         St.Unload
         break
      case "CharNew"
         St.CharNew
         break
      case "CharDelete"
         St.CharDelete
         break
      case "CharSave"
         St.CharSave
         break
      case "PlayerSave"
         St.PlayerSave
         break
      case "Resume"
         St.Resume
         break
      default
         if pName begins with "Skill:" then St.UseSkill char 7 to -1 of pName
   end switch
end St.Click

on commandKeyDown pKey
   if pKey is "r" then
      St.Regenerate
   else
      pass commandKeyDown
   end if
end commandKeyDown

on controlKeyDown pKey
   if pKey is "r" then
      St.Regenerate
   else
      pass controlKeyDown
   end if
end controlKeyDown

-- Escape first pauses (rule 18): the running call is cancelled, the developer options show
on escapeKey
   if the milliseconds - sEscAt < 300 then exit escapeKey
   put the milliseconds into sEscAt
   if the short name of this card is not "Studio" then
      go card "Studio"
      exit escapeKey
   end if
   if the visible of group "Pause" of card "Studio" then
      St.Resume
   else
      St.Pause
   end if
end escapeKey

-------------------------------------------------------------------- models

on St.Refresh
   local tModels, tIds, tLine, tLoaded, tDM, tStatus
   put TTRPG.LM.Models() into tModels
   if tModels is empty then
      St.Status "LM Studio server is not running (open LM Studio, Developer tab, Start Server), then press Refresh. Load also tries to start it."
      exit St.Refresh
   end if
   set the itemDel to tab
   repeat for each line tLine in tModels
      put item 1 of tLine & return after tIds
      if item 2 of tLine is "loaded" then put item 1 of tLine & return after tLoaded
   end repeat
   set the itemDel to comma
   delete the last char of tIds
   delete the last char of tLoaded
   put the label of button "DMMenu" of card "Studio" into tDM
   set the text of button "DMMenu" of card "Studio" to tIds
   set the text of button "VoicesMenu" of card "Studio" to "Same as DM" & return & tIds
   if tDM is empty or tDM is not among the lines of tIds then
      if "gemma-2-2b-it-abliterated" is among the lines of tIds then
         put "gemma-2-2b-it-abliterated" into tDM
      else
         put line 1 of tIds into tDM
      end if
   end if
   set the label of button "DMMenu" of card "Studio" to tDM
   if the label of button "VoicesMenu" of card "Studio" is not among the lines of tIds then
      set the label of button "VoicesMenu" of card "Studio" to "Same as DM"
   end if
   put the number of lines of tIds && "models." into tStatus
   if tLoaded is not empty then
      replace return with ", " in tLoaded
      put " Loaded now: " & tLoaded & "." after tStatus
   end if
   if TTRPG.LM.DM() is not empty then
      put " In use: DM " & TTRPG.LM.DM() & ", Voices " & TTRPG.LM.Voices() & "." after tStatus
   else
      put " Pick a DM and press Load." after tStatus
   end if
   St.Status tStatus
end St.Refresh

on St.Load
   if TTRPG.Busy() then exit St.Load
   St.Status "loading " & the label of button "DMMenu" of card "Studio" & "... (5 to 30 seconds a model)"
   St.Thinking true
   send "St.DoLoad" to me in 20 milliseconds
end St.Load

on St.DoLoad
   local tStatus
   put TTRPG.LM.LoadModels(the label of button "DMMenu" of card "Studio", the label of button "VoicesMenu" of card "Studio") into tStatus
   St.Thinking false
   St.Status tStatus
   St.Log "note", empty, tStatus
end St.DoLoad

on St.Unload
   if TTRPG.Busy() then TTRPG.Cancel
   TTRPG.LM.UnloadMine
   TTRPG.LM.UseModels empty, empty
   St.Status "Unloaded what this stack loaded (a model that was loaded before stays)."
end St.Unload

function St.Ready
   if TTRPG.LM.DM() is empty then
      St.Status "Load a model first: pick a DM on the left, press Load."
      return false
   end if
   if TTRPG.Busy() or TTRPG.LM.Busy() then
      St.Status "Still thinking. Esc cancels."
      return false
   end if
   return true
end St.Ready

-------------------------------------------------------------------- play

-- pIdea given (Scene here): no question asked
on St.NewScene pIdea
   local tIdea
   if not St.Ready() then exit St.NewScene
   if pIdea is empty then
      ask "One line: what is the scene?" with "a flooded crypt under a chapel"
      if it is empty or the result is "Cancel" then exit St.NewScene
      put it into tIdea
   else
      put pIdea into tIdea
   end if
   put empty into sLogHTML
   set the visible of field "Notes" of card "Studio" to false
   put "Making the scene: " & tIdea into field "SceneText" of card "Studio"
   St.Log "note", empty, "making the scene (" & TTRPG.LM.DM() & ")..."
   St.Thinking true
   TTRPG.Scene.New tIdea
end St.NewScene

on St.Send
   local tLine, tScene, tPlayer, tReply
   put word 1 to -1 of field "Input" of card "Studio" into tLine
   if tLine is empty then exit St.Send
   put TTRPG.Scene() into tScene
   -- a world loaded: its actions first, no model needed (in a scene, look / search are the DM's: clues)
   if sWorld is an array and sWPlayer is not empty then
      if not (tScene["title"] is not empty and tScene["ended"] is not "true" and toLower(word 1 of tLine) is among the items of "look,l,search,examine") then
         TTRPG.World.Act sWorld, sWPlayer, tLine
         put the result into tReply
         if tReply is not empty then
            put TTRPG.Player() into tPlayer
            put empty into field "Input" of card "Studio"
            St.Log "player", tPlayer["name"], tLine
            St.Log "world", empty, tReply
            put true into sWDirty
            put sWorld["player"][sWPlayer]["location"] into sWCell
            St.WorldShow
            exit St.Send
         end if
      end if
   end if
   if not St.Ready() then exit St.Send
   if tScene["title"] is empty or tScene["ended"] is "true" then
      St.Status "No scene running: press New Scene."
      exit St.Send
   end if
   put TTRPG.Player() into tPlayer
   put empty into field "Input" of card "Studio"
   St.Log "player", tPlayer["name"], tLine
   St.Thinking true
   TTRPG.Turn.Begin tLine
end St.Send

on St.Regenerate
   local tScene
   if not St.Ready() then exit St.Regenerate
   put TTRPG.Scene() into tScene
   if the number of elements of tScene["turns"] is 0 or tScene["ended"] is "true" then
      St.Status "Nothing to regenerate yet."
      exit St.Regenerate
   end if
   -- note and mark first: the answer may come back before Redo returns
   St.Log "note", empty, "(again, in other words: same roll, same clue)"
   St.Thinking true
   TTRPG.Turn.Redo
end St.Regenerate

on St.AddCharacter
   local tAsk, tIdx
   answer "Add a character:" with "Cancel" or "By hand" or "Ask the DM model"
   if it is "By hand" then
      St.CharNew
   else if it is "Ask the DM model" then
      if not St.Ready() then exit St.AddCharacter
      ask "One line: who comes in?" with "a talking rat"
      if it is empty or the result is "Cancel" then exit St.AddCharacter
      St.Log "note", empty, "a character is being made: " & it
      St.Thinking true
      TTRPG.Character.Make it
   end if
end St.AddCharacter

on St.Notes
   if the visible of field "Notes" of card "Studio" then
      set the visible of field "Notes" of card "Studio" to false
      set the label of button "Notes" of card "Studio" to "DM Notes"
   else
      put TTRPG.Notes() into field "Notes" of card "Studio"
      set the visible of field "Notes" of card "Studio" to true
      set the label of button "Notes" of card "Studio" to "Back to Play"
   end if
end St.Notes

on St.EndScene
   local tScene, i, tKeep
   put TTRPG.Scene() into tScene
   if tScene["title"] is empty or tScene["ended"] is "true" then
      St.Status "No scene running."
      exit St.EndScene
   end if
   if TTRPG.Busy() then TTRPG.Cancel
   repeat with i = 1 to the number of elements of tScene["characters"]
      if tScene["characters"][i]["kind"] is "scene" and tScene["characters"][i]["keep"] is "true" then
         put tScene["characters"][i]["name"] & ", " after tKeep
      end if
   end repeat
   if tKeep is empty then
      put "none (tick Keep after scene on a character to keep it)" into tKeep
   else
      delete char -2 to -1 of tKeep
   end if
   answer "End the scene?" & return & "Kept for every new scene: " & tKeep with "Cancel" or "End Scene"
   if it is not "End Scene" then exit St.EndScene
   TTRPG.Scene.End empty
   St.Log "note", empty, "The scene ends. Kept: " & tKeep
   St.FillChars
end St.EndScene

-- a skill button: the line starts "I use <skill>: " (an earlier "I use ...: " is replaced), the rest is kept
on St.UseSkill pSkill
   local tLine
   put field "Input" of card "Studio" into tLine
   if matchText(tLine, "(?i)^\s*I use [A-Za-z ]+:\s*") then put replaceText(tLine, "(?i)^\s*I use [A-Za-z ]+:\s*", empty) into tLine
   put "I use " & pSkill & ": " & tLine into field "Input" of card "Studio"
   focus on field "Input" of card "Studio"
   select after text of field "Input" of card "Studio"
end St.UseSkill

-------------------------------------------------------------------- the engine talks back

on TTRPG.SceneReady
   local tScene
   put TTRPG.Scene() into tScene
   set the htmlText of field "SceneText" of card "Studio" to "<p><b>" & St.Esc(tScene["title"]) & "</b></p><p>" & St.Esc(tScene["opening"]) & "</p>"
   put empty into sLogHTML
   St.Log "note", empty, "== " & tScene["title"] & " ==   (type what you do; Return sends)"
   St.FillChars
   St.Status "Scene ready. Type what your character does."
end TTRPG.SceneReady

on TTRPG.Shown pLines
   local tLine
   set the itemDel to tab
   repeat for each line tLine in pLines
      St.Log item 1 of tLine, item 1 of tLine, item 2 to -1 of tLine
   end repeat
   set the itemDel to comma
   if the visible of field "Notes" of card "Studio" then put TTRPG.Notes() into field "Notes" of card "Studio"
end TTRPG.Shown

on TTRPG.CharacterMade pName
   if pName is empty then
      St.Log "error", empty, "(the model gave no character)"
   else
      St.Log "note", empty, "enters: " & pName
   end if
   St.FillChars
   if pName is not empty then
      St.CharPick the number of lines of field "CharList" of card "Studio"
   end if
end TTRPG.CharacterMade

on TTRPG.Status pText
   St.Log "error", empty, pText
   St.Status pText
end TTRPG.Status

on TTRPG.Done
   St.Thinking false
   St.FillChars
end TTRPG.Done

-------------------------------------------------------------------- the log

-- pKind: player, DM, roll, clue, secret, note, error, or a character's name
on St.Log pKind, pWho, pText
   local tP, tLine
   switch pKind
      case "player"
         put "<p><font color=" & quote & "#9fd3ff" & quote & "><b>" & St.Esc(pWho) & ":</b> " & St.Esc(pText) & "</font></p>" into tP
         break
      case "DM"
         put "<p>" & St.Esc(pText) & "</p>" into tP
         break
      case "roll"
         put "<p><font color=" & quote & "#8a8a92" & quote & ">[" & St.Esc(pText) & "]</font></p>" into tP
         break
      case "clue"
         put "<p><font color=" & quote & "#ffd75a" & quote & "><b>[clue]</b> " & St.Esc(pText) & "</font></p>" into tP
         break
      case "secret"
         put "<p><font color=" & quote & "#ff9fd0" & quote & "><b>[secret]</b> " & St.Esc(pText) & "</font></p>" into tP
         break
      case "world"
         repeat for each line tLine in pText
            put "<p><font color=" & quote & "#c9b8ff" & quote & ">" & St.Esc(tLine) & "</font></p>" after tP
         end repeat
         break
      case "note"
         put "<p><font color=" & quote & "#8a8a92" & quote & "><i>" & St.Esc(pText) & "</i></font></p>" into tP
         break
      case "error"
         put "<p><font color=" & quote & "#ff7a6a" & quote & ">" & St.Esc(pText) & "</font></p>" into tP
         break
      default
         put "<p><font color=" & quote & "#b6f0a8" & quote & "><b>" & St.Esc(pKind) & ":</b> " & St.Esc(pText) & "</font></p>" into tP
   end switch
   put tP after sLogHTML
   lock screen
   set the htmlText of field "Log" of card "Studio" to sLogHTML
   set the vScroll of field "Log" of card "Studio" to the formattedHeight of field "Log" of card "Studio"
   unlock screen
end St.Log

function St.Esc pText
   replace "&" with "&amp;" in pText
   replace "<" with "&lt;" in pText
   replace ">" with "&gt;" in pText
   return pText
end St.Esc

on St.Status pText
   put pText into field "Status" of card "Studio"
   put pText into field "ModelStatus" of card "Studio"
   if there is a field "WStatus" of card "World" of me then put pText into field "WStatus" of card "World" of me
end St.Status

on St.Thinking pOn
   set the visible of field "Thinking" of card "Studio" to pOn
end St.Thinking

-------------------------------------------------------------------- characters

on St.FillChars
   local tChars, i, tOut, tC
   put TTRPG.Chars() into tChars
   repeat with i = 1 to the number of elements of tChars
      put tChars[i] into tC
      put tC["name"] & "  (" & tC["kind"] after tOut
      if tC["keep"] is "true" and tC["kind"] is "scene" then put ", keep" after tOut
      put ")" & return after tOut
   end repeat
   delete the last char of tOut
   put tOut into field "CharList" of card "Studio"
   if sCharIdx > 0 and sCharIdx <= the number of elements of tChars then
      set the hilitedLine of field "CharList" of card "Studio" to sCharIdx
   else
      put 0 into sCharIdx
      St.CharShow empty
   end if
end St.FillChars

on St.CharPick pLine
   local tChars
   if pLine is empty then put the hilitedLine of field "CharList" of card "Studio" into pLine
   if pLine is empty or pLine < 1 then exit St.CharPick
   put pLine into sCharIdx
   set the hilitedLine of field "CharList" of card "Studio" to pLine
   put TTRPG.Chars() into tChars
   St.CharShow tChars[pLine]
end St.CharPick

on St.CharShow pA
   local k
   repeat for each item k in "name,look,voice,wants,secret"
      put pA[k] into field ("c_" & k) of card "Studio"
   end repeat
   set the hilite of button "Keep" of card "Studio" to (pA["keep"] is "true" or pA["kind"] is "constant")
   set the enabled of button "Keep" of card "Studio" to (pA["kind"] is not "constant")
end St.CharShow

on St.CharSave
   local tA, k
   if sCharIdx < 1 then
      St.Status "Click a character in the list first (or New)."
      exit St.CharSave
   end if
   repeat for each item k in "name,look,voice,wants,secret"
      put word 1 to -1 of field ("c_" & k) of card "Studio" into tA[k]
   end repeat
   if tA["name"] is empty then
      St.Status "A character needs a name."
      exit St.CharSave
   end if
   put (the hilite of button "Keep" of card "Studio") into tA["keep"]
   TTRPG.Char.Update sCharIdx, tA
   St.FillChars
   St.Status "Saved " & tA["name"] & "."
end St.CharSave

on St.CharNew
   put TTRPG.Char.New() into sCharIdx
   St.FillChars
   St.CharPick sCharIdx
   focus on field "c_name" of card "Studio"
end St.CharNew

on St.CharDelete
   local tChars, tC, tMsg
   if sCharIdx < 1 then exit St.CharDelete
   put TTRPG.Chars() into tChars
   put tChars[sCharIdx] into tC
   put "Delete " & tC["name"] & "?" into tMsg
   if tC["kind"] is "constant" then put return & "It is a constant character: its file goes too." after tMsg
   answer tMsg with "Cancel" or "Delete"
   if it is not "Delete" then exit St.CharDelete
   TTRPG.Char.Delete sCharIdx
   put 0 into sCharIdx
   St.FillChars
end St.CharDelete

-------------------------------------------------------------------- your character

constant kSkills = "Acrobatics,Animal Handling,Arcana,Athletics,Deception,History,Insight,Intimidation,Investigation,Medicine,Nature,Perception,Performance,Persuasion,Religion,Sleight of Hand,Stealth,Survival"

on St.FillPlayer
   local tP, tSkill
   put TTRPG.Player() into tP
   put tP["name"] into field "p_name" of card "Studio"
   put tP["look"] into field "p_look" of card "Studio"
   repeat for each item tSkill in kSkills
      put tP["skills"][tSkill] into field ("s_" & tSkill) of card "Studio"
   end repeat
end St.FillPlayer

on St.PlayerSave
   local tP, tSkill, v
   put TTRPG.Player() into tP
   if word 1 to -1 of field "p_name" of card "Studio" is not empty then put word 1 to -1 of field "p_name" of card "Studio" into tP["name"]
   put word 1 to -1 of field "p_look" of card "Studio" into tP["look"]
   repeat for each item tSkill in kSkills
      put word 1 to -1 of field ("s_" & tSkill) of card "Studio" into v
      if v is not an integer then put 0 into v
      put v into tP["skills"][tSkill]
   end repeat
   TTRPG.Character.Save tP
   St.FillPlayer
   St.Status "Your character is saved."
end St.PlayerSave

-------------------------------------------------------------------- pause (Escape)

constant kDevOptions = "max_dm,max_voice,max_referee,max_make,max_summary,temp_dm,temp_voice,keep_turns,summary_every"

on St.Pause
   local k
   if TTRPG.Busy() then
      TTRPG.Cancel
      St.Thinking false
      St.Log "note", empty, "(cancelled)"
   end if
   repeat for each item k in kDevOptions
      put TTRPG.Cfg.Get(k) into field ("o_" & k) of card "Studio"
   end repeat
   put TTRPG.LM.Get("ctx") into field "o_ctx" of card "Studio"
   set the visible of group "Pause" of card "Studio" to true
end St.Pause

on St.Resume
   local k, v
   repeat for each item k in kDevOptions
      put word 1 to -1 of field ("o_" & k) of card "Studio" into v
      if v is a number then TTRPG.Cfg.Set k, v
   end repeat
   put word 1 to -1 of field "o_ctx" of card "Studio" into v
   if v is an integer and v >= 512 then TTRPG.LM.Set "ctx", v
   set the visible of group "Pause" of card "Studio" to false
   focus on field "Input" of card "Studio"
end St.Resume

-------------------------------------------------------------------- the world (card "World", owner 23 Nov)

function St.World
   return sWorld
end St.World

function St.WorldCell
   return sWCell
end St.WorldCell

-- pName, pCols, pRows given (tests): no question asked
on St.WorldNew pName, pCols, pRows
   if not St.WorldMayDrop() then exit St.WorldNew
   if pName is empty then
      ask "New world: name, columns, rows (up to 24 x 24)" with "Example_01_World, 16, 16"
      if it is empty or the result is "Cancel" then exit St.WorldNew
      put word 1 to -1 of item 1 of it into pName
      put word 1 to -1 of item 2 of it into pCols
      put word 1 to -1 of item 3 of it into pRows
   end if
   if pCols is not an integer then put 16 into pCols
   if pRows is not an integer then put 16 into pRows
   put max(2, min(24, pCols)) into pCols
   put max(2, min(24, pRows)) into pRows
   lock screen
   put TTRPG.World.New(pName, pCols, pRows) into sWorld
   TTRPG.World.Spawn sWorld
   put the result into sWPlayer
   put sWorld["player"][sWPlayer]["location"] into sWCell
   put true into sWDirty
   St.WorldShow
   unlock screen
   St.Status "New world " & TTRPG.World.Words(sWorld["name"]) & ": " & pCols * pRows & " cells, " & \
         the number of lines of the keys of sWorld["npc"] & " people, " & the number of lines of the keys of sWorld["monsters"] & \
         " monsters. Save World keeps it."
end St.WorldNew

-- false = the user kept the unsaved world
function St.WorldMayDrop
   if sWDirty is not true then return true
   answer "The world has changes that are not saved." with "Cancel" or "Drop them" or "Save World"
   if it is "Cancel" then return false
   if it is "Save World" then St.WorldSave
   return true
end St.WorldMayDrop

on St.WorldLoad pPath
   local tW, tFolder
   if pPath is empty then
      if not St.WorldMayDrop() then exit St.WorldLoad
      put TTRPG.Path("worlds", "x.json") into tFolder
      set the itemDel to "/"
      delete item -1 of tFolder
      set the itemDel to comma
      answer file "Load a world" with tFolder
      if it is empty then exit St.WorldLoad
      put it into pPath
   end if
   put TTRPG.World.Load(pPath) into tW
   if tW["locations"] is not an array then
      St.Status "Not a world: " & pPath
      exit St.WorldLoad
   end if
   put tW into sWorld
   put line 1 of TTRPG.World.Ordered(the keys of sWorld["player"]) into sWPlayer
   if sWPlayer is empty then
      TTRPG.World.Spawn sWorld
      put the result into sWPlayer
   end if
   put sWorld["player"][sWPlayer]["location"] into sWCell
   put false into sWDirty
   St.WorldShow
   St.Status "Loaded " & TTRPG.World.Words(sWorld["name"]) & " (" & pPath & ")."
end St.WorldLoad

on St.WorldSave
   if sWorld is not an array then
      St.Status "No world yet: New World first."
      exit St.WorldSave
   end if
   TTRPG.World.Save sWorld
   put false into sWDirty
   St.Status "World saved: " & the result
end St.WorldSave

-- the whole card from sWorld and the chosen cell
on St.WorldShow
   local tCR, tKind
   if there is not a card "World" of me then exit St.WorldShow
   lock screen
   if sWorld is not an array then
      put "No world yet: New World or Load World." into field "WorldName" of card "World" of me
      put empty into field "Map" of card "World" of me
      put empty into field "CellData" of card "World" of me
      put empty into field "HereList" of card "World" of me
      put empty into field "HereLore" of card "World" of me
      put empty into sHereKeys
      St.WorldWords
      unlock screen
      exit St.WorldShow
   end if
   put TTRPG.World.CellOf(sWCell) into tCR
   put TTRPG.World.Words(sWorld["locations"][sWCell]["kind"]) into tKind
   put TTRPG.World.Words(sWorld["name"]) & " (" & sWorld["cols"] & " x " & sWorld["rows"] & ")" into field "WorldName" of card "World" of me
   put "This cell: " & tKind & " (column " & item 1 of tCR & ", row " & item 2 of tCR & ")" into field "CellLabel" of card "World" of me
   St.MapDraw
   put TTRPG.World.CellData(sWorld, sWCell) into field "CellData" of card "World" of me
   St.HereFill
   St.WorldWords
   unlock screen
end St.WorldShow

-- the map as text: @ in the accent colour, the chosen cell on a light ground
on St.MapDraw
   local tLines, tHTML, r, c, tRow, tM, tCR
   put TTRPG.World.MapLines(sWorld, sWPlayer) into tLines
   put TTRPG.World.CellOf(sWCell) into tCR
   repeat with r = 1 to the number of lines of tLines
      put "<p>" after tHTML
      put line r of tLines into tRow
      repeat with c = 1 to sWorld["cols"]
         put char (c * 2 - 1) of tRow into tM
         if tM is space then put "&nbsp;" into tM
         if tM is "@" then put "<font color=" & quote & "#ffd75a" & quote & "><b>@</b></font>" into tM
         if tM is "&" then put "&amp;" into tM
         if (c & comma & r) is tCR then put "<font bgcolor=" & quote & "#46466e" & quote & ">" & tM & "</font>" into tM
         put tM after tHTML
         if c < sWorld["cols"] then put "&nbsp;" after tHTML
      end repeat
      put "</p>" after tHTML
   end repeat
   set the htmlText of field "Map" of card "World" of me to tHTML
end St.MapDraw

-- the map field's mouseUp: which cell (one mark a cell, a space between)
on St.MapClicked
   local tIdx, tRowLen, tPos
   if sWorld is not an array then exit St.MapClicked
   put word 2 of the clickCharChunk into tIdx
   if tIdx is not an integer then exit St.MapClicked
   put sWorld["cols"] * 2 into tRowLen
   put (tIdx - 1) mod tRowLen + 1 into tPos
   St.MapClick (tPos + 1) div 2, (tIdx - 1) div tRowLen + 1, the shiftKey is down
end St.MapClicked

-- a cell next to @ = walk there (unless pJustLook); any other cell = see and edit it
on St.MapClick pCol, pRow, pJustLook
   local tLoc, tYou, tWay, tReply, tPlayer
   put TTRPG.World.CellAt(sWorld, pCol, pRow) into tLoc
   if tLoc is empty then exit St.MapClick
   put TTRPG.World.CellOf(sWorld["player"][sWPlayer]["location"]) into tYou
   if pJustLook is not true then
      if pCol is item 1 of tYou and pRow is item 2 of tYou - 1 then put "north" into tWay
      if pCol is item 1 of tYou and pRow is item 2 of tYou + 1 then put "south" into tWay
      if pRow is item 2 of tYou and pCol is item 1 of tYou + 1 then put "east" into tWay
      if pRow is item 2 of tYou and pCol is item 1 of tYou - 1 then put "west" into tWay
   end if
   if tWay is not empty then
      TTRPG.World.Act sWorld, sWPlayer, "go " & tWay
      put the result into tReply
      put TTRPG.Player() into tPlayer
      St.Log "player", tPlayer["name"], "go " & tWay
      St.Log "world", empty, tReply
      put true into sWDirty
      St.Status "You go " & tWay & "."
   end if
   put tLoc into sWCell
   St.WorldShow
end St.MapClick

-- Apply: the edited lines into the cell. Lines not understood: asked first (pForce skips the question)
on St.CellApply pForce
   local tText, tCopy, tBad
   if sWorld is not an array then exit St.CellApply
   put field "CellData" of card "World" of me into tText
   put sWorld into tCopy
   TTRPG.World.SetCellData tCopy, sWCell, tText
   put the result into tBad
   if tBad is not empty and pForce is not true then
      answer "These lines are not understood and would be left out:" & return & tBad with "Cancel" or "Apply the rest"
      if it is not "Apply the rest" then exit St.CellApply
   end if
   put tCopy into sWorld
   put true into sWDirty
   St.WorldShow
   if tBad is empty then St.Status "Cell changed."
   else St.Status "Cell changed; left out: " & line 1 of tBad
end St.CellApply

-- the people and monsters on the chosen cell
on St.HereFill
   local tK, tList
   put empty into sHereKeys
   put 0 into sHereIdx
   repeat for each line tK in TTRPG.World.Here(sWorld, sWCell, "npc")
      put TTRPG.World.Words(sWorld["npc"][tK]["role"]) & "  (person)" & return after tList
      put "npc" & tab & tK & return after sHereKeys
   end repeat
   repeat for each line tK in TTRPG.World.Here(sWorld, sWCell, "monsters")
      put TTRPG.World.Words(sWorld["monsters"][tK]["kind"]) & "  (monster)" & return after tList
      put "monsters" & tab & tK & return after sHereKeys
   end repeat
   delete the last char of tList
   delete the last char of sHereKeys
   if tList is empty then put "Nobody here." into tList
   put tList into field "HereList" of card "World" of me
   put empty into field "HereLore" of card "World" of me
end St.HereFill

on St.HerePick pLine
   local tKind, tK, tA, tOut, tAt
   if pLine is empty then put the hilitedLine of field "HereList" of card "World" of me into pLine
   if pLine is not an integer or pLine < 1 or pLine > the number of lines of sHereKeys then exit St.HerePick
   put pLine into sHereIdx
   set the hilitedLine of field "HereList" of card "World" of me to pLine
   set the itemDel to tab
   put item 1 of line pLine of sHereKeys into tKind
   put item 2 of line pLine of sHereKeys into tK
   set the itemDel to comma
   put sWorld[tKind][tK] into tA
   if tKind is "npc" then
      put TTRPG.World.Words(tA["role"]) into tOut
      if tA["lore"] is not empty then
         put return & tA["lore"] after tOut
      end if
   else
      put TTRPG.World.Words(tA["kind"]) into tOut
   end if
   put empty into tAt
   repeat for each item tK in "Strength,Constitution,Dexterity,Intelligence,Wisdom,Charisma,AC,HP"
      if tA["attributes"][tK] is not empty then put tK & " " & tA["attributes"][tK] & ", " after tAt
   end repeat
   if tAt is not empty then put return & return & char 1 to -3 of tAt after tOut
   put tOut into field "HereLore" of card "World" of me
end St.HerePick

-- Add as character: by hand (name = role, look = lore) or the DM model makes one from role and lore.
-- pHow "hand" / "model" (tests) skips the question
on St.HereAdd pHow
   local tLine, tKind, tK, tAsk, tIdx, tA
   put sHereIdx into tLine
   if tLine is not an integer or tLine < 1 or tLine > the number of lines of sHereKeys then
      St.Status "Click someone in Here first."
      exit St.HereAdd
   end if
   set the itemDel to tab
   put item 1 of line tLine of sHereKeys into tKind
   put item 2 of line tLine of sHereKeys into tK
   set the itemDel to comma
   if tKind is "npc" then
      put TTRPG.World.CharacterAsk(sWorld, tK) into tAsk
      put TTRPG.World.Words(sWorld["npc"][tK]["role"]) into tA["name"]
      put sWorld["npc"][tK]["lore"] into tA["look"]
   else
      put TTRPG.World.Words(sWorld["monsters"][tK]["kind"]) into tAsk
      put tAsk into tA["name"]
   end if
   if pHow is empty then
      answer "Add " & tA["name"] & " as a character:" with "Cancel" or "By hand" or "Ask the DM model"
      if it is "By hand" then put "hand" into pHow
      if it is "Ask the DM model" then put "model" into pHow
   end if
   if pHow is "hand" then
      put TTRPG.Char.New() into tIdx
      TTRPG.Char.Update tIdx, tA
      go card "Studio"
      St.FillChars
      St.CharPick tIdx
      St.Status tA["name"] & " is a character now: edit it on the right."
   else if pHow is "model" then
      if not St.Ready() then exit St.HereAdd
      go card "Studio"
      St.Log "note", empty, "a character is being made: " & tAsk
      St.Thinking true
      TTRPG.Character.Make tAsk
   end if
end St.HereAdd

-- Scene here: a New Scene from where you stand (@)
on St.SceneHere
   if sWorld is not an array then
      St.Status "No world yet: New World first."
      exit St.SceneHere
   end if
   if not St.Ready() then exit St.SceneHere
   go card "Studio"
   St.NewScene TTRPG.World.SceneIdea(sWorld, sWPlayer)
end St.SceneHere

-- Verbose on: the DM model words the chosen cell (only what can be seen); remembered while the cell stays the same
on St.WorldWords
   local tOn, tKey
   if there is not a card "World" of me then exit St.WorldWords
   put the hilite of button "Verbose" of card "World" of me into tOn
   set the visible of field "WordsLabel" of card "World" of me to tOn
   set the visible of field "CellWords" of card "World" of me to tOn
   if not tOn or sWorld is not an array then exit St.WorldWords
   put TTRPG.World.TilePrompt(sWorld, sWCell) into tKey
   if sWords[tKey] is not empty then
      put sWords[tKey] into field "CellWords" of card "World" of me
      exit St.WorldWords
   end if
   if TTRPG.LM.DM() is empty then
      put "Load a model first (Studio card, left) and the DM puts this cell into words." into field "CellWords" of card "World" of me
      exit St.WorldWords
   end if
   if TTRPG.Busy() or TTRPG.LM.Busy() then
      put "The model is busy; click the cell again in a moment." into field "CellWords" of card "World" of me
      exit St.WorldWords
   end if
   put "thinking..." into field "CellWords" of card "World" of me
   put tKey into sWordsKey
   put sWCell into sWordsLoc
   TTRPG.World.Describe sWorld, sWCell, the long id of me, "St.OnWorldWords"
   if the result is not empty then put "The model did not take it: " & the result into field "CellWords" of card "World" of me
end St.WorldWords

on St.OnWorldWords pText, pErr
   if pErr is not empty then
      put "model error: " & pErr into field "CellWords" of card "World" of me
      exit St.OnWorldWords
   end if
   put TTRPG.CleanNarration(pText, 7) into pText
   put pText into sWords[sWordsKey]
   if sWCell is sWordsLoc then put pText into field "CellWords" of card "World" of me
end St.OnWorldWords
