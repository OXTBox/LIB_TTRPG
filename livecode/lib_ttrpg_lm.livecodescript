script "lib_ttrpg_lm"
######################################################################################
## lib_ttrpg_lm (LIB_TTRPG, iteration 1, 15 Nov 2026): LM Studio for TTRPG Studio.
## A port of the LM Studio half of ref/ttrpg_ref.py (http, models, load_one, load_models,
## unload_models, chat, form), plus the JSON reader and writer the engine shares.
##   start using stack ".../livecode/lib_ttrpg_lm.livecodescript"
##   TTRPG.LM.Init                         defaults; long timeouts
##   TTRPG.LM.Models()                     lines: id <tab> state <tab> type (llm / vlm only)
##   TTRPG.LM.LoadModels(pDM, pVoices)     -> the status line; TTRPG.LM.DM() / TTRPG.LM.Voices()
##   TTRPG.LM.UnloadMine                   unload only what this stack loaded
##   TTRPG.LM.Chat tCallA                  one call; replies by dispatch tCallA["msg"] to
##                                         tCallA["target"] with pText, pError
##   TTRPG.LM.Form tCallA                  same, but the reply is a parsed array (empty on failure)
##   TTRPG.LM.Cancel / TTRPG.LM.Busy()
##   TTRPG.JSON.Quote(t) / TTRPG.JSON.Parse(t) / TTRPG.JSON.Export(a) / TTRPG.JSON.Error()
## tCallA keys: role (dm / voice / referee / make / summary), model, system, user,
## schema (JSON text, or empty), temperature, maxTokens, target (long id), msg.
## Transport: tsNet (asynchronous) in the Windows window; elsewhere (the headless server in
## WSL, used by the tests) a blocking curl.exe, and the reply is dispatched before Chat returns.
## The request body is built as text, never with jsonExport (a real true, numbers, one-entry
## enums); the server has no jsonImport either, hence TTRPG.JSON.Parse.
######################################################################################

local sLM          -- url, timeoutMS, sync, ctx
local sReq         -- the call in flight
local sForm        -- the form around it: target, msg, tries
local sNoSystem    -- model -> true: its template refuses the system role
local sLogPath     -- one JSON line a call
local sLoaded      -- models this stack loaded, one a line
local sDM, sVoices
local sCalls       -- role <tab> model, one line a call (the tests read it)
local sLmsExe
local sJ, sJI, sJN, sJErr

-------------------------------------------------------------------- settings

command TTRPG.LM.Init
   if sLM["url"] is empty then put "http://127.0.0.1:1234" into sLM["url"]
   if sLM["timeoutMS"] is empty then put 300000 into sLM["timeoutMS"]    -- a 7B model can take a minute
   if sLM["ctx"] is empty then put 4096 into sLM["ctx"]
   if sLM["sync"] is empty then put (the platform is not "Win32") into sLM["sync"]
   set the socketTimeoutInterval to sLM["timeoutMS"]
   try
      -- DNS, connect, whole transfer, low-speed time, low-speed limit, continue
      tsNetSetTimeouts 10000, 10000, sLM["timeoutMS"], 0, 0, 1000
   catch tErr
   end try
end TTRPG.LM.Init

command TTRPG.LM.Set pName, pValue
   TTRPG.LM.Init
   put pValue into sLM[pName]
   if pName is "timeoutMS" then TTRPG.LM.Init
end TTRPG.LM.Set

function TTRPG.LM.Get pName
   TTRPG.LM.Init
   return sLM[pName]
end TTRPG.LM.Get

command TTRPG.LM.SetLog pPath
   put pPath into sLogPath
end TTRPG.LM.SetLog

function TTRPG.LM.LogPath
   return sLogPath
end TTRPG.LM.LogPath

function TTRPG.LM.DM
   return sDM
end TTRPG.LM.DM

function TTRPG.LM.Voices
   if sVoices is empty then return sDM
   return sVoices
end TTRPG.LM.Voices

-- for tests and for a stack that finds models already loaded
command TTRPG.LM.UseModels pDM, pVoices
   put pDM into sDM
   if pVoices is empty then put pDM into pVoices
   put pVoices into sVoices
end TTRPG.LM.UseModels

