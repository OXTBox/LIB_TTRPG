-- client_main.livecodescript: the stack script of TTRPG_Client (the player's window).
-- SOURCE OF TRUTH: edit this file, never only the stack. Dev.NewVersion (LIB_DEV/tools/xtalk/dev_version.livecodescript)
-- puts it into each new TTRPG_Client_dev_<stamp> stack. Written by Opus via the xTalk MCP Bridge, 15 Nov 2026.
-- Party data: the custom property cPartyText of this stack, one [Name] section a player
-- (look=, color=r,g,b, dex=+n, skills=, weapons=, items=, spells= with | between entries,
-- magic= and injured= as part:what|part:what for the stick figure (parts: head, body, left arm, right arm,
-- left leg, right leg), then face= and 16 rows of 0/1).
-- Who acts (owner, 15 Nov): the scene mode decides. explore = the player's choice (click a face in the party
-- strip); combat = d20 + Dexterity initiative; talk = d20 + the better of Persuasion and Deception.
-- The engine (the Studio) will set the mode; until then /mode combat|talk|explore.
-- Commands typed in Player Input: /llm text (to Claude, saved in OXT-BEYOND/sessions/llm_inbox.txt),
-- /x xtalk, /mode, /dm text (puts text in the DM field), /clear (saves the log, then clears it), /help.
-- Never name this stack in code (its name changes every version): use this stack.
constant kSessions = "//wsl$/Ubuntu/home/igame3d/projects/OXT-BEYOND/sessions/"
local sParty, sCount, sTurn, sKind, sMode, sOrder, sOrderPos, sRound

on openStack
   Client.Init
end openStack

on closeStackRequest
   Client.SaveLog
   set the destroyStack of this stack to true
   pass closeStackRequest
end closeStackRequest

command Client.Init
   Client.LoadParty
   put 1 into sTurn
   put "Skills" into sKind
   lock messages   -- menuHistory would send menuPick
   set the menuHistory of button "ListTabs" of this stack to 1
   unlock messages
   put "explore" into sMode
   put empty into sOrder
   Client.DrawParty
   Client.ShowPlayer
end Client.Init

-- a click on a face (or a name) in the party strip: in explore mode, that player acts next
on mouseUp pButton
   local tName
   put the short name of the target into tName
   if tName begins with "Face_" or tName begins with "FaceName_" then
      set the itemDelimiter to "_"
      Client.ChooseActor item 2 of tName
   end if
   pass mouseUp
end mouseUp

command Client.ChooseActor pIndex
   if pIndex is not an integer or pIndex < 1 or pIndex > sCount then exit Client.ChooseActor
   if sMode is not "explore" then
      Client.Log "(In " & sMode & " the rolled order decides who acts; Next Turn follows it.)"
      exit Client.ChooseActor
   end if
   put pIndex into sTurn
   Client.Log "-- " & sParty[sTurn]["name"] & " acts --"
   Client.ShowPlayer
end Client.ChooseActor

-- explore | combat | talk: combat and talk roll the order (d20 + bonus), explore leaves it to the player
command Client.SetMode pMode
   local i, tRolls, tLine, tBonus, tList, tWhat
   if pMode is not among the items of "explore,combat,talk" then
      Client.Log "Modes: explore (click a face to choose who acts), combat (d20 + Dexterity), talk (d20 + Persuasion or Deception)"
      exit Client.SetMode
   end if
   put pMode into sMode
   put empty into sOrder
   put 1 into sRound
   if pMode is "explore" then
      Client.Log "-- Exploring: click a face to choose who acts --"
   else
      repeat with i = 1 to sCount
         if pMode is "combat" then
            put Client.Bonus(i, "dex") into tBonus
         else
            put max(Client.Bonus(i, "Persuasion"), Client.Bonus(i, "Deception")) into tBonus
         end if
         put (random(20) + tBonus) & comma & i & return after tRolls
      end repeat
      sort lines of tRolls descending numeric by item 1 of each
      repeat for each line tLine in tRolls
         put item 2 of tLine & comma after sOrder
         put sParty[item 2 of tLine]["name"] && item 1 of tLine & ", " after tList
      end repeat
      delete char -1 of sOrder
      delete char -2 to -1 of tList
      if pMode is "combat" then
         put "Combat! Initiative (d20 + Dexterity): " into tWhat
      else
         put "Talk. Order (d20 + Persuasion or Deception): " into tWhat
      end if
      Client.Log "-- " & tWhat & tList & " --"
      put 1 into sOrderPos
      put item 1 of sOrder into sTurn
      Client.Log "-- " & sParty[sTurn]["name"] & "'s turn --"
   end if
   Client.ShowPlayer
