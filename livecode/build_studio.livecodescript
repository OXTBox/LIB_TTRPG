script "build_studio"
######################################################################################
## build_studio (LIB_TTRPG, iteration 1, 15 Nov 2026): makes TTRPG_Studio.livecode from scratch.
##   start using stack ".../LIB_TTRPG/livecode/build_studio.livecodescript"
##   Build.Studio ".../LIB_TTRPG"          -> saves .../LIB_TTRPG/TTRPG_Studio.livecode, returns its path
## The stack script is studio_stack.livecodescript; edit that, then build again. Copies of the
## two libraries and LIB_DATA go in as substacks, and the prompts as the custom property set
## "Prompts", so the stack still works when moved (it prefers the files when it finds them).
## Modelled on LIB_BIT/editor/livecode/build_editor.livecodescript; LIB_THEME colours it.
######################################################################################

constant kW = 1280
constant kH = 720
constant kSkills = "Acrobatics,Animal Handling,Arcana,Athletics,Deception,History,Insight,Intimidation,Investigation,Medicine,Nature,Perception,Performance,Persuasion,Religion,Sleight of Hand,Stealth,Survival"
-- the skill buttons' short labels, same order
constant kSkillShort = "Acrobatics,Animals,Arcana,Athletics,Deception,History,Insight,Intimidate,Investigate,Medicine,Nature,Perception,Perform,Persuasion,Religion,Sleight,Stealth,Survival"
constant kDevOptions = "max_dm,max_voice,max_referee,max_make,max_summary,temp_dm,temp_voice,keep_turns,summary_every,ctx"
constant kDevLabels = "Max tokens: narrator,Max tokens: voices,Max tokens: referee,Max tokens: scene / character maker,Max tokens: summary,Temperature: narrator,Temperature: voices,Turns kept word for word,Fold the summary every N turns,Context length (at Load)"

