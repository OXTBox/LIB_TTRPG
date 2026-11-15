# TTRPG Studio, iteration 1: the design

Sunday, November 15, 2026. Fable 5.2. Tested with `ref/ttrpg_ref.py` against LM Studio
(gemma-2-2b-it-abliterated alone; gemma + lfm3-omni-2b together). The stack is a port of that file.

## The one idea

**The code holds the secrets; the models only word things.**

A 2B model told "here are four secrets, reveal them slowly" reveals all four at once. So the
narrator is never shown them. Each turn the code decides what happens (which clue, did the roll
succeed), and the narrator gets one line, RESULT, to put into words. It cannot dump what it was
never given. "One clue, not all of them" is a property of the program, not a hope about the model.

## Who does what

| Part | Who | Sees |
|---|---|---|
| Scene maker | DM model, once a scene, answers as a form (JSON schema) | the one-line idea |
| Referee | DM model, every turn, answers as a form of 4 fixed choices | the player's line, character names, the *names of the spots* where clues are (never the clues) |
| Ruling | code | everything: picks the clue, rolls the die |
| Narrator | DM model | place, who is here, summary, clues already found, last 3 exchanges, RESULT |
| A character | Voices model | its own persona (look, voice, wants, secret), place, last 3 exchanges, the player's line |
| Summary | DM model, every 4 turns | the old exchanges to fold away |

One model can do all of it (Voices = "Same as DM"). Forms use LM Studio's `response_format`
`json_schema`, which forces valid JSON even from a 2B model: no parsing of free text for decisions.

## A turn

```
player types a line
  -> REFEREE (form): kind = talk / look / do; who; spot; skill
  -> RULING (code)
       talk: that character answers. If the player presses for the truth with Insight or
             Persuasion: roll against 13; on success the character is told to let its secret slip.
       look: a clue is open?  spot matched -> that clue, roll against 8
                              no spot matched -> the NEXT open clue, roll against 11
                              (the Lazy DM way: the clue turns up wherever the player looks)
             success -> clue found; RESULT = "discovers exactly this, and nothing more: <fact>"
             failure -> RESULT = "finds nothing new, hint to look closer"; that clue is 3 easier next time
             no clues left -> RESULT = "nothing more hidden here"
       do:   risky verb (climb, force, sneak...) -> roll against 10; else it just works
  -> talk: VOICES model speaks as the character. The narrator is not called at all.
     else: NARRATOR words the RESULT in 2 or 3 sentences.
  -> shown: the roll line, the reply, and after a found clue the clue itself, word for word
     (after a successful press, the character's secret, word for word)
  -> every 4 turns: fold exchanges older than the last 3 into the summary
```

Roll = d20 + the player character's skill bonus. Eight skills in iteration 1: Perception,
Investigation, Arcana, History, Insight, Athletics, Stealth, Persuasion.

**Regenerate** keeps the ruling (same roll, same clue) and only asks for new words. Otherwise a
player could re-roll a failure by pressing the key.

## Small-model care (all of it measured, not guessed)

| Care | How |
|---|---|
| Short prompts | each call under about 350 tokens in; context loaded at 4096 |
| Low reply limits | narrator 200, voice 120, referee 60, summary 120, scene form 500 |
| Cut-off replies | a reply that hits the limit is trimmed back to its last whole sentence |
| No option lists | the prompt forbids them AND the code cuts them: bullets, numbered lines, "What do you do?", any sentence ending in "?" |
| Markdown, "DM:" prefixes, stage directions | stripped in code (`clean_narration`, `clean_speech`) |
| Opening of 3 to 5 sentences | asked for 4; trimmed to 5; fewer than 3 = ask again (3 tries), then the plain facts |
| Forgetting | hidden notes live in the scene file; summary + last 3 exchanges are re-sent every call; no chat history is kept in the model |
| System role refused (some Gemma templates) | on an error reply the call is repeated once with system + user merged; remembered per model |
| Speed | gemma 2B here: 0.4 to 5 s a call, a whole turn 2 to 6 s |

## Data (JSON, one file an object, through LIB_DATA)

Folder `Games/TTRPG/` in the Data folder; logs in `Work/Logs/TTRPG/`.

**Character** `characters/<id>.json` (constant ones only; scene characters live inside their scene)

| Key | |
|---|---|
| `id`, `name`, `kind` | `constant` or `scene` |
| `look`, `voice`, `wants`, `secret` | one phrase or sentence each; the persona prompt is built from these four |
| `player` | true on the player's own character (one) |
| `skills` | player only: skill -> bonus |

**Scene** `scenes/<date>_<time>_<title>.json`

| Key | |
|---|---|
| `idea`, `title`, `place`, `happening`, `wrong` | the visible facts (the opening is written from these) |
| `truth` | hidden: what is really going on |
| `clues` | hidden: list of `id`, `where` (the spot), `skill`, `fact`, `found`, `tries` |
| `characters` | full copies of everyone present (constant ones copied in, scene ones made here) |
| `opening`, `summary`, `folded` | narration so far; `folded` = how many turns are inside the summary |
| `turns` | list of `action`, `ruling`, `speaker`, `reply` |
| `ended` | set by End Scene |

End Scene: every `kind = scene` character is dropped unless the owner ticks it; ticked ones are
saved as constant. Constant characters join every new scene (iteration 1: all of them; a tick
list is the obvious next step).

**Session log** `<date>_<time>_session.jsonl`: one line a model call: time, role, model, system,
user, reply, finish, error, seconds. This is the tuning record.

## Models

- List: `GET /api/v0/models` gives `id`, `type` (`llm`, `vlm`, `embeddings`) and `state`
  (`loaded` / `not-loaded`). Show llm and vlm. (`/v1/models` has no state.)
- Load / unload: `lms load <id> --identifier <id> --context-length 4096 --ttl 1800 --yes`,
  `lms unload <id>`; then read the state back from `/api/v0/models`: that, not the command's
  text, says whether it worked.
- Server: if the list call gets no answer, run `lms server start --port 1234`; still nothing ->
  tell the owner: "open LM Studio, Developer tab, Start Server".
- Two models: load DM, then Voices. Voices fails -> Voices = DM, and the status line says so
  (tested with a model name that does not exist; a real out-of-memory takes the same path).
- Closing the stack unloads what the stack loaded (never a model it found already loaded: that
  may be Spark at work).

## Known weak spots (for the tuning pass)

1. A 2B model does not always word the clue clearly; that is why the clue is also shown word for word.
2. On a successful Persuasion the character is *told* to let the secret slip, and gemma 2B often
   still does not. **Fixed (15 Nov, TUNING.md):** the code now shows the secret word for word as a
   `[secret]` line, the way found clues are shown, and marks the character `revealed` (the narrator
   may know it from then on). Putting the secret in the user message was tried and did not help.
3. Repeating the same action can get nearly the same narration back (it is in "Just before").
4. The scene maker's clues do not always point at the truth; fine for fun, weak for mysteries.
   A 7B model as DM (qwen2.5-7b) with a 2B for Voices is the pairing to try.
5. Characters do not know the scene's clues or truth, only their own secret.

## Not in iteration 1

Maps, combat, inventories, PROMPT & GLAZE hook-up, audio. The harvested world / item code
(`XTJSON/batch/TTRPG_STUDIO_020920229AM`) is not carried into this repo yet: see `OPUS_BUILD.md` step 9.
