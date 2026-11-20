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
| `livecode/` | the stack's scripts and builder; `livecode/tests/` the headless tests |
| `TTRPG_Studio.livecode` | the built stack |
| `TUNING.md` | what was measured with real models, and what changed |
| `ref/tune.py` | the measuring harness for the weak spots |

## Play it in the window

Open `TTRPG_Studio.livecode` (here, or the copy in `LIB_TEST/`). Pick a DM model on the left,
press Load, press New Scene, type an idea, then type what you do. Esc pauses (developer options);
Ctrl+R regenerates. Closing the window unloads the models it loaded. The About card says the rest.
Rebuild after editing a script: `start using stack ".../livecode/build_studio.livecodescript"`,
then `Build.Studio ".../LIB_TTRPG"`.

Status (15 Nov 2026): the terminal engine and the stack's engine both pass the owner's test steps 2 to
6 (gemma-2-2b alone; gemma + lfm3-omni-2b; a Voices model that will not load falls back to one).
The stack's engine was tested headless (`livecode/tests/`); the window itself has not been seen on a
screen yet. Tuning results: `TUNING.md`.

## Licence

GPL-3.0 (see `LICENSE`), because the xTalk work here is built on the GPL-licensed LiveCode Community 9 engine. Copyright (c) 2026 xAction.

The Python files (`.py`) and other material that is not xTalk are also offered under the MIT licence, Copyright (c) 2026 xAction: you may use them under either licence.