command Build.Studio pDir
   local tS, tPath, tErr, tName, x, y, i, tA, tFiles, tF, tOld, tScript
   put "TTRPG_Studio" into tS
   if there is a stack tS then delete stack tS
   Build.UseTheme pDir
   Theme.Begin
   create invisible stack tS
   set the rect of stack tS to 40, 40, 40 + kW, 40 + kH
   set the title of stack tS to "FOR OWNER | New Scene, type an idea, then type what you do"
   dispatch "Users.TitleStack" with tS, "New Scene, type an idea, then type what you do"   -- LIB_USERS words it, when in use
   set the textSize of stack tS to 12
   set the resizable of stack tS to false
   set the defaultStack to tS
   set the name of card 1 of stack tS to "About"
   Build.About tS, pDir
   create card "Studio"

   ---------------------------------------------------------------- top: the buttons
   put 8 into x
   repeat for each item tName in "NewScene,AddCharacter,Regenerate,Notes,EndScene,About"
      create button tName
      set the rect of it to x, 6, x + 112, 30
      add 118 to x
      Build.Click it, tName
   end repeat
   set the label of button "NewScene" to "New Scene"
   set the label of button "AddCharacter" to "Add Character"
   set the label of button "Regenerate" to "Regenerate"
   set the tooltip of button "Regenerate" to "Same roll, same clue, new words (Ctrl+R)"
   set the label of button "Notes" to "DM Notes"
   set the tooltip of button "Notes" to "The DM's hidden notes: the truth, the clues, the summary"
   set the label of button "EndScene" to "End Scene"
   set the label of button "About" to "About"
   Build.Label "Hint", "Esc: pause, cancel a call, developer options.   Ctrl+R: regenerate.", 728, 8, 1272, 28

   ---------------------------------------------------------------- left: the models
   Build.Label "ModelsLabel", "Models", 8, 40, 268, 60
   set the textStyle of field "ModelsLabel" to "bold"
   Build.Label "DMLabel", "DM", 8, 66, 54, 88
   create button "DMMenu"
   set the style of it to "menu"
   set the menuMode of it to "option"
   set the rect of it to 56, 64, 268, 88
   set the tooltip of it to "The narrator, referee, scene maker and summary"
   Build.Label "VoicesLabel", "Voices", 8, 96, 54, 118
   create button "VoicesMenu"
   set the style of it to "menu"
   set the menuMode of it to "option"
   set the rect of it to 56, 94, 268, 118
   set the text of it to "Same as DM"
   set the label of it to "Same as DM"
   set the tooltip of it to "The characters' voices; Same as DM = one model plays everything"
   put 8 into x
   repeat for each item tName in "Refresh,Load,Unload"
      create button tName
      set the rect of it to x, 126, x + 82, 150
      add 88 to x
      Build.Click it, tName
   end repeat
   create field "ModelStatus"
   set the rect of it to 8, 158, 268, 300
   set the lockText of it to true
   set the dontWrap of it to false
   create field "LibsNote"
   set the rect of it to 8, 310, 268, 684
   set the lockText of it to true
   set the textSize of it to 11
   put "How a turn works" & return & \
         "You type what your character does. A referee sorts it (talk, look, do); the program decides what " & \
         "happens and rolls the die; the narrator only puts it into words. A character you talk to answers " & \
         "in its own voice." & return & return & \
         "Clues come one at a time, only when you look, and are shown word for word after the narration " & \
         "(the narrator never sees a clue before you find it)." & return & return & \
         "Name a skill (the buttons over the input box): it finds the clue that needs it, or a new lead; " & \
         "Insight, Persuasion, Deception or Intimidation on a character presses for its secret." & return & return & \
         "Regenerate keeps the roll and the clue: only the words change." & return & return & \
         "DM Notes shows the hidden truth and the clues: it is your game, you may peek." & return & return & \
         "Characters: click one to edit it. Tick Keep after scene, then End Scene, and it joins every new scene." into field "LibsNote"

   ---------------------------------------------------------------- middle: scene, log, input
   create field "SceneText"
   set the rect of it to 280, 40, 900, 170
   set the lockText of it to true
   set the vScrollbar of it to true
   create field "Log"
   set the rect of it to 280, 178, 900, 560
   set the lockText of it to true
   set the vScrollbar of it to true
   set the textSize of it to 13
   create field "Notes"
   set the rect of it to 280, 178, 900, 560
   set the lockText of it to true
   set the vScrollbar of it to true
   set the visible of it to false
   create field "Input"
   set the rect of it to 280, 620, 900, 656
   set the textSize of it to 13
   set the script of it to "on returnInField" & return & "St.Send" & return & "end returnInField" & return & \
         "on enterInField" & return & "St.Send" & return & "end enterInField"
   create field "Thinking"
   set the rect of it to 280, 660, 600, 684
   set the lockText of it to true
   put "thinking..." into field "Thinking"
   set the visible of it to false
   -- the skill buttons: a click starts the line with "I use <skill>: " (owner, 15 Nov: naming a skill moves the plot)
   put 0 into i
   repeat for each item tName in kSkills
      put 280 + (i mod 9) * 69 into x
      put 566 + (i div 9) * 24 into y
      create button ("skill_" & tName)
      set the label of it to item (i + 1) of kSkillShort
      set the rect of it to x, y, x + 66, y + 22
      set the textSize of it to 10
      set the tooltip of it to "I use " & tName & ": ... (your bonus is on the sheet, right)"
      Build.Click it, "Skill:" & tName
      add 1 to i
   end repeat
   Build.Pause

   ---------------------------------------------------------------- right: characters, your character
   Build.Label "CharsLabel", "Characters (click to edit)", 912, 40, 1272, 60
   set the textStyle of field "CharsLabel" to "bold"
   create field "CharList"
   set the rect of it to 912, 62, 1272, 190
   set the listBehavior of it to true
   set the lockText of it to true
   set the dontWrap of it to true
   set the vScrollbar of it to true
   set the script of it to "on mouseUp" & return & "St.CharPick" & return & "end mouseUp"
   create button "CharNew"
   set the label of it to "New"
   set the rect of it to 912, 196, 990, 218
   Build.Click it, "CharNew"
   create button "CharDelete"
   set the label of it to "Delete"
   set the rect of it to 996, 196, 1074, 218
   Build.Click it, "CharDelete"
   put 226 into y
   repeat for each item tName in "name,look,voice,wants,secret"
      Build.Label "l_" & tName, toUpper(char 1 of tName) & char 2 to -1 of tName, 912, y + 2, 966, y + 22
      create field ("c_" & tName)
      set the rect of it to 968, y, 1272, y + 24
      set the dontWrap of it to true
      add 28 to y
   end repeat
   set the tooltip of field "c_voice" to "how they speak"
   set the tooltip of field "c_wants" to "what they want right now"
   set the tooltip of field "c_secret" to "what they hide (only their own voice ever sees it)"
   create button "Keep"
   set the style of it to "checkbox"
   set the label of it to "Keep after scene"
   set the rect of it to 912, 368, 1100, 390
   set the tooltip of it to "End Scene saves it as a constant character, in every new scene"
   create button "CharSave"
   set the label of it to "Save"
   set the rect of it to 1180, 368, 1272, 390
   Build.Click it, "CharSave"
   Build.Label "PlayerLabel", "Your character", 912, 406, 1272, 426
   set the textStyle of field "PlayerLabel" to "bold"
   Build.Label "l_pname", "Name", 912, 432, 966, 452
   create field "p_name"
   set the rect of it to 968, 430, 1272, 454
   set the dontWrap of it to true
   Build.Label "l_plook", "Look", 912, 460, 966, 480
   create field "p_look"
   set the rect of it to 968, 458, 1272, 482
   set the dontWrap of it to true
   put 0 into i
   repeat for each item tName in kSkills
      put 912 + (i mod 3) * 121 into x
      put 490 + (i div 3) * 26 into y
      Build.Label "l_" & tName, tName, x, y + 3, x + 86, y + 21
      set the textSize of field ("l_" & tName) to 10
      create field ("s_" & tName)
      set the rect of it to x + 86, y, x + 118, y + 22
      set the dontWrap of it to true
      set the tooltip of it to tName & ": bonus added to the d20 roll"
      add 1 to i
   end repeat
   create button "PlayerSave"
   set the label of it to "Save"
   set the rect of it to 1180, 652, 1272, 674
   Build.Click it, "PlayerSave"

   create field "Status"
   set the rect of it to 8, 692, kW - 8, 714
   set the lockText of it to true
   set the dontWrap of it to true

   ---------------------------------------------------------------- colours, then the pieces that make it work anywhere
   Theme.ApplyStack tS
   repeat for each item tName in "Hint,ModelsLabel,DMLabel,VoicesLabel,CharsLabel,PlayerLabel,Thinking,LibsNote,l_pname,l_plook"
      if there is a field tName of card "Studio" of stack tS then
         set the opaque of field tName of card "Studio" of stack tS to false
         set the showBorder of field tName of card "Studio" of stack tS to false
      end if
   end repeat
   set the foregroundColor of field "Thinking" of card "Studio" of stack tS to Theme.Get("accent")
   repeat for each item tName in kSkills
      set the opaque of field ("l_" & tName) of card "Studio" of stack tS to false
      set the showBorder of field ("l_" & tName) of card "Studio" of stack tS to false
   end repeat
   Theme.End
   -- the library copies (used only when the files are not found next to the stack)
   Build.Substack tS, "TTRPG_Studio_lm", pDir & "/livecode/lib_ttrpg_lm.livecodescript"
   put the result into tErr
   Build.Substack tS, "TTRPG_Studio_engine", pDir & "/livecode/lib_ttrpg.livecodescript"
   put the result after tErr
   set the itemDel to "/"
   put item 1 to -2 of pDir & "/LIB_DATA/livecode/lib_data.livecodescript" into tF
   set the itemDel to comma
   Build.Substack tS, "TTRPG_Studio_data", tF
   put the result after tErr
   if tErr is not empty then
      delete stack tS
      return tErr
   end if
   -- the prompts, as the custom property set "Prompts"
   put the defaultFolder into tOld
   set the defaultFolder to pDir & "/prompts"
   put the files into tFiles
   set the defaultFolder to tOld
   repeat for each line tF in tFiles
      if tF ends with ".txt" then put word 1 to -1 of Build.ReadText(pDir & "/prompts/" & tF) into tA[char 1 to -5 of tF]
   end repeat
   set the customPropertySet of stack tS to "Prompts"
   set the customProperties of stack tS to tA
   set the customPropertySet of stack tS to empty
   -- If the stack script does not compile, nothing is saved (a stack without its handlers
   -- throws an error at every click).
   set the script of stack tS to Build.ReadText(pDir & "/livecode/studio_stack.livecodescript")
   put the result into tErr
   if tErr is not empty then
      delete stack tS
      return "ERROR: studio_stack does not compile:" && line 1 of tErr
   end if
   set the destroyStack of stack tS to true
   put pDir & "/TTRPG_Studio.livecode" into tPath
   set the fileName of stack tS to tPath
   save stack tS
   return tPath