function TTRPG.LM.Calls
   return sCalls
end TTRPG.LM.Calls

function TTRPG.LM.Busy
   return sReq["role"] is not empty
end TTRPG.LM.Busy

-------------------------------------------------------------------- blocking HTTP

-- GET (pBody empty) or POST; -> the reply text (UTF-8 decoded); TTRPG.LM.HTTPError() says why if empty
local sHTTPErr
function TTRPG.LM.HTTP pPath, pBody, pTimeoutSec
   local tOld, tData, tFile, tOut, tCmd, tCurl
   TTRPG.LM.Init
   put empty into sHTTPErr
   if pTimeoutSec is empty then put sLM["timeoutMS"] div 1000 into pTimeoutSec
   if the platform is "Win32" then
      put the socketTimeoutInterval into tOld
      set the socketTimeoutInterval to pTimeoutSec * 1000
      if pBody is empty then
         put URL (sLM["url"] & pPath) into tData
      else
         set the httpHeaders to "Content-Type: application/json"
         post textEncode(pBody, "UTF-8") to URL (sLM["url"] & pPath)
         put it into tData
         set the httpHeaders to empty
      end if
      if the result is not empty then put the result into sHTTPErr
      set the socketTimeoutInterval to tOld
      if sHTTPErr is not empty and tData is empty then return empty
      return textDecode(tData, "UTF-8")
   end if
   -- Linux / WSL: curl.exe reaches the Windows host's LM Studio (WSL's own 127.0.0.1 does not)
   put "curl.exe" into tCurl
   if shell("command -v curl.exe") is empty then put "curl" into tCurl
   put lmTemp("reply") into tOut
   put "cd /mnt/c 2>/dev/null; " & tCurl & " -sS -m " & pTimeoutSec into tCmd
   if pBody is not empty then
      put lmTemp("body") into tFile
      put textEncode(pBody, "UTF-8") into URL ("binfile:" & tFile)
      put "cat '" & tFile & "' | " & tCmd & " -H 'Content-Type: application/json' --data-binary @-" into tCmd
   else
      put " </dev/null" after tCmd                 -- a Windows .exe must not eat the terminal's input
   end if
   put " " & sLM["url"] & pPath & " > '" & tOut & "' 2>&1" after tCmd
   get shell(tCmd)
   put textDecode(URL ("binfile:" & tOut), "UTF-8") into tData
   if tFile is not empty then delete file tFile
   delete file tOut
   if tData is empty or char 1 of word 1 of tData is not among the chars of "{[" then
      put tData into sHTTPErr
      if sHTTPErr is empty then put "no answer" into sHTTPErr
      return empty
   end if
   return tData
end TTRPG.LM.HTTP

function TTRPG.LM.HTTPError
   return sHTTPErr
end TTRPG.LM.HTTPError

private function lmTemp pName
   return specialFolderPath("temporary") & "/ttrpg_" & pName & "_" & the milliseconds & random(100000) & ".txt"
end lmTemp

-------------------------------------------------------------------- models

-- lines: id <tab> state <tab> type, chat models only; empty when the server is not running
function TTRPG.LM.Models
   local tA, tOut, i, tM
   put TTRPG.JSON.Parse(TTRPG.LM.HTTP("/api/v0/models", empty, 10)) into tA
   if tA is not an array then return empty
   repeat with i = 1 to the number of elements of tA["data"]
      put tA["data"][i] into tM
      if tM["type"] is not among the items of "llm,vlm" then next repeat
      put tM["id"] & tab & tM["state"] & tab & tM["type"] & return after tOut
   end repeat
   delete the last char of tOut
   return tOut
end TTRPG.LM.Models

function TTRPG.LM.IsLoaded pModel
   local tLine
   set the itemDel to tab
   repeat for each line tLine in TTRPG.LM.Models()
      if item 1 of tLine is pModel and item 2 of tLine is "loaded" then return true
   end repeat
   return false
end TTRPG.LM.IsLoaded

