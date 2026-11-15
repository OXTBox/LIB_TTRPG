# LIB_TTRPG: TTRPG Studio

Sunday, November 15, 2026. A small role-playing table run by local models (LM Studio): you pick
one or two light models, give a one-line scene idea, and play by typing what your character does.
The narrator plays a **Lazy DM**: a short opening, then one clue at a time, only when you look.
Later it becomes the talking back end of PROMPT & GLAZE.

## Play it now (terminal, before the stack exists)

```
cd ~/projects/LIB_TTRPG
python3 ref/ttrpg_ref.py play "a flooded crypt under a chapel"
python3 ref/ttrpg_ref.py play "a toll bridge run by goblins" --voices lfm3-omni-2b
python3 ref/ttrpg_ref.py unload          # when you finish
```

Type what you do. `/r` says the last answer again in other words, `/npc a talking rat` adds a
character, `/who`, `/notes` (peek at the DM's hidden notes), `/end`, `/quit`.

## What is here

| File | What |
|---|---|
| `DESIGN.md` | how it works: data, the turn, the prompts, why small models cope |
| `OPUS_BUILD.md` | the build list for the LiveCode stack (for Opus) |
| `prompts/*.txt` | every prompt, as plain text with `{blanks}`; the terminal version and the stack share them |
| `ref/ttrpg_ref.py` | the engine, reference version: `models`, `load`, `unload`, `play`, `test` |
| `ref/vectors.json` | text-cleaning examples the stack's port must reproduce |
| `livecode/` | the stack's scripts and builder (to be built: `OPUS_BUILD.md`) |

Status: the engine passes the owner's test steps 2 to 6 from the terminal (gemma-2-2b alone, and
gemma + lfm3-omni-2b together). The stack (window) is not built yet.
