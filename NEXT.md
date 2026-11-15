# LIB_TTRPG: where we left off (come back here)

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
7. Later (OPUS_BUILD step 9): carry the old studio's world / item code.

## Machine limits (owner)
gemma-2-2b alone is comfortable. qwen-7B + a 2B pushed memory to 95%. 13B is out of reach. Ask before loading.