end Client.SetMode

-- a player's bonus: "dex" (the dex= line) or a skill's (+n after its name in skills=); 0 when none
function Client.Bonus pPlayer, pWhat
   local tItem
   if pWhat is "dex" then
      if sParty[pPlayer]["dex"] is a number then return sParty[pPlayer]["dex"] + 0
      return 0
   end if
   set the itemDelimiter to "|"
   repeat for each item tItem in sParty[pPlayer]["skills"]
      if word 1 to -2 of tItem is pWhat and word -1 of tItem is a number then return word -1 of tItem + 0
   end repeat
   return 0
end Client.Bonus

-- what a part of the body carries: the text after "part:" in magic= or injured=, empty when nothing
function Client.PartNote pPlayer, pKey, pPart
   local tItem
   set the itemDelimiter to "|"
   repeat for each item tItem in sParty[pPlayer][pKey]
      if tItem begins with pPart & ":" then return char (the number of chars of pPart) + 2 to -1 of tItem
   end repeat
   return empty
end Client.PartNote

-- the stick figure of whoever acts (in place of the big portrait, owner 15 Nov): grey, purple where a
-- magic item is worn, red where injured, pink for both; the tooltip of a part says what is there
command Client.DrawFigure
   local tParts, tPart, tName, tMagic, tHurt, tColor, tTip, i
   put "head|oval|40,98,64,122" & return & "body|line|52,122 52,170" & return & \
         "left arm|line|52,132 30,160" & return & "right arm|line|52,132 74,160" & return & \
         "left leg|line|52,170 34,214" & return & "right leg|line|52,170 70,214" into tParts
   set the defaultStack to the short name of this stack
   lock screen
   lock messages
   repeat with i = the number of controls of this card down to 1
      if the short name of control i of this card begins with "Fig_" then delete control i of this card
   end repeat
   set the itemDelimiter to "|"
   repeat for each line tPart in tParts
      put "Fig_" & item 1 of tPart into tName
      put Client.PartNote(sTurn, "magic", item 1 of tPart) into tMagic
      put Client.PartNote(sTurn, "injured", item 1 of tPart) into tHurt
      if tMagic is not empty and tHurt is not empty then
         put "255,110,200" into tColor
      else if tMagic is not empty then
         put "190,120,255" into tColor
      else if tHurt is not empty then
         put "230,60,60" into tColor
      else
         put "200,200,200" into tColor
      end if
      put item 1 of tPart into tTip
      if tMagic is not empty then put tTip & ": " & tMagic & " (magic)" into tTip
      if tHurt is not empty then put tTip & ", " & tHurt & " (injured)" into tTip
      create graphic tName
      if item 2 of tPart is "oval" then
         set the style of graphic tName to "oval"
         set the rect of graphic tName to item 3 of tPart
         set the filled of graphic tName to false
      else
         set the style of graphic tName to "line"
         set the points of graphic tName to replaceText(item 3 of tPart, " ", return)
      end if
      set the lineSize of graphic tName to 4
      set the foregroundColor of graphic tName to tColor
      set the tooltip of graphic tName to tTip
   end repeat
   unlock messages
   unlock screen
end Client.DrawFigure

-- the scene mode line under the player's description
command Client.ShowMode
   local tNames, i
   if there is not a field "SceneMode" of this stack then exit Client.ShowMode
   if sMode is "explore" or sOrder is empty then
      put "EXPLORING - click a face to choose who acts" into field "SceneMode" of this stack
      exit Client.ShowMode
   end if
   repeat for each item i in sOrder
      put sParty[i]["name"] & ", " after tNames
   end repeat
   delete char -2 to -1 of tNames
   put toUpper(sMode) & " - round " & sRound & ": " & tNames into field "SceneMode" of this stack
end Client.ShowMode

command Client.LoadParty
   local tLine, tInFace, k
   put empty into sParty
   put 0 into sCount
   put false into tInFace
   repeat for each line tLine in the cPartyText of this stack
      if char 1 of tLine is "[" then
         add 1 to sCount
         put char 2 to -2 of tLine into sParty[sCount]["name"]
         put false into tInFace
      else if sCount is 0 then
         next repeat
      else if tInFace then
         if tLine is not empty then
            put tLine & return after sParty[sCount]["face"]
         end if
      else if tLine begins with "face=" then
         put true into tInFace
      else if "=" is in tLine then
         put offset("=", tLine) into k
         put char k + 1 to -1 of tLine into sParty[sCount][char 1 to k - 1 of tLine]
      end if
   end repeat
