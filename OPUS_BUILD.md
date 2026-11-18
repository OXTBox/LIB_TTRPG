# Build list for Opus: the TTRPG Studio stack

Written by Fable, 15 Nov 2026. The engine is designed and tested (`DESIGN.md`,
`ref/ttrpg_ref.py`, `prompts/`). What is left is a port to LiveCode and a window. Do not redesign
the turn; if a prompt needs tuning, tune it in the terminal version first (it takes seconds),
then both share the same `prompts/*.txt`.

Read first: `LIB_SYSTEM/LIB_ALPHA.md`, `DESIGN.md`, `ref/ttrpg_ref.py` (570 lines, the spec),
`Vibecode3D/LiveCode_Claude_Kit/kit/docs/livecode-gotchas.md`.
Branch `ttrpg-studio-1` (already made). Commit as you go. The owner merges.
**Ask the owner before loading models while he is at the machine; unload when you finish.**

## Files to make (all in `livecode/`)

| File | Holds |
|---|---|
| `lib_ttrpg_lm.livecodescript` | LM Studio: list, load, unload, one async chat call, the log |
| `lib_ttrpg.livecodescript` | the engine: characters, scene, ruling, turn, summary, text cleaning. No UI, no field names |
| `studio_stack.livecodescript` | the stack script: UI handlers only, calls the two libraries |
| `build_studio.livecodescript` | builder, modelled on `LIB_BIT/editor/livecode/build_editor.livecodescript`: `Build.Studio <dir>` makes `TTRPG_Studio.livecode` from the scripts |

## Steps