end Build.Studio

-- a substack holding a copy of a library's script (its first line, script "...", left out)
command Build.Substack pStack, pName, pFile
   local tScript
   if there is not a file pFile then return "ERROR: not found " & pFile
   put Build.ReadText(pFile) into tScript
   if line 1 of tScript begins with "script " then delete line 1 of tScript
   create invisible stack pName
   set the mainStack of stack pName to pStack
   set the script of stack pName to tScript
   if the result is not empty then return "ERROR: " & pFile & " does not compile: " & line 1 of the result
   set the defaultStack to pStack
   return empty
end Build.Substack

command Build.Click pObj, pName
   set the script of pObj to "on mouseUp" & return & "St.Click " & quote & pName & quote & return & "end mouseUp"
end Build.Click

command Build.Label pName, pText, pL, pT, pR, pB
   create field pName
   set the rect of it to pL, pT, pR, pB
   set the lockText of it to true
   set the dontWrap of it to true
   put pText into field pName
end Build.Label

-- Escape's panel: developer options, over the log (rule 18)
command Build.Pause
   local i, tName, y
   reset the templateGroup
   create group "Pause"
   set the margins of group "Pause" to 0
   create graphic "PauseBack" in group "Pause"
   set the style of it to "rectangle"
   set the filled of it to true
   set the opaque of it to true
   set the backgroundColor of it to "28,28,34"
   set the foregroundColor of it to Theme.Get("accent")
   set the uThemeSkip of it to true
   set the rect of it to 280, 178, 900, 612
   create field "PauseTitle" in group "Pause"
   set the rect of it to 296, 186, 884, 230
   set the lockText of it to true
   put "PAUSED. Esc again (or Resume) goes back to play." & return & "Developer options: they change the next call." into field "PauseTitle"
   put 240 into y
   put 0 into i
   repeat for each item tName in kDevOptions
      add 1 to i
      create field ("ol_" & tName) in group "Pause"
      set the rect of it to 296, y + 2, 600, y + 24
      set the lockText of it to true
      set the dontWrap of it to true
      put item i of kDevLabels into field ("ol_" & tName)
      create field ("o_" & tName) in group "Pause"
      set the rect of it to 610, y, 700, y + 26
      set the dontWrap of it to true
      add 32 to y
   end repeat
   create button "Resume" in group "Pause"
   set the rect of it to 610, y + 8, 700, y + 32
   Build.Click it, "Resume"
   set the visible of group "Pause" to false
