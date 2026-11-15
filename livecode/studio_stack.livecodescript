######################################################################################
## STACK SCRIPT: "TTRPG_Studio" (LIB_TTRPG, iteration 1, 15 Nov 2026)
## UI handlers only: the engine is lib_ttrpg, the model calls lib_ttrpg_lm. Built by
## build_studio.livecodescript; this text is the stack script it sets.
## Card 1 "About" (rule 17), card 2 "Studio":
##   LEFT    Models: DM and Voices option menus (Voices starts on "Same as DM"),
##           Refresh / Load / Unload, one status line.
##   MIDDLE  the Scene (title + opening), the chat log, the input (Return sends), "thinking...".
##   RIGHT   Characters (click = edit; New, Delete, Keep after scene, Save), your character's sheet.
##   TOP     New Scene, Add Character, Regenerate (Ctrl+R), DM Notes, End Scene, About.
##   Escape  pauses (rule 18): cancels a running call and shows the developer options.
## The libraries are found next to the stack (livecode/, or ../LIB_TTRPG/livecode/ from LIB_TEST);
## if not, the copies the builder put in as substacks are used. Same for the prompts.
######################################################################################

local sDir, sCharIdx, sEscAt, sLogHTML, sLibs

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
   if TTRPG.Busy() then
      St.Status "Still thinking. Esc cancels."
      return false
   end if
   return true
end St.Ready

-------------------------------------------------------------------- play

on St.NewScene
   local tIdea
   if not St.Ready() then exit St.NewScene
   ask "One line: what is the scene?" with "a flooded crypt under a chapel"
   if it is empty or the result is "Cancel" then exit St.NewScene
   put it into tIdea
   put empty into sLogHTML
   set the visible of field "Notes" of card "Studio" to false
   put "Making the scene: " & tIdea into field "SceneText" of card "Studio"
   St.Log "note", empty, "making the scene (" & TTRPG.LM.DM() & ")..."
   St.Thinking true
   TTRPG.Scene.New tIdea
end St.NewScene

on St.Send
   local tLine, tScene, tPlayer
   put word 1 to -1 of field "Input" of card "Studio" into tLine
   if tLine is empty then exit St.Send
   if not St.Ready() then exit St.Send
   put TTRPG.Scene() into tScene
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
   local tP
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

constant kSkills = "Perception,Investigation,Arcana,History,Insight,Athletics,Stealth,Persuasion"

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
