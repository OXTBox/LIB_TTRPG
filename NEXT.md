# LIB_TTRPG: where we left off (come back here)

## 23 Nov 2026: the World panel is built (branch `world-panel`, not merged, waits for the owner's look)
- Owner's answers (23 Nov): own card (World tab); New / Load / Save World; NPCs here -> Add Character;
  small map of cells (click a neighbour = walk); "Scene here"; NOT the "You are at..." prose: the cell is
  plain data, editable by the user (later a model); a Verbose switch has the DM model pad it into words;
  typing in the Studio tries world actions first.
- Built: Studio top row has a World button -> card "World": map (text, @ & n m .; click = see/edit a cell,
  next to @ = walk, Shift-click = just look), the cell as plain lines + Apply / Revert, Verbose (DM model,
  visible tile only, remembered per cell), Here list + lore + Add as character (by hand / DM model),
  Scene here. St.Send: world actions first, no model needed; during a scene look / search still go to the
  DM (they find the clues). Closing / New / Load ask before dropping an unsaved world.
- Spec first: `ref/ttrpg_world.py` cell_data / set_cell_data / map_lines (+ vectors); port
  TTRPG.World.CellData / SetCellData / MapLines / Here / Ordered / Describe.
- Tests: `lc_world_test.txt` (0 fails), new `lc_world_ui_test.txt` (0 fails), the old ones still pass.
- Not seen on a screen yet: the map font (Courier New 18) and the card's look. LIB_TEST's copy is older.
- Next, after his look: a model that EDITS the cell data (owner: "modifiable by the users/LLM").
- OWNER SAW (23 Nov): Verbose answers "as if looking at a LiveCode object instead of an RPG map", and it
  "sees the total map sometimes". Fix later: a real system prompt for world_tile (what to output, plain
  RPG narration, never mention data / JSON / fields), send the tile as plain lines rather than JSON, and
  check that nothing beyond the one cell reaches it. PARKED: the owner put the whole Studio in one bubble at
  the bottom of the tube, "TTRPG STUDIO: Total Application Review & Comments Required by Owner." (n-58af1221):
  a full application that needs dedicated testing, feedback and design; his head is not in TTRPG now.

## 19 Nov 2026 evening: the old studio's world code is in (branch `ttrpg-world-code`, not merged)
- `ref/ttrpg_world.py` (spec) + `livecode/lib_ttrpg_world.livecodescript` (port), same answers on
  `ref/world_vectors.json`. Map of what became of each old handler: `livecode/WORLD_PORT.md`.
- Try it in a terminal: `python3 ref/ttrpg_world.py new` then `python3 ref/ttrpg_world.py play`
  (look, take, drop, open, close, search, n/s/e/w, `idea` = a New Scene idea from where you stand, q).
- Tests: `python3 ref/ttrpg_world.py test`; `lc_world_test.txt` headless. Studio tests still pass;
  the library is a substack of the rebuilt `TTRPG_Studio.livecode` but no button uses it yet.
- Next (ask the owner): a World panel in the Studio (New World, the view, "Scene here" = SceneIdea ->
  New Scene, NPCs here -> Add Character), and world actions tried before the referee each turn.
- Owner tried `play` 19 Nov: "That works great, it's like 1981 all over again!". Merge not yet asked for.
- PARKED (owner, 19 Nov: "build, test and set aside" later): Raon-1-nano NPC model (KRAFTON). LM Studio
  lists it but cannot load it (architecture too new). Plan: build krafton-ai/llama.cpp branch
  `raon-1-nano` in WSL (owner runs `sudo apt install -y build-essential cmake` first; CPU build, CUDA
  later), serve the GGUF from C:\Users\Private\.cache\lm-studio\models\KRAFTON\Raon-1-nano-gguf
  (2 GB, never read it) on :8000 with --ctx-size 8192, thinking off/capped; then a Voices base URL in
  ref + lib_ttrpg_lm. Or wait for upstream PR ggml-org/llama.cpp#32200. Notes:
  LIB_LLMOUT/Read/LIB_TTRPG/About_Raon_LLM.txt. vLLM is out (server GPU).
- NOTE: `python3 ref/ttrpg_ref.py test` is the LIVE test: it loads gemma-2-2b. Do not use it as a quick check.


Sunday, November 15, 2026, written by Opus at the owner's request before a /clear.
Branch `ttrpg-studio-1` (LIB_TTRPG and LIB_TEST); nothing merged; all models unloaded.

## State
- The stack `TTRPG_Studio.livecode` is built (copy in LIB_TEST, README section 4). Headless tests all
  pass (`livecode/tests/`, see `livecode/README.md`). **The window has never been opened on a screen.**
  It reaches LM Studio through tsNet, which is untested (headless runs used curl.exe).
- Skills drive the play (owner, 15 Nov: "I use Skill X" moves the plot): 18 D&D skills; a named skill
  is honoured, opens its own clue or turns up a lead; social skills press secrets; skill buttons in the window.
- Self-play (`python3 ref/ttrpg_ref.py selfplay`): a model plays the player. Results in `TUNING.md`.
- **The owner played the terminal version** (11:19, 6 turns, "That was great!"):
  `work/data/scenes/2026-11-15_111910_flooded_crypt.json` and `work/data/logs/2026-11-15_111906_session.jsonl`.

## To do next, in order
1. **Named skills as questions.** "Does my Religion skill give me...", "What does my insight tell me..."
   are not seen as naming the skill (only "I use / using / with X" are). Count "my X", "an X check",
   "X roll". Python first (`declared_skill`), then `TTRPG.DeclaredSkill`, then add vectors.
2. **The owner opens the window** (first real run): watch for "thinking..." hanging (tsNet), the look
   (scrollbars, colours), the dialogs. Ask him how it went; read the Data folder logs.
3. **An ending beat**: once the clues are found and the story has moved on, the code tells the narrator
   to bring the truth into view, then End Scene. Ask the owner first: it changes how a scene plays.
4. Narrator leftovers: "You see:", "The player sees...", "Wren ... she" -> clean in code.
5. The self-play player uses only its best skills: tell it which skills it has not tried yet.
6. The risky-verb list matches "run my fingers" (drop "run" unless "run to / away / from").
7. DONE 19 Nov: the old studio's world / item code (see the top).

## Machine limits (owner)
gemma-2-2b alone is comfortable. qwen-7B + a 2B pushed memory to 95%. 13B is out of reach. Ask before loading.

## Player client (OXT-Beyond, 15 Nov)
`client/livecode/client_main.livecodescript` is the code; dev stacks `client/TTRPG_Client_dev_<stamp>.oxtstack`
(rule: memory xtalk-dev-stack-workflow). Session log: `~/projects/OXT-BEYOND/sessions/TTRPG_Client_log.txt`.
Owner's ideas, to build when play shows the need: a scene strip at the top right (NPCs, monsters, treasure,
16x16 faces like the party); companions/familiars beside their hero. The Studio should set the scene mode
(explore/combat/talk) and fill the DM text.