1. **LM library.** Port `http`, `models`, `load_one`, `load_models`, `unload_models`, `chat`, `form`.
   - Chat calls must be asynchronous (`tsNetPost` with a callback; `post` blocks and times out at
     10 s). Pattern: the `LIB_LLM` card script in
     `XTJSON/XtRedeemer_FIRST_SUCCESS/XTJSON/scripts/3DSCENE_v111092026d_LIB_LLM__card_6208_LIB_LLM.livecodescript`.
     Set a long timeout (a 7B model can take a minute).
   - **Build the request body as text, not with jsonExport.** The body needs a real `true`
     (`"strict": true`, `"stream": false`), numbers that stay numbers and `enum` lists that stay
     lists even with one entry; jsonExport cannot be trusted with any of those. Write
     `TTRPG.JSON.Quote(text)` (escape `\`, `"`, newline, return, tab, control characters) and
     put the body together by hand. Parse replies with `jsonImport` (reply text is at
     `choices[1]["message"]["content"]` after import).
   - The three schemas (scene, character, referee) are in `ttrpg_ref.py`: `SCENE_SCHEMA`,
     `CHARACTER_SCHEMA`, and the referee's inside `rule()`. The referee's `who` and `spot` enums
     change every turn: build that text each time.
   - `textEncode(body, "UTF-8")` out, `textDecode(reply, "UTF-8")` in.
   - `lms.exe` is at `$USERPROFILE & "\.cache\lm-studio\bin\lms.exe"`. `set the hideConsoleWindows
     to true` before `shell()`. A load blocks for 5 to 30 s: show "loading..." first
     (`send ... in 10 milliseconds`), or use `open process`.
   - The system-role fallback (merge system + user, remember per model) is in `chat()`. Keep it.
   - Log every call: one JSON line appended to `Data.Path("Logs", "TTRPG/<dated>_session.jsonl")`.
2. **Engine library.** Port the `Studio` class and the text helpers. Scene and characters are
   LiveCode arrays shaped exactly as the JSON in `DESIGN.md` (lists = arrays keyed 1..n), saved
   with `jsonExport` (fine here: files, not requests; check that `found` and `player` read back
   as true / false) through `Data.Path("Games", "TTRPG/scenes/..." )` and `.../characters/...`.
   - A turn is several calls in a row, so in async form it is a short chain:
     `TTRPG.Turn.Begin pAction` -> referee callback -> `TTRPG.Rule` (pure code) -> narrator or
     voice callback -> `TTRPG.Turn.Finish` (append the turn, save, tell the UI by `dispatch
     "TTRPG.Shown"` with the lines) -> `TTRPG.Fold` when due. Keep one "busy" flag: no second
     turn while one runs.
   - Text cleaning: port `sentences`, `whole_sentences`, `clean_narration`, `clean_speech`,
     `slug`, `name_words`, `is_named`. **`ref/vectors.json` has inputs and expected outputs: write
     `TTRPG.SelfTest` that runs them all and reports mismatches.** LiveCode's `matchText` /
     `replaceText` are PCRE, so the Python patterns carry over; the sentence splitter is easier
     as a character loop than as a regex.
   - `random(20)` for the die.
3. **Prompts.** Read `../prompts/<name>.txt` at start (path from the stack's folder; the builder
   also copies them into a custom property set `Prompts` so the stack works when moved). `fill`
   = `replace "{key}" with value`.
4. **The window** (text only; LIB_THEME as the editor's builder does):
   - card `About` first (rule 17), card `Studio` second.
   - left: **Models** panel: two option menus (DM, Voices; Voices starts on "Same as DM"),
     buttons Refresh / Load / Unload, one status line (the text `load_models` returns).
   - middle: **Scene** field (title + opening, read only), the **chat log** (scrolling, the
     player's lines, roll lines in grey brackets, clue lines marked), the **input** field
     (Return sends), a "thinking..." mark while busy.
   - right: **Characters** list (name, kind; click = show look / voice / wants / secret in a small
     editor; New, Delete, "Keep after scene" tick), and the player's sheet (name, look, 8 skill bonuses).
   - buttons: New Scene (asks the one-line idea), Add Character (one-line ask -> `make_character`,
     or by hand), Regenerate (also a key: Ctrl+R), DM Notes (the `/notes` view: truth, clues with
     found marks, summary; it is the owner's game, he may peek), End Scene (tick who to keep).
   - Escape pauses (rule 18): cancels a running call and shows the developer options (max tokens
     per role, temperature, keep-turns, summary-every, context length).
   - Title by rules 13 / 14; `closeStackRequest` per rule 12b, and it unloads the models the
     stack itself loaded.
5. **Compile and lint** every script (`LIB_MCP/tools/lcmcp compile`, `lcmcp lint`).
6. **Test** through LIB_MCP: `TTRPG.SelfTest` (vectors), then the scripted run in
   `cmd_test()` ported as `TTRPG.OwnerTest` (same PASS / FAIL lines), then a screenshot.
7. **Tune** (weak spots 1 to 4 in `DESIGN.md`), in the terminal version, reading the session
   logs. Try `qwen2.5-7b-instruct-1m` as DM with a 2B for Voices, and `llama2-13b-psyfighter2`
   as Voices if memory allows. Record what was tried in `TUNING.md`.
8. **Hand over**: stack in `LIB_TEST/`, title `FOR BILL | New Scene, type an idea, then type what
   you do`, every new file through `python3 -I ~/projects/LIB_DEV/tools/for_review.py add`.
9. **Later, not now**: carry the old studio's world / actor / item handlers into
   `livecode/lib_ttrpg_world.livecodescript` (from `XTJSON/batch/TTRPG_STUDIO_020920229AM/scripts/
   TTRPGtudioapilib_02092026__stack.livecodescript`), fixing as they are touched: the second
   `SaveWorldObjectToJSON` (line 361) and `init.globals` shadow earlier copies; rename
   `InterpregPlayerAction` and its callers; the `LM_Init` URL is `127.0.01` (a typo that happens
   to work); `GetFirsgWorldAssets`; four fields named `WeaponField1`. Its LM handlers
   (`LM_Init`, `LM_BuildRequestJSON`, `LM_TestConnection`) are replaced by step 1, not carried.
   Its `nouns` and `roles` sets go to **LIB_LISTS** (`<set>/<list>.txt`, added to its CATALOG.md;
   moved by a script that counts lines and never prints the words), and LIB_GENERICA **refers** to
   them by name (owner, 18 Nov: "the LIST might grow/change outside of the sub-projects that use
   them"; TODO A-66). They can then seed scene ideas and character asks.

## The owner's test maps to

| Owner's step | Covered by |
|---|---|
| 1 pick gemma, Load: loaded | step 1 + 4; engine path tested from the terminal |
| 2 opening, 3 to 5 sentences, no options | tested (`test`, "2 ...") |
| 3 search the walls: one clue | tested ("3 ..."): by construction, see DESIGN "The one idea" |
| 4 a character answers, not the DM | tested ("4 ..."): the narrator is not called on talk |
| 5 second model, or fall back and say so | both paths tested |
| 6 constants and the log survive | tested ("6 ...") |