end Client.LoadParty

-- draws 16x16 bits into an image, each bit pScale pixels, in colour pColor (r,g,b)
command Client.DrawFace pImage, pBits, pScale, pColor
   local tOn, tOff, tData, tLine, tRow, r, c
   if pColor is empty then put "220,220,220" into pColor
   put numToByte(0) & numToByte(item 1 of pColor) & numToByte(item 2 of pColor) & numToByte(item 3 of pColor) into tOn
   put numToByte(0) & numToByte(30) & numToByte(30) & numToByte(36) into tOff
   repeat with r = 1 to 16
      put line r of pBits into tRow
      put empty into tLine
      repeat with c = 1 to 16
         if char c of tRow is "1" then
            repeat pScale times
               put tOn after tLine
            end repeat
         else
            repeat pScale times
               put tOff after tLine
            end repeat
         end if
      end repeat
      repeat pScale times
         put tLine after tData
      end repeat
   end repeat
   set the width of image pImage of this stack to 16 * pScale
   set the height of image pImage of this stack to 16 * pScale
   set the imageData of image pImage of this stack to tData
end Client.DrawFace

-- the party strip along the top: a face and a name for each player (72 px a slot, 4 fit left of the DM text)
command Client.DrawParty
   local i, x, tName
   set the defaultStack to the short name of this stack
   lock screen
   lock messages
   repeat with i = the number of controls of this card down to 1
      put the short name of control i of this card into tName
      if tName begins with "Face_" or tName begins with "FaceName_" then delete control i of this card
   end repeat
   repeat with i = 1 to sCount
      put 12 + (i - 1) * 72 into x
      create image ("Face_" & i)
      set the lockLoc of it to true
      set the cPlayer of it to i
      Client.DrawFace "Face_" & i, sParty[i]["face"], 3, sParty[i]["color"]
      set the topLeft of image ("Face_" & i) to (x + 12) & comma & 8
      create field ("FaceName_" & i)
      set the rect of it to x, 58, x + 72, 78
      set the lockText of it to true
      set the opaque of it to false
      set the showBorder of it to false
      set the traversalOn of it to false
      set the textAlign of it to "center"
      set the foregroundColor of it to "220,220,220"
      set the text of it to sParty[i]["name"]
   end repeat
   unlock messages
   unlock screen
end Client.DrawParty

-- whose turn it is: portrait, name, look, the list, the turn mark
command Client.ShowPlayer
   local x
   set the defaultStack to the short name of this stack
   lock screen
   Client.DrawFigure
   put sParty[sTurn]["name"] into field "PlayerName"
   put sParty[sTurn]["look"] into field "PlayerLook"
   put 12 + (sTurn - 1) * 72 into x
   set the rect of graphic "TurnMark" to x + 1, 4, x + 71, 80
   set the foregroundColor of graphic "TurnMark" to sParty[sTurn]["color"]
   Client.ShowList sKind
   Client.ShowMode
   unlock screen
end Client.ShowPlayer

command Client.ShowList pKind
   local tList
   if pKind is not among the items of "Skills,Weapons,Items,Spells" then put "Skills" into pKind
   put pKind into sKind
   put sParty[sTurn][toLower(pKind)] into tList
   replace "|" with return in tList
   if tList is empty then put "(none)" into tList
   put tList into field "IntentList" of this stack
end Client.ShowList

-- a click on the list: put what the player means to do into Player Input, to finish and send
command Client.UseIntent pLine
   local tSay
   put Client.IntentText(pLine, false) into tSay
   if tSay is empty then exit Client.UseIntent
   put tSay into field "Player Input" of this stack
   focus on field "Player Input" of this stack
   select after text of field "Player Input" of this stack
end Client.UseIntent

-- a double-click on the list: just do it (owner, 15 Nov), no trip back to the chat box
command Client.DoIntent pLine
   local tSay
   put Client.IntentText(pLine, true) into tSay
   if tSay is empty then exit Client.DoIntent
   put empty into field "Player Input" of this stack
   Client.Log sParty[sTurn]["name"] & ": " & tSay
end Client.DoIntent

-- what a list line says as an action: open-ended ("I use my Stealth skill to ") or whole ("I use my Stealth skill.")
function Client.IntentText pLine, pWhole
   local tWhat
   put pLine into tWhat
   if tWhat is empty or tWhat is "(none)" then return empty
   if sKind is "Skills" then
      put word 1 to -2 of tWhat into tWhat
      if pWhole then return "I use my " & tWhat & " skill."
      return "I use my " & tWhat & " skill to "
   else if sKind is "Weapons" then
      if pWhole then return "I attack with my " & tWhat & "."
      return "I attack with my " & tWhat & " "
   else if sKind is "Items" then
      if pWhole then return "I use my " & tWhat & "."
      return "I use my " & tWhat & " to "
   end if
   if pWhole then return "I cast " & tWhat & "."
   return "I cast " & tWhat & " "