-- the lms command line tool; -> its output, colour codes removed
function TTRPG.LM.Lms pArgs
   local tOut
   put lmLmsExe() into sLmsExe
   if sLmsExe is empty then return "lms not found"
   if the platform is "Win32" then
      set the hideConsoleWindows to true
      put shell(quote & sLmsExe & quote && pArgs & " 2>&1") into tOut
   else
      put shell("cd /mnt/c 2>/dev/null; '" & sLmsExe & "' " & pArgs & " </dev/null 2>&1") into tOut
   end if
   return replaceText(tOut, numToChar(27) & "\[[0-9;?]*[A-Za-z]", empty)
end TTRPG.LM.Lms

private function lmLmsExe
   local tHome
   if sLmsExe is not empty then return sLmsExe
   if the platform is "Win32" then
      return $USERPROFILE & "\.cache\lm-studio\bin\lms.exe"
   end if
   put line 1 of shell("cd /mnt/c 2>/dev/null; cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null </dev/null") into tHome
   replace numToChar(13) with empty in tHome
   if tHome is not empty and tHome is not "%USERPROFILE%" then
      put line 1 of shell("wslpath '" & tHome & "'") into tHome
      return tHome & "/.cache/lm-studio/bin/lms.exe"
   end if
   return $HOME & "/.cache/lm-studio/bin/lms"
end lmLmsExe

-- "loaded", "already loaded" or "failed: <the first error line>"
function TTRPG.LM.LoadOne pModel
   local tOut, tLine, tLast
   if TTRPG.LM.IsLoaded(pModel) then return "already loaded"
   put TTRPG.LM.Lms("load '" & pModel & "' --identifier '" & pModel & "' --context-length " & TTRPG.LM.Get("ctx") & " --ttl 1800 --yes") into tOut
   if TTRPG.LM.IsLoaded(pModel) then
      if pModel is not among the lines of sLoaded then put pModel & return after sLoaded
      return "loaded"
   end if
   replace numToChar(13) with return in tOut
   repeat for each line tLine in tOut
      if word 1 to -1 of tLine is empty then next repeat
      if tLast is empty and matchText(tLine, "(?i)error|not found|cannot|memory|failed") then put word 1 to -1 of tLine into tLast
   end repeat
   if tLast is empty then
      repeat with tLine = the number of lines of tOut down to 1
         if word 1 to -1 of line tLine of tOut is not empty then
            put word 1 to -1 of line tLine of tOut into tLast
            exit repeat
         end if
      end repeat
   end if
   return "failed: " & char 1 to 200 of tLast
end TTRPG.LM.LoadOne

-- load DM, then Voices; Voices fails -> one model plays both, and the line says so
function TTRPG.LM.LoadModels pDM, pVoices
   local tMsg
   put empty into sDM
   put empty into sVoices
   if TTRPG.LM.Models() is empty then
      get TTRPG.LM.Lms("server start --port 1234")
      if TTRPG.LM.Models() is empty then
         return "LM Studio server is not running (open LM Studio, Developer tab, Start Server)"
      end if
   end if
   put TTRPG.LM.LoadOne(pDM) into tMsg
   if tMsg begins with "failed" then return "DM model" && pDM && tMsg
   put pDM into sDM
   if pVoices is empty or pVoices is pDM or pVoices is "Same as DM" then
      put pDM into sVoices
      return "loaded:" && pDM && "(DM and Voices)"
   end if
   put TTRPG.LM.LoadOne(pVoices) into tMsg
   if tMsg begins with "failed" then
      put pDM into sVoices
      return "loaded:" && pDM & ". Voices model" && pVoices && tMsg & ", so" && pDM && "plays the voices too"
   end if
   put pVoices into sVoices
   return "loaded: DM" && pDM & ", Voices" && pVoices
end TTRPG.LM.LoadModels

-- only the models this stack loaded: one found already loaded may be Spark at work
command TTRPG.LM.UnloadMine
   local tM
   repeat for each line tM in sLoaded
      if tM is not empty then get TTRPG.LM.Lms("unload '" & tM & "'")
   end repeat
   put empty into sLoaded
end TTRPG.LM.UnloadMine

function TTRPG.LM.LoadedByMe
   return sLoaded
end TTRPG.LM.LoadedByMe

-------------------------------------------------------------------- one call

