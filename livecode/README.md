# livecode/: the TTRPG Studio stack's scripts

| File | Holds |
|---|---|
| `lib_ttrpg_lm.livecodescript` | LM Studio: models, load / unload (`lms`), one async chat call (tsNet; curl.exe when headless in WSL), forms, the session log; the JSON reader / writer |
| `lib_ttrpg.livecodescript` | the engine: characters, scene, ruling, turn, summary, text cleaning, `TTRPG.SelfTest`, `TTRPG.OwnerTest` |
| `studio_stack.livecodescript` | the stack script: UI handlers only |
| `build_studio.livecodescript` | `Build.Studio <LIB_TTRPG folder>` makes `../TTRPG_Studio.livecode` |

## Tests (no window: the LiveCode 9.6.3 server in WSL)

```
R=~/projects/LIB_BIT/editor/tests/run_headless.py
python3 -I $R tests/lc_selftest.txt     # text helpers vs ref/vectors.json, JSON round trips
python3 -I $R tests/lc_mock_test.txt    # owner's test with a mock model + the secrecy checks
python3 -I $R tests/lc_ui_test.txt      # builds the stack, drives its handlers (mock model, temp Data folder)
python3 -I $R tests/lc_live_test.txt    # REAL models: ask the owner first; unload after
```

The server has no jsonImport / jsonExport, hence the library's own `TTRPG.JSON.Parse` / `Export`.
Not tested headless: the look of the window, the mouse, tsNet (the window's transport), `ask` / `answer` dialogs.