end Client.IntentText

-- double-clicks come up from the list field to here (its own script only has mouseUp)
on mouseDoubleUp pButton
   if the short name of the target is "IntentList" and pButton is 1 then
      Client.DoIntent the value of the clickLine
   end if
   pass mouseDoubleUp
end mouseDoubleUp

-- Next Turn: in combat and talk the rolled order (a new round after the last), in explore the next face
command Client.NextTurn
   if sMode is "explore" or sOrder is empty then
      add 1 to sTurn
      if sTurn > sCount then
         put 1 into sTurn
      end if
   else
      add 1 to sOrderPos
      if sOrderPos > the number of items of sOrder then
         put 1 into sOrderPos
         add 1 to sRound
         Client.Log "-- Round " & sRound & " --"
      end if
      put item sOrderPos of sOrder into sTurn
   end if
   Client.Log "-- " & sParty[sTurn]["name"] & "'s turn --"
   Client.ShowPlayer
end Client.NextTurn

command Client.Send
   local tSay
   put field "Player Input" of this stack into tSay
   if tSay is empty then exit Client.Send
   put empty into field "Player Input" of this stack
   if char 1 of tSay is "/" then
      Client.Command tSay
   else
      Client.Log sParty[sTurn]["name"] & ": " & tSay
   end if
end Client.Send

command Client.Command pLine
   local tWord, tRest
   put word 1 of pLine into tWord
   put word 2 to -1 of pLine into tRest
   switch tWord
      case "/llm"
         put textEncode(the long date && the long time & tab & sParty[sTurn]["name"] & tab & tRest & return, "UTF-8") after url ("binfile:" & kSessions & "llm_inbox.txt")
         Client.Log "[to Claude] " & tRest
         break
      case "/dm"
         put tRest into field "DM Text" of this stack
         Client.Log "DM: " & tRest
         break
      case "/clear"
         Client.SaveLog
         put empty into field "Game Log" of this stack
         break
      case "/x"
         Client.RunXTalk tRest
         break
      case "/mode"
         Client.SetMode word 1 of tRest
         break
      default
         Client.Log "Commands: /llm text (to Claude)  /x xtalk (runs it, like the Message Box)  /mode explore|combat|talk  /dm text  /clear (saves the log first)  /help"
   end switch
end Client.Command

-- /x: the Message Box in the chat (owner, 15 Nov). Statements run here, in the stack script, so they
-- see its handlers and this stack's controls; `put x` with no container shows x in the log, and an
-- expression alone ("/x the seconds") shows its value. Runs whatever is typed: the owner's own tool.
command Client.RunXTalk pCode
   local tOut, tErr, tDoErr, tKeepMsg
   if pCode is empty then exit Client.RunXTalk
   Client.Log "> " & pCode
   put msg into tKeepMsg   -- the IDE's Message Box gets its text back afterwards
   put empty into msg
   try
      do pCode
      put msg into tOut
   catch tDoErr
      -- not a statement: try it as an expression; when that fails too, the statement's error says more
      try
         put value(pCode) into tOut
      catch tErr
         put "error: " & line (item 1 of line 1 of tDoErr) of the scriptExecutionErrors & " (" & item 1 of line 1 of tDoErr & ") near " & quote & item 4 of line 1 of tDoErr & quote into tOut
      end try
   end try
   if the result is not empty and tOut is empty then put "result: " & the result into tOut
   put tKeepMsg into msg
   if tOut is not empty then Client.Log tOut
end Client.RunXTalk

command Client.Log pLine
   if field "Game Log" of this stack is not empty then put return after field "Game Log" of this stack
   put pLine after field "Game Log" of this stack
   set the vScroll of field "Game Log" of this stack to the formattedHeight of field "Game Log" of this stack
end Client.Log

-- keeps the game log in OXT-BEYOND/sessions before it is cleared or the stack closes
command Client.SaveLog
   local tLog
   put field "Game Log" of this stack into tLog
   if tLog is empty then exit Client.SaveLog
   put textEncode("== " & the long date && the long time & return & tLog & return & return, "UTF-8") after url ("binfile:" & kSessions & "TTRPG_Client_gamelog.txt")
end Client.SaveLog