-- the request, as text: a real true and false, numbers as numbers, the schema as given
function TTRPG.LM.Body pA, pMerge
   local tB, tTemp
   put "{" & quote & "model" & quote & ":" & TTRPG.JSON.Quote(pA["model"]) into tB
   if pMerge then
      put "," & quote & "messages" & quote & ":[{" & quote & "role" & quote & ":" & quote & "user" & quote & "," & \
            quote & "content" & quote & ":" & TTRPG.JSON.Quote(pA["system"] & return & return & pA["user"]) & "}]" after tB
   else
      put "," & quote & "messages" & quote & ":[{" & quote & "role" & quote & ":" & quote & "system" & quote & "," & \
            quote & "content" & quote & ":" & TTRPG.JSON.Quote(pA["system"]) & "},{" & \
            quote & "role" & quote & ":" & quote & "user" & quote & "," & \
            quote & "content" & quote & ":" & TTRPG.JSON.Quote(pA["user"]) & "}]" after tB
   end if
   put pA["temperature"] into tTemp
   if tTemp is not a number then put 0.8 into tTemp
   put "," & quote & "temperature" & quote & ":" & tTemp after tB
   put "," & quote & "max_tokens" & quote & ":" & (pA["maxTokens"] + 0) after tB
   put "," & quote & "stream" & quote & ":false" after tB
   if pA["schema"] is not empty then
      put "," & quote & "response_format" & quote & ":{" & quote & "type" & quote & ":" & quote & "json_schema" & quote & "," & \
            quote & "json_schema" & quote & ":{" & quote & "name" & quote & ":" & TTRPG.JSON.Quote(pA["role"]) & "," & \
            quote & "strict" & quote & ":true," & quote & "schema" & quote & ":" & pA["schema"] & "}}" after tB
   end if
   return tB & "}"
end TTRPG.LM.Body

command TTRPG.LM.Chat pA
   TTRPG.LM.Init
   if TTRPG.LM.Busy() then return "busy"
   put pA into sReq
   put "ttrpg" & the milliseconds into sReq["id"]
   put the milliseconds into sReq["startMS"]
   put (sNoSystem[pA["model"]] is true) into sReq["merged"]
   put empty into sReq["first"]
   lmSend
   return empty
end TTRPG.LM.Chat

private command lmSend
   local tBody, tErr
   put TTRPG.LM.Body(sReq, sReq["merged"]) into tBody
   if not sLM["sync"] then
      try
         put tsNetPost(sReq["id"], sLM["url"] & "/v1/chat/completions", "Content-Type: application/json", \
               textEncode(tBody, "UTF-8"), "TTRPG.LM.tsNetDone") into tErr
         if tErr is empty then exit lmSend
      catch tErr
      end try
      put true into sLM["sync"]          -- no tsNet: blocking from now on
   end if
   lmGot TTRPG.LM.HTTP("/v1/chat/completions", tBody), TTRPG.LM.HTTPError()
end lmSend

-- tsNet calls this when the transfer ends
on TTRPG.LM.tsNetDone pId, pResult, pBytes, pCurlCode
   local tErr, tData
   if pId is not sReq["id"] then
      try
         tsNetCloseConn pId
      catch tErr
      end try
      exit TTRPG.LM.tsNetDone
   end if
   put empty into tErr
   put tsNetRetrieveData(pId, tErr) into tData
   if pCurlCode is not 0 then
      try
         put tsNetRetrieveError(pId) into tErr
      catch tErr
      end try
      if tErr is empty then put "connection failed (curl" && pCurlCode & ")" into tErr
   end if
   try
      tsNetCloseConn pId
   catch tData2
   end try
   lmGot textDecode(tData, "UTF-8"), tErr
end TTRPG.LM.tsNetDone