end Build.Pause

-- card 1 (rule 17): long date, stack name, title, what for, how, how to report
command Build.About pStack, pDir
   local tText
   put "Sunday, November 15, 2026" & return & \
         "Stack: TTRPG_Studio" & return & \
         "Title: FOR OWNER | New Scene, type an idea, then type what you do" & return & return & \
         "WHAT IT IS FOR" & return & \
         "A small role-playing table run by local models in LM Studio. You pick one or two light models, give a " & \
         "one-line scene idea, and play by typing what your character does. The narrator plays a Lazy DM: a short " & \
         "opening, then one clue at a time, only when you look. Iteration 1 of LIB_TTRPG; later the talking back end " & \
         "of PROMPT & GLAZE." & return & return & \
         "HOW" & return & \
         "- Esc or the Start button below: go to the studio." & return & \
         "- Left: pick a DM model (and Voices, or Same as DM), press Load. Unload, or closing the window, unloads " & \
         "what this stack loaded (never a model that was already loaded)." & return & \
         "- New Scene: type a one-line idea. Wait for the opening (a few seconds)." & return & \
         "- Type what you do in the box under the log; Return sends. Say a character's name, or use quotes, to talk to them." & return & \
         "- Name a skill to move the story: click a skill button over the box (it starts your line with " & quote & "I use Medicine: " & quote & "), " & \
         "or type it. A named skill finds the clue that needs it, wherever you are; when none is left it turns up a new lead." & return & \
         "- Ctrl+R (or Regenerate): the last answer again in other words. Same roll, same clue." & return & \
         "- Add Character: by hand, or a one-line ask to the model. Click a character to edit it; Keep after scene " & \
         "+ End Scene keeps it for every new scene." & return & \
         "- DM Notes: peek at the truth and the clues." & return & \
         "- Esc while playing: pause; cancels a running call; developer options (token limits, temperatures, " & \
         "turns kept, summary pace, context length)." & return & return & \
         "HOW TO REPORT" & return & \
         "Was it fun? Did the DM give one clue at a time? Did characters answer in their own voices? Write notes in " & \
         "LIB_LLMIN/LIB_TTRPG/ (any text file) or with the review browser's Tell Claude. Every model call is logged " & \
         "(Data folder: Work/Logs/TTRPG/<date>_session.jsonl) and every scene saved (Games/TTRPG/scenes/): " & \
         "Claude reads those; nothing is watching live." into tText
   create field "AboutText"
   set the rect of it to 40, 30, kW - 40, kH - 70
   set the lockText of it to true
   set the textSize of it to 14
   set the vScrollbar of it to true
   put tText into field "AboutText"
   set the textStyle of line 1 to 3 of field "AboutText" to "bold"
   create button "Start"
   set the label of it to "Start"
   set the rect of it to kW - 160, kH - 54, kW - 40, kH - 24
   Build.Click it, "Start"
end Build.About

command Build.UseTheme pDir
   local tLib
   set the itemDel to "/"
   put item 1 to -2 of pDir & "/LIB_THEME/livecode/lib_theme.livecodescript" into tLib
   set the itemDel to comma
   if there is not a file tLib then
      answer "LIB_THEME not found: " & tLib
      exit to top
   end if
   start using stack tLib
   Theme.Use "dark"
end Build.UseTheme

function Build.ReadText pPath
   return textDecode(URL ("binfile:" & pPath), "UTF-8")
end Build.ReadText
