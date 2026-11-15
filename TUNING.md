# TTRPG Studio: the tuning pass (iteration 1)

Sunday, November 15, 2026. Opus 5.5, from OPUS_BUILD.md step 7. Measured with `ref/tune.py`
(A against B, real models, 6 to 8 tries each; raw output in `work/tune_*.txt`, every call in
`work/tune/<dm>/logs/`). The numbers are rough: small samples, crude word-overlap scores. I read
the replies themselves before drawing anything from a number.

## The machine

| Pairing | Fits? |
|---|---|
| gemma-2-2b alone | yes; a whole turn 1 to 3 s |
| gemma-2-2b + lfm3-omni-2b | yes |
| qwen2.5-7b-instruct-1m (DM) + lfm3-omni-2b (Voices) | only just: memory at 95% (owner, 15 Nov). Scene 16.5 s, narration 4.3 s, voice 0.3 s |
| llama2-13b-psyfighter2 as Voices | **no**: "way over my computer's ability" (owner). Not tried, not to be suggested again |

## The weak spots (DESIGN.md)

| # | Spot | What was tried | Result | Done |
|---|---|---|---|---|
| 1 | The narrator blurs the clue | measured the share of the clue's words in the narration | gemma 0.26, qwen 0.33 | nothing new: the clue is already shown word for word under the narration, which covers it |
| 2 | A pressed character keeps its secret | A: the guard line in the system prompt (as was). B: + "Say this now, in your own words: <secret>" in the user message | gemma as Voices: **0 of 12** replies said it, A or B. lfm3: A gave it away in most replies (the score undercounts paraphrase), B no better. qwen DM run, lfm3 voices: A 1/6, B 2/6 | **code fix**: on a successful press the code shows the secret word for word, as a `[secret]` line, the way found clues are shown; the character is marked `revealed` and the narrator may know it from then on. Prompts unchanged. In the reference and the stack, tested (stub / mock) |
| 3 | The same action gets the same narration | A as is; B: + "Say something new: do not reuse the wording of Just before"; C: the code asks again at temperature 1.1 when the overlap is over 0.6 | noisy. gemma: A 0.61 / B 0.57 (with three near-copies at 0.95 to 1.00) in one run, A 0.62 / B 0.40 / C 0.64 in another. qwen: A 0.53 / B 0.34 / C 0.40 | **no change**. B helps on average but sometimes makes the model copy outright (pointing a small model at text invites copying). Worth a bigger sample before adopting it |
| 4 | The scene maker's clues do not point at the truth | gemma against qwen as DM, 4 ideas each, read by me | qwen is clearly better: short concrete spots ("altar", "the lens"), skills that fit the spot, several clues that do point at the truth ("the keeper's reflection is absent" for a cursed lighthouse). gemma: clues in the first person ("I can feel..."), long spots, Athletics / Stealth for looking | **no code change.** The better pairing costs memory the machine barely has |

## Also seen

- The system-role fallback never fired: LM Studio's gemma-2 template now accepts a system message.
  The code keeps the fallback (it costs nothing).
- `clean_speech` lets narration through when it is not in asterisks: gemma writes
  `It's safe here, Elowen whispers, ...`. A next fix: drop clauses like `<Name> (whispers|says|...)`.
- qwen's openings often name the player's position plainly and keep to 4 sentences; gemma sometimes
  writes the NPC as the subject ("Eliana stands at the edge...").

## Suggestions (for the owner)

1. Play with **gemma-2-2b alone** (fast, fits). If the scenes feel thin, try **qwen-7B as DM with
   Voices = Same as DM** (one model in memory, not two). That pairing has not been measured yet.
2. A later option, if wanted: a "Scene maker" model choice. qwen makes the scene (once, about 16 s),
   then is unloaded and gemma plays the turns. That needs a load/unload in the middle of New Scene.