-- a reply (or none): system-role fallback, log, trim, then hand it on
private command lmGot pRaw, pErr
   local tA, tText, tFinish, tCall, tChoice
   put TTRPG.JSON.Parse(pRaw) into tA
   if tA is an array and tA["choices"] is empty and not sReq["merged"] then
      -- e.g. Gemma: "System role not supported": once more with system + user merged
      put true into sNoSystem[sReq["model"]]
      put pRaw into sReq["first"]
      put true into sReq["merged"]
      put true into sReq["fellBack"]
      lmSend
      exit lmGot
   end if
   if sReq["fellBack"] and (tA is not an array or tA["choices"] is empty) then
      delete variable sNoSystem[sReq["model"]]
      put TTRPG.JSON.Parse(sReq["first"]) into tA
      put sReq["first"] into pRaw
   end if
   if tA is an array and tA["choices"] is an array then
      put tA["choices"][1] into tChoice
      put tChoice["message"]["content"] into tText
      put replaceText(tText, "(?s)<think>.*?</think>", empty) into tText
      put word 1 to -1 of tText into tText
      put tChoice["finish_reason"] into tFinish
   else if pErr is empty then
      if tA is an array and tA["error"] is an array then
         put tA["error"]["message"] into pErr
      else if tA is an array and tA["error"] is not empty then
         put tA["error"] into pErr
      else
         put char 1 to 300 of pRaw into pErr
      end if
      if pErr is empty then put "no answer" into pErr
   end if
   put sReq["role"] & tab & sReq["model"] & return after sCalls
   lmLog tText, tFinish, pErr
   if tFinish is "length" and sReq["schema"] is empty then put TTRPG.WholeSentences(tText) into tText
   put sReq into tCall
   put empty into sReq
   if tCall["form"] is true then
      lmFormGot tText, pErr
   else if tCall["target"] is not empty and exists(tCall["target"]) then
      dispatch tCall["msg"] to tCall["target"] with tText, pErr
   end if
end lmGot

private command lmLog pText, pFinish, pErr
   local tL, tSecs
   if sLogPath is empty then exit lmLog
   put round((the milliseconds - sReq["startMS"]) / 100) / 10 into tSecs
   put "{" & quote & "time" & quote & ":" & TTRPG.JSON.Quote(the long time) into tL
   put "," & quote & "role" & quote & ":" & TTRPG.JSON.Quote(sReq["role"]) after tL
   put "," & quote & "model" & quote & ":" & TTRPG.JSON.Quote(sReq["model"]) after tL
   put "," & quote & "system" & quote & ":" & TTRPG.JSON.Quote(sReq["system"]) after tL
   put "," & quote & "user" & quote & ":" & TTRPG.JSON.Quote(sReq["user"]) after tL
   put "," & quote & "reply" & quote & ":" & TTRPG.JSON.Quote(pText) after tL
   put "," & quote & "finish" & quote & ":" & TTRPG.JSON.Quote(pFinish) after tL
   put "," & quote & "error" & quote & ":" & TTRPG.JSON.Quote(pErr) after tL
   put "," & quote & "merged" & quote & ":" & (sReq["merged"] is true) after tL
   put "," & quote & "seconds" & quote & ":" & tSecs & "}" & numToChar(10) after tL
   put textEncode(tL, "UTF-8") after URL ("binfile:" & sLogPath)
end lmLog

-- a call that must come back as a JSON object: one retry. Replies with an array, or empty.
command TTRPG.LM.Form pA
   if TTRPG.LM.Busy() then return "busy"
   put pA["target"] into sForm["target"]
   put pA["msg"] into sForm["msg"]
   put 1 into sForm["tries"]
   put pA into sForm["call"]
   put true into pA["form"]
   TTRPG.LM.Chat pA
   return empty
end TTRPG.LM.Form

private command lmFormGot pText, pErr
   local tA, tTarget, tMsg
   put TTRPG.JSON.Parse(pText) into tA
   if tA is not an array and sForm["tries"] < 2 then
      add 1 to sForm["tries"]
      put sForm["call"] into tA
      put true into tA["form"]
      TTRPG.LM.Chat tA
      exit lmFormGot
   end if
   put sForm["target"] into tTarget
   put sForm["msg"] into tMsg
   put empty into sForm
   if tA is not an array then put empty into tA
   if tTarget is not empty and exists(tTarget) then dispatch tMsg to tTarget with tA, pErr
end lmFormGot

-- stop the call in flight; nobody is told
command TTRPG.LM.Cancel
   if sReq["id"] is not empty and not sLM["sync"] then
      try
         tsNetCloseConn sReq["id"]
      catch tErr
      end try
   end if
   put empty into sReq
   put empty into sForm
