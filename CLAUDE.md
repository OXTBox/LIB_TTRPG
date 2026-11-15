# LIB_TTRPG notes for AI models

- The engine's spec is `ref/ttrpg_ref.py`; the stack is a port. Change behaviour there first, run
  `python3 ref/ttrpg_ref.py test`, then carry it to `livecode/`.
- Rule that must survive every change: unrevealed clues, the truth and other characters' secrets
  are never put in a narrator prompt. The code picks; the model words.
- Prompts are `prompts/*.txt` with `{blanks}`; never inline a prompt in code.
- Ask the owner before loading models while he is at the machine; unload when done
  (`python3 ref/ttrpg_ref.py unload`). `spark-x2.6-4b` is Spark's: ask before using it.
- From WSL the server is reached through `curl.exe` (the tool does this itself). Any subprocess
  that runs a Windows .exe must get `stdin=DEVNULL`, or it eats the terminal's input.
- Test data goes in `work/` (git-ignored). The stack saves through LIB_DATA (`Games/TTRPG`).
