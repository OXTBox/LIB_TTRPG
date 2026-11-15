-- client_main.livecodescript: the stack script of TTRPG_Client (the player's window).
-- SOURCE OF TRUTH: edit this file, never only the stack. Dev.NewVersion (LIB_DEV/tools/xtalk/dev_version.livecodescript)
-- puts it into each new TTRPG_Client_dev_<stamp> stack. Written by Opus via the xTalk MCP Bridge, 15 Nov 2026.
-- Party data: the custom property cPartyText of this stack, one [Name] section a player
-- (look=, color=r,g,b, skills=, weapons=, items=, spells= with | between entries, then face= and 16 rows of 0/1).
-- Commands typed in Player Input: /llm text (to Claude, saved in OXT-BEYOND/sessions/llm_inbox.txt),
-- /dm text (puts text in the DM field), /clear (saves the log, then clears it), /help.
-- Never name this stack in code (its name changes every version): use this stack.
constant kSessions = "//wsl$/Ubuntu/home/igame3d/projects/OXT-BEYOND/sessions/"
local sParty, sCount, sTurn, sKind

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
   Client.DrawParty
   Client.ShowPlayer
end Client.Init

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
   Client.DrawFace "Portrait", sParty[sTurn]["face"], 8, sParty[sTurn]["color"]
   set the topLeft of image "Portrait" to 12, 92
   put sParty[sTurn]["name"] into field "PlayerName"
   put sParty[sTurn]["look"] into field "PlayerLook"
   put 12 + (sTurn - 1) * 72 into x
   set the rect of graphic "TurnMark" to x + 1, 4, x + 71, 80
   set the foregroundColor of graphic "TurnMark" to sParty[sTurn]["color"]
   Client.ShowList sKind
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

-- a click on the list: put what the player means to do into Player Input
command Client.UseIntent pLine
   local tWhat, tSay
   put pLine into tWhat
   if tWhat is empty or tWhat is "(none)" then exit Client.UseIntent
   if sKind is "Skills" then
      put word 1 to -2 of tWhat into tWhat
      put "I use my " & tWhat & " skill to " into tSay
   else if sKind is "Weapons" then
      put "I attack with my " & tWhat & " " into tSay
   else if sKind is "Items" then
      put "I use my " & tWhat & " to " into tSay
   else
      put "I cast " & tWhat & " " into tSay
   end if
   put tSay into field "Player Input" of this stack
   focus on field "Player Input" of this stack
   select after text of field "Player Input" of this stack
end Client.UseIntent

command Client.NextTurn
   add 1 to sTurn
   if sTurn > sCount then put 1 into sTurn
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
      default
         Client.Log "Commands: /llm text (to Claude)  /dm text  /clear (saves the log first)  /help"
   end switch
end Client.Command

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