end TTRPG.LM.Cancel

-------------------------------------------------------------------- JSON

-- a JSON string, quotes included
function TTRPG.JSON.Quote pText
   local i
   replace "\" with "\\" in pText
   replace quote with "\" & quote in pText
   replace numToChar(13) & numToChar(10) with "\n" in pText
   replace numToChar(10) with "\n" in pText
   replace numToChar(13) with "\r" in pText
   replace tab with "\t" in pText
   repeat with i = 0 to 31
      if pText contains numToChar(i) then replace numToChar(i) with "\u00" & format("%02x", i) in pText
   end repeat
   return quote & pText & quote
end TTRPG.JSON.Quote

function TTRPG.JSON.Error
   return sJErr
end TTRPG.JSON.Error

-- JSON text -> array (lists keyed 1..n) or a plain value; true / false / null -> "true" / "false" / empty.
-- Not JSON -> empty, and TTRPG.JSON.Error() says where.
function TTRPG.JSON.Parse pText
   local tV
   put pText into sJ
   put 1 into sJI
   put the number of codeunits of sJ into sJN
   put empty into sJErr
   if word 1 to -1 of pText is empty then
      put "empty" into sJErr
      return empty
   end if
   try
      jsSkip
      put jsValue() into tV
      jsSkip
      if sJI <= sJN then put "extra text at" && sJI into sJErr
   catch tE
      if sJErr is empty then put "bad JSON near" && sJI into sJErr
   end try
   put empty into sJ
   if sJErr is not empty then return empty
   return tV
end TTRPG.JSON.Parse

private command jsSkip
   repeat while sJI <= sJN and codeunit sJI of sJ is among the items of (" ," & tab & "," & numToChar(10) & "," & numToChar(13))
      add 1 to sJI
   end repeat
end jsSkip

private command jsFail pWhat
   put pWhat && "at" && sJI into sJErr
   throw sJErr
end jsFail

private function jsValue
   local c, tA, n, tKey, tNum
   if sJI > sJN then jsFail "unexpected end"
   put codeunit sJI of sJ into c
   switch c
      case "{"
         add 1 to sJI
         put empty into tA
         jsSkip
         if codeunit sJI of sJ is "}" then
            add 1 to sJI
            return tA
         end if
         repeat
            jsSkip
            if codeunit sJI of sJ is not quote then jsFail "a key expected"
            put jsString() into tKey
            jsSkip
            if codeunit sJI of sJ is not ":" then jsFail "':' expected"
            add 1 to sJI
            jsSkip
            if tKey is empty then put "_" into tKey
            put jsValue() into tA[tKey]
            jsSkip
            if codeunit sJI of sJ is "," then
               add 1 to sJI
            else if codeunit sJI of sJ is "}" then
               add 1 to sJI
               return tA
            else
               jsFail "',' or '}' expected"
            end if
         end repeat
         break
      case "["
         add 1 to sJI
         put empty into tA
         put 0 into n
         jsSkip
         if codeunit sJI of sJ is "]" then
            add 1 to sJI
            return tA
         end if
         repeat
            jsSkip
            add 1 to n
            put jsValue() into tA[n]
            jsSkip
            if codeunit sJI of sJ is "," then
               add 1 to sJI
            else if codeunit sJI of sJ is "]" then
               add 1 to sJI
               return tA
            else
               jsFail "',' or ']' expected"
            end if
         end repeat
         break
      case quote
         return jsString()
      case "t"
         if codeunit sJI to sJI + 3 of sJ is not "true" then jsFail "bad word"
         add 4 to sJI
         return "true"
      case "f"
         if codeunit sJI to sJI + 4 of sJ is not "false" then jsFail "bad word"
         add 5 to sJI
         return "false"
      case "n"
         if codeunit sJI to sJI + 3 of sJ is not "null" then jsFail "bad word"
         add 4 to sJI
         return empty
      default
         put empty into tNum
         repeat while sJI <= sJN and codeunit sJI of sJ is among the chars of "+-0123456789.eE"
            put codeunit sJI of sJ after tNum
            add 1 to sJI
         end repeat
         if tNum is empty or tNum is not a number then jsFail "a value expected"
         return tNum
   end switch
end jsValue

-- at the opening quote; -> the string, sJI after the closing quote
private function jsString
   local tOut, c, tStart, tHex, tCode, tLow
   add 1 to sJI
   repeat
      put sJI into tStart
      repeat while sJI <= sJN
         put codeunit sJI of sJ into c
         if c is quote or c is "\" then exit repeat
         add 1 to sJI
      end repeat
      if sJI > sJN then jsFail "unclosed string"
      if sJI > tStart then put codeunit tStart to sJI - 1 of sJ after tOut
      if c is quote then
         add 1 to sJI
         return tOut
      end if
      -- a backslash
      put codeunit sJI + 1 of sJ into c
      add 2 to sJI
      switch c
         case "n"
            put numToChar(10) after tOut
            break
         case "r"
            put numToChar(13) after tOut
            break
         case "t"
            put tab after tOut
            break
         case "b"
            put numToChar(8) after tOut
            break
         case "f"
            put numToChar(12) after tOut
            break
         case "u"
            put codeunit sJI to sJI + 3 of sJ into tHex
            add 4 to sJI
            put baseConvert(tHex, 16, 10) into tCode
            if tCode >= 55296 and tCode <= 56319 and codeunit sJI to sJI + 1 of sJ is "\u" then
               put baseConvert(codeunit sJI + 2 to sJI + 5 of sJ, 16, 10) into tLow
               if tLow >= 56320 and tLow <= 57343 then
                  put 65536 + (tCode - 55296) * 1024 + (tLow - 56320) into tCode
                  add 6 to sJI
               end if
            end if
            put numToCodepoint(tCode) after tOut
            break
         default
            put c after tOut           -- \" \\ \/
      end switch
   end repeat
end jsString

-- array or value -> JSON text, one item a line (indent 1, like the Python files).
-- Keys 1..n -> a list. "true" / "false" -> true / false; plain decimal numbers stay numbers.
-- Keys in kListKeys are lists even when empty. Keys come in a reading order (kKeyOrder), then A to Z.
constant kListKeys = "turns,clues,characters"
constant kKeyOrder = "id,name,kind,player,look,voice,wants,secret,keep,skills,idea,title,place,happening,wrong,truth,clues,characters,opening,summary,folded,turns,ended,file,where,skill,fact,found,tries,action,ruling,speaker,reply,who,success,roll,clue,result"

function TTRPG.JSON.Export pV
   return jsOut(pV, 0, empty)
end TTRPG.JSON.Export

private function jsOut pV, pDepth, pKey
   local tKeys, tOut, tPad, tPadIn, k, n, tIsList, tOrdered
   if pV is not an array then
      if pV is empty and pKey is among the items of kListKeys then return "[]"
      if pV is "true" or pV is "false" then return pV
      if matchText(pV, "^-?(0|[1-9][0-9]{0,14})(\.[0-9]+)?$") then return pV
      return TTRPG.JSON.Quote(pV)
   end if
   put the keys of pV into tKeys
   put the number of lines of tKeys into n
   put true into tIsList
   repeat with k = 1 to n
      if not (k is among the lines of tKeys) then
         put false into tIsList
         exit repeat
      end if
   end repeat
   put return & char 1 to pDepth + 1 of "                                        " into tPadIn
   put return & char 1 to pDepth of "                                        " into tPad
   if pDepth is 0 then put return into tPad
   if tIsList then
      repeat with k = 1 to n
         put "," & tPadIn & jsOut(pV[k], pDepth + 1, empty) after tOut
      end repeat
      delete char 1 of tOut
      return "[" & tOut & tPad & "]"
   end if
   repeat for each item k in kKeyOrder
      if k is among the lines of tKeys then put k & return after tOrdered
   end repeat
   sort lines of tKeys
   repeat for each line k in tKeys
      if not (k is among the items of kKeyOrder) then put k & return after tOrdered
   end repeat
   repeat for each line k in tOrdered
      put "," & tPadIn & TTRPG.JSON.Quote(k) & ": " & jsOut(pV[k], pDepth + 1, k) after tOut
   end repeat
   delete char 1 of tOut
   return "{" & tOut & tPad & "}"
end jsOut
