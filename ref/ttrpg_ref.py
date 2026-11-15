#!/usr/bin/env python3
"""ttrpg_ref: the TTRPG Studio engine, reference version (LIB_TTRPG, iteration 1).

The LiveCode stack is a port of this file: same data, same prompts (../prompts/*.txt), same
steps. Tune here first (fast), then carry the change over.

    python3 ttrpg_ref.py models                          what LM Studio has, and what is loaded
    python3 ttrpg_ref.py load  DM [VOICES]               load one or two models (falls back to one)
    python3 ttrpg_ref.py unload                          unload what this tool loaded
    python3 ttrpg_ref.py play  "a flooded crypt under a chapel" [--dm M] [--voices M]
    python3 ttrpg_ref.py test  [--dm M] [--voices M]     the owner's test, steps 2 to 4 and 6, scripted
    python3 ttrpg_ref.py selfplay ["idea"] [--player M] [--turns N]   a model plays the player; transcript + counts

In play: type what your character does. /r regenerate the last answer, /npc <one line> add a
scene character, /who, /notes (the DM's hidden notes), /end (end the scene), /quit.

The rule that makes the Lazy DM work with small models: THE CODE HOLDS THE SECRETS. The
narrator model is only ever shown the one clue it must give now, so it cannot dump the rest.
"""
import argparse, json, os, random, re, shutil, subprocess, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROMPTS = os.path.join(HERE, '..', 'prompts')
BASE = 'http://127.0.0.1:1234'
WSL = bool(shutil.which('curl.exe')) and os.path.isdir('/mnt/c')
SKILLS = ['Perception', 'Investigation', 'Arcana', 'History', 'Insight', 'Athletics', 'Stealth', 'Persuasion']
TALK_SKILLS = ('Insight', 'Persuasion')
DEFAULT_PLAYER = {'id': 'player', 'name': 'Wren', 'kind': 'constant', 'player': True,
                  'look': 'a wiry traveller in a patched grey cloak', 'voice': 'dry and curious',
                  'wants': 'to know what happened here', 'secret': '',
                  'skills': {'Perception': 2, 'Investigation': 3, 'Arcana': 3, 'History': 1,
                             'Insight': 1, 'Athletics': 0, 'Stealth': 2, 'Persuasion': 1}}
MAX_TOKENS = {'dm': 200, 'voice': 120, 'referee': 60, 'make': 500, 'summary': 120, 'player': 60}
KEEP_TURNS = 3          # exchanges shown to the models word for word
SUMMARY_EVERY = 4       # fold older exchanges into the summary this often


# ---------------------------------------------------------------- LM Studio
def http(path, body=None, timeout=300):
    """-> (parsed JSON or None, error text). From WSL the server is reached through curl.exe."""
    data = json.dumps(body).encode('utf-8') if body is not None else None
    try:
        if WSL:
            cmd = ['curl.exe', '-sS', '-m', str(timeout), BASE + path]
            if data is not None:
                cmd += ['-H', 'Content-Type: application/json', '--data-binary', '@-']
            r = subprocess.run(cmd, capture_output=True, cwd='/mnt/c', **({'input': data} if data is not None else {'stdin': subprocess.DEVNULL}))
            raw = r.stdout.decode('utf-8', 'replace')
            if not raw.strip():
                return None, r.stderr.decode('utf-8', 'replace').strip() or 'no answer'
        else:
            req = urllib.request.Request(BASE + path, data=data, headers={'Content-Type': 'application/json'})
            raw = urllib.request.urlopen(req, timeout=timeout).read().decode('utf-8', 'replace')
        return json.loads(raw), ''
    except Exception as e:
        return None, str(e)


def lms(*args):
    try:
        if WSL:
            home = subprocess.run(['cmd.exe', '/c', 'echo %USERPROFILE%'], capture_output=True, text=True, stdin=subprocess.DEVNULL,
                                  cwd='/mnt/c').stdout.strip()
            exe = subprocess.run(['wslpath', home], capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout.strip() \
                + '/.cache/lm-studio/bin/lms.exe'
            cwd = '/mnt/c'
        else:
            exe, cwd = os.path.expanduser('~/.cache/lm-studio/bin/lms'), None
        r = subprocess.run([exe] + list(args), capture_output=True, text=True, cwd=cwd, timeout=300, stdin=subprocess.DEVNULL,
                           encoding='utf-8', errors='replace')
        return re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', r.stdout + r.stderr)
    except Exception as e:
        return 'lms failed: %s' % e


def models():
    """-> list of (id, state, type); empty when the server is not running."""
    d, _ = http('/api/v0/models', timeout=10)
    return [(m['id'], m.get('state', '?'), m.get('type', '?')) for m in (d or {}).get('data', [])]


def load_one(model):
    """-> (ok, message)"""
    if any(i == model and s == 'loaded' for i, s, _ in models()):
        return True, 'already loaded'
    out = lms('load', model, '--identifier', model, '--context-length', '4096', '--ttl', '1800', '--yes')
    ok = any(i == model and s == 'loaded' for i, s, _ in models())
    lines = [l for l in re.split(r'[\r\n]+', out) if l.strip()]
    last = [l for l in lines if re.search(r'error|not found|cannot|memory|failed', l, re.I)][:1] or lines[-1:] or ['']
    return ok, ('loaded' if ok else 'failed: ' + last[0].strip()[:200])


def load_models(dm, voices=None):
    """Load the DM model, then the Voices model. -> (dm, voices, status line).
    If the second does not load (memory), fall back to one model and say so."""
    if not models():
        lms('server', 'start', '--port', '1234')
        if not models():
            return None, None, 'LM Studio server is not running (open LM Studio, Developer tab, Start Server)'
    ok, msg = load_one(dm)
    if not ok:
        return None, None, 'DM model %s %s' % (dm, msg)
    if not voices or voices == dm:
        return dm, dm, 'loaded: %s (DM and Voices)' % dm
    ok, msg = load_one(voices)
    if not ok:
        return dm, dm, 'loaded: %s. Voices model %s %s, so %s plays the voices too' % (dm, voices, msg, dm)
    return dm, voices, 'loaded: DM %s, Voices %s' % (dm, voices)


def unload_models(names):
    for n in dict.fromkeys(n for n in names if n):
        lms('unload', n)


class Studio:
    """One sitting: the models, the data folder, the session log."""

    def __init__(self, data_dir, dm, voices=None):
        self.dir = data_dir
        for sub in ('characters', 'scenes', 'logs'):
            os.makedirs(os.path.join(data_dir, sub), exist_ok=True)
        self.dm, self.voices = dm, voices or dm
        self.log_path = os.path.join(data_dir, 'logs', time.strftime('%Y-%m-%d_%H%M%S') + '_session.jsonl')
        self.no_system = set()     # models whose template refuses a system message
        self.calls = []            # (role, model) of every call, for tests

    # ------------------------------------------------------------ one model call
    def chat(self, role, model, system, user, schema=None, temperature=0.8):
        """role = dm / voice / referee / make / summary. -> text ('' on failure). Every call is logged."""
        def body(merge):
            msgs = [{'role': 'user', 'content': system + '\n\n' + user}] if merge else \
                   [{'role': 'system', 'content': system}, {'role': 'user', 'content': user}]
            b = {'model': model, 'messages': msgs, 'temperature': temperature,
                 'max_tokens': MAX_TOKENS[role], 'stream': False}
            if schema:
                b['response_format'] = {'type': 'json_schema',
                                        'json_schema': {'name': role, 'strict': True, 'schema': schema}}
            return b
        t0 = time.time()
        d, err = http('/v1/chat/completions', body(model in self.no_system))
        if d is not None and 'choices' not in d and model not in self.no_system:
            self.no_system.add(model)                    # e.g. Gemma: "System role not supported"
            first = d
            d, err = http('/v1/chat/completions', body(True))
            if d is None or 'choices' not in d:
                self.no_system.discard(model)
                d = first
        text, finish = '', ''
        if d and 'choices' in d:
            c = d['choices'][0]
            text = re.sub(r'<think>.*?</think>', '', c['message'].get('content') or '', flags=re.S).strip()
            finish = c.get('finish_reason') or ''
        else:
            err = err or json.dumps(d)[:300]
        self.calls.append((role, model))
        with open(self.log_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'time': time.strftime('%H:%M:%S'), 'role': role, 'model': model,
                                'system': system, 'user': user, 'reply': text, 'finish': finish,
                                'error': err, 'seconds': round(time.time() - t0, 1)}, ensure_ascii=False) + '\n')
        if finish == 'length' and not schema:
            text = whole_sentences(text)
        return text

    def form(self, role, model, system, user, schema, temperature=0.7):
        """A call that must come back as JSON matching schema; one retry. -> dict or None"""
        for _ in range(2):
            try:
                d = json.loads(self.chat(role, model, system, user, schema, temperature))
                if isinstance(d, dict):
                    return d
            except ValueError:
                pass
        return None

    # ------------------------------------------------------------ characters
    def constants(self):
        out = []
        folder = os.path.join(self.dir, 'characters')
        for n in sorted(os.listdir(folder)):
            if n.endswith('.json'):
                with open(os.path.join(folder, n), encoding='utf-8') as f:
                    out.append(json.load(f))
        return out

    def save_character(self, ch):
        ch['kind'] = 'constant'
        ch['id'] = ch.get('id') or slug(ch['name'])
        with open(os.path.join(self.dir, 'characters', ch['id'] + '.json'), 'w', encoding='utf-8') as f:
            json.dump(ch, f, indent=1, ensure_ascii=False)

    def player(self):
        for ch in self.constants():
            if ch.get('player'):
                return ch
        self.save_character(dict(DEFAULT_PLAYER))
        return dict(DEFAULT_PLAYER)

    def make_character(self, scene, ask):
        d = self.form('make', self.dm, fill('character_make', place=scene['place'], ask=ask), 'Fill in the form.',
                      CHARACTER_SCHEMA, 0.9)
        if not d:
            return None
        d.update(id=slug(d['name']), kind='scene')
        scene['characters'].append(d)
        return d

    # ------------------------------------------------------------ a scene
    def new_scene(self, idea, with_characters=()):
        """idea (one line) -> scene dict with its hidden notes, its opening already narrated."""
        d = self.form('make', self.dm, fill('scene_make', idea=idea, nclues=4), 'Fill in the form.', SCENE_SCHEMA, 0.9)
        if not d:
            d = {'title': idea[:40], 'truth': 'Someone was here moments ago and left in a hurry.',
                 'place': 'You stand in ' + idea + '.', 'happening': 'It is quiet, too quiet.',
                 'wrong': 'Something here has been disturbed.', 'npc': None,
                 'clues': [{'where': 'the floor', 'skill': 'Perception', 'fact': 'Fresh wet footprints lead away.'},
                           {'where': 'the walls', 'skill': 'Investigation', 'fact': 'A mark was scratched here in haste.'}]}
        scene = {'idea': idea, 'title': d['title'], 'truth': d['truth'], 'place': d['place'],
                 'happening': d['happening'], 'wrong': d['wrong'], 'summary': '', 'turns': [], 'folded': 0,
                 'clues': [], 'characters': [dict(c) for c in with_characters if not c.get('player')],
                 'file': time.strftime('%Y-%m-%d_%H%M%S_') + slug(d['title']) + '.json'}
        for i, c in enumerate(d['clues'], 1):
            scene['clues'].append({'id': i, 'where': c['where'], 'skill': c['skill'], 'fact': c['fact'],
                                   'found': False, 'tries': 0})
        if d.get('npc'):
            npc = dict(d['npc'], kind='scene')
            npc['id'] = slug(npc['name'])
            scene['characters'].append(npc)
        self.open_scene(scene)
        return scene

    def open_scene(self, scene):
        p = self.player()
        for _ in range(3):
            text = clean_narration(self.chat('dm', self.dm, fill('dm_open'), fill(
                'dm_open_user', place=scene['place'], happening=scene['happening'], who=who_line(scene),
                wrong=scene['wrong'], player=p['look']), temperature=0.7), 5)
            if len(sentences(text)) >= 3:
                break
        if len(sentences(text)) < 3:                        # the model would not: say the facts plainly
            text = ' '.join([scene['place'], scene['happening'], scene['wrong']])
        scene['opening'] = text
        self.save_scene(scene)
        return text

    def save_scene(self, scene):
        with open(os.path.join(self.dir, 'scenes', scene['file']), 'w', encoding='utf-8') as f:
            json.dump(scene, f, indent=1, ensure_ascii=False)

    def end_scene(self, scene, keep=()):
        """Scene characters are dropped, except the names in keep: those become constant."""
        for ch in scene['characters']:
            if ch.get('kind') == 'scene' and ch['name'] in keep:
                self.save_character(ch)
        scene['ended'] = True
        self.save_scene(scene)

    # ------------------------------------------------------------ one turn
    def turn(self, scene, action, redo=False):
        """The player's line -> list of (speaker, text) to show. redo = regenerate the last answer
        with the same ruling (same roll, same clue): only the wording changes."""
        p = self.player()
        if redo and scene['turns']:
            last = scene['turns'].pop()
            action, ruling = last['action'], last['ruling']
        else:
            ruling = self.rule(scene, p, action)
        shown = []
        if ruling.get('roll'):
            shown.append(('roll', ruling['roll']))
        recent = recent_text(scene, p['name'])
        if ruling['kind'] == 'talk':
            ch = next(c for c in scene['characters'] if c['id'] == ruling['who'])
            guard = 'The player has earned your trust or seen through you: let your secret slip now.' \
                if ruling.get('success') else 'Do not give your secret away; you may hint that you have one.'
            text = self.chat('voice', self.voices, fill('voice', guard=guard, **{
                k: ch.get(k, '') for k in ('name', 'look', 'voice', 'wants', 'secret')}), fill(
                'voice_user', place=scene['place'], recent=recent, player=p['name'], action=action), temperature=0.9)
            text = clean_speech(text, ch['name']) or '...'
            shown.append((ch['name'], text))
            if ruling.get('success') and ch.get('secret'):
                # small models rarely let it slip even when told to (TUNING.md, W2): the code shows it,
                # word for word, as it does a found clue; from now on it is known, not hidden
                ch['revealed'] = True
                shown.append(('secret', '%s: %s' % (ch['name'], ch['secret'])))
        else:
            known = ' '.join([c['fact'] for c in scene['clues'] if c['found'] and c['id'] != ruling.get('clue')] +
                             [c['secret'] for c in scene['characters'] if c.get('revealed')]) or 'nothing yet'
            text = clean_narration(self.chat('dm', self.dm, fill('dm_turn'), fill(
                'dm_turn_user', place=scene['place'], who=who_line(scene), summary=scene['summary'] or 'The scene has just begun.',
                known=known, recent=recent, player=p['name'], action=action, result=ruling['result'])), 4)
            if ruling.get('clue') and ruling.get('success'):
                fact = next(c['fact'] for c in scene['clues'] if c['id'] == ruling['clue'])
                shown.append(('DM', text or 'You find something.'))
                shown.append(('clue', fact))                 # the clue itself, word for word: small models blur it
            else:
                shown.append(('DM', text or 'Nothing changes.'))
        said = [x for x in shown if x[0] not in ('roll', 'clue', 'secret')][-1]
        scene['turns'].append({'action': action, 'ruling': ruling, 'speaker': said[0], 'reply': said[1]})
        self.fold(scene)
        self.save_scene(scene)
        return shown

    def rule(self, scene, p, action):
        """What happens, decided by code + one small referee call. The narrator only words it."""
        names = [c['name'] for c in scene['characters']]
        open_clues = [c for c in scene['clues'] if not c['found']]
        schema = {'type': 'object', 'properties': {
            'kind': {'type': 'string', 'enum': ['talk', 'look', 'do']},
            'who': {'type': 'string', 'enum': names + ['nobody']},
            'spot': {'type': 'string', 'enum': [str(c['id']) for c in open_clues] + ['none']},
            'skill': {'type': 'string', 'enum': SKILLS}},
            'required': ['kind', 'who', 'spot', 'skill']}
        spots = '\n'.join('%d: %s' % (c['id'], c['where']) for c in open_clues) or '(none)'
        r = self.form('referee', self.dm, fill('referee'), fill(
            'referee_user', names=', '.join(names) or '(nobody)', spots=spots, action=action), schema, 0.0) \
            or {'kind': 'do', 'who': 'nobody', 'spot': 'none', 'skill': 'Perception'}
        kind, skill = r['kind'], r['skill']
        named = [c for c in scene['characters'] if is_named(c['name'], action)]
        who = next((c for c in scene['characters'] if c['name'] == r['who']), None)
        if kind == 'talk' and not who:
            who = named[0] if named else (scene['characters'][0] if len(scene['characters']) == 1 else None)
        if kind != 'talk' and named and ('"' in action or '?' in action):
            kind, who = 'talk', named[0]                     # the referee missed plain speech to a named character
        if kind == 'talk' and not who:
            kind = 'do'
        bonus = int(p.get('skills', {}).get(skill, 0))
        ruling = {'kind': kind, 'skill': skill}

        def roll(dc):
            d = random.randint(1, 20)
            ok = d + bonus >= dc
            ruling.update(success=ok, roll='%s: %d %s %d = %d against %d, %s' % (
                skill, d, '+' if bonus >= 0 else '-', abs(bonus), d + bonus, dc, 'success' if ok else 'failure'))
            return ok

        if kind == 'talk':
            ruling['who'] = who['id']
            if skill in TALK_SKILLS and who.get('secret') and re.search(
                    r'persua|convinc|plead|press|insist|trust|lying|lie\b|truth|hiding|secret|insight|read (him|her|them)', action, re.I):
                roll(13)
            ruling['result'] = ''
        elif kind == 'look' and open_clues:
            clue = next((c for c in open_clues if str(c['id']) == r['spot']), None)
            matched = clue is not None
            clue = clue or open_clues[0]                     # Lazy DM: the next clue turns up where the player looks
            dc = max(5, (8 if matched else 11) - 3 * clue['tries'])
            if roll(dc):
                clue['found'] = True
                ruling.update(clue=clue['id'], result='The player discovers exactly this, and nothing more: ' + clue['fact'] + (
                    '' if matched else ' (Place this discovery where the player is looking.)'))
            else:
                clue['tries'] += 1
                ruling['result'] = 'The player finds nothing new this time. Say what they see instead; hint that a closer or different look might help.'
        elif kind == 'look':
            ruling['result'] = 'There is nothing more hidden here. The player sees only what is already known.'
        else:
            ok = roll(10) if re.search(r'\b(try|attempt|climb|jump|force|break|sneak|swim|lift|push|pull|pick|dodge|run|grab|throw|attack|hit|kick)', action, re.I) else True
            ruling['result'] = 'The action works; describe its plain, immediate effect.' if ok else \
                'The action fails; describe the small setback. Nobody is badly hurt.'
        return ruling

    def fold(self, scene):
        """Rolling summary: exchanges older than the last KEEP_TURNS are folded into scene['summary']."""
        old = len(scene['turns']) - KEEP_TURNS
        if old - scene['folded'] < SUMMARY_EVERY:
            return
        p = self.player()['name']
        notes = scene['summary'] + '\n' + '\n'.join(
            '%s: %s\n%s: %s' % (p, t['action'], t['speaker'], t['reply']) for t in scene['turns'][scene['folded']:old])
        text = self.chat('summary', self.dm, fill('summary'), notes.strip(), temperature=0.2)
        if text:
            scene['summary'], scene['folded'] = ' '.join(text.split()), old


# ---------------------------------------------------------------- text helpers
CHARACTER_PROPS = {k: {'type': 'string'} for k in ('name', 'look', 'voice', 'wants', 'secret')}
CHARACTER_SCHEMA = {'type': 'object', 'properties': CHARACTER_PROPS, 'required': list(CHARACTER_PROPS)}
SCENE_SCHEMA = {'type': 'object', 'properties': {
    'title': {'type': 'string'}, 'truth': {'type': 'string'}, 'place': {'type': 'string'},
    'happening': {'type': 'string'}, 'wrong': {'type': 'string'},
    'clues': {'type': 'array', 'minItems': 3, 'maxItems': 4, 'items': {'type': 'object', 'properties': {
        'where': {'type': 'string'}, 'skill': {'type': 'string', 'enum': SKILLS}, 'fact': {'type': 'string'}},
        'required': ['where', 'skill', 'fact']}},
    'npc': CHARACTER_SCHEMA},
    'required': ['title', 'truth', 'place', 'happening', 'wrong', 'clues', 'npc']}
_prompts = {}


def fill(name, /, **values):
    if name not in _prompts:
        with open(os.path.join(PROMPTS, name + '.txt'), encoding='utf-8') as f:
            _prompts[name] = f.read().strip()
    text = _prompts[name]
    for k, v in values.items():
        text = text.replace('{' + k + '}', str(v))
    return text


def slug(s):
    return re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')[:40] or 'x'


NAME_NOISE = ('the', 'a', 'an', 'of', 'old', 'young', 'elder', 'brother', 'sister', 'father', 'mother', 'sir', 'lady', 'lord', 'captain')


def name_words(name):
    """the words of a name a player would use for the character: 'Elder Elias' -> ['elias']"""
    words = [w for w in re.findall(r'[a-z]+', name.lower()) if w not in NAME_NOISE and len(w) > 2]
    return words or [name.lower()]


def is_named(name, action):
    said = re.findall(r'[a-z]+', action.lower())
    return any(w in said for w in name_words(name))


def who_line(scene):
    return '; '.join('%s (%s)' % (c['name'], c.get('look', '')) for c in scene['characters']) or 'nobody else'


def recent_text(scene, player):
    turns = scene['turns'][-KEEP_TURNS:]
    if not turns:
        return scene.get('opening', '')
    return ' '.join('%s: %s %s: %s' % (player, t['action'], t['speaker'], t['reply']) for t in turns)


def sentences(text):
    return [s.strip() for s in re.findall(r'.+?(?:[.!?]+["\')\]\u201d]*(?=\s|$)|$)', ' '.join(text.split())) if s.strip()]


def whole_sentences(text):
    """drop a cut-off last sentence"""
    m = list(re.finditer(r'[.!?]["\')\]]?(?=\s|$)', text))
    return text[:m[-1].end()] if m else text


OPTION_LINE = re.compile(r'^\s*(\d+[.)]|[-*•]|[A-Da-d][.)])\s+')
ASKING = re.compile(r'(what (do|will|would) you do|what now|what is your next|how do you (proceed|respond)|'
                    r'do you (want|wish|dare)|will you\b|you (can|could|may|might) (choose|either|try)|your options)', re.I)


def clean_narration(text, max_sentences):
    """The narrator's reply as shown: no markdown, no option lists, no closing question, a few sentences."""
    text = re.sub(r'[*_#`]+', '', text)
    text = re.sub(r'^\s*(DM|Narrator|RESULT|Narration)\s*:\s*', '', text, flags=re.I)
    keep = []
    for line in text.splitlines():
        if OPTION_LINE.match(line):
            break                                           # a list of choices: stop before it
        keep.append(line.strip())
    out = []
    for s in sentences(' '.join(l for l in keep if l)):
        if ASKING.search(s) or s.rstrip('"\u201d').endswith('?'):
            continue
        out.append(s)
    return ' '.join(out[:max_sentences]).strip()


def clean_speech(text, name):
    """A character's reply as shown: their words only."""
    text = re.sub(r'[*_#`]+[^*_#`\n]*[*_#`]+', ' ', text) if re.search(r'\*[^*\n]+\*', text) else text
    text = re.sub(r'\([^)]*\)', ' ', text)
    text = re.sub(r'^\s*%s\s*((says|replies|speaks|answers)( aloud)?)?\s*[:,]\s*' % re.escape(name), '', text.strip(), flags=re.I)
    text = ' '.join(re.sub(r'["\u201c\u201d]', '', text).split())
    return ' '.join(sentences(text)[:3])


# ---------------------------------------------------------------- command line
def show(lines):
    for who, text in lines:
        print(('   [%s]' % text) if who == 'roll' else ('   [%s: %s]' % (who, text)) if who in ('clue', 'secret') else '\n%s: %s' % (who, text))


def cmd_play(st, idea):
    constants = st.constants()
    print('Making the scene (%s)...' % st.dm)
    scene = st.new_scene(idea, constants)
    print('\n== %s ==\n\nDM: %s' % (scene['title'], scene['opening']))
    while True:
        try:
            line = input('\n> ').strip()
        except EOFError:
            line = '/quit'
        if not line:
            continue
        if line in ('/quit', '/end'):
            keep = input('Keep which scene characters (names, comma; Enter = none)? ').split(',') if line == '/end' and sys.stdin.isatty() else []
            st.end_scene(scene, [k.strip() for k in keep])
            break
        if line == '/notes':
            print('TRUTH:', scene['truth'])
            for c in scene['clues']:
                print(' %s %d. %s (%s): %s' % ('x' if c['found'] else ' ', c['id'], c['where'], c['skill'], c['fact']))
            for c in scene['characters']:
                print(' %s wants %s; hides %s%s' % (c['name'], c.get('wants'), c.get('secret'), ' (revealed)' if c.get('revealed') else ''))
            print('SUMMARY:', scene['summary'])
        elif line == '/who':
            for c in scene['characters']:
                print(' %s (%s): %s' % (c['name'], c['kind'], c.get('look')))
        elif line.startswith('/npc '):
            ch = st.make_character(scene, line[5:])
            print(' enters: %s, %s' % (ch['name'], ch['look']) if ch else ' (the model gave no character)')
        elif line == '/r':
            show(st.turn(scene, '', redo=True))
        else:
            show(st.turn(scene, line))
    print('\nlog: %s\nscene: %s' % (st.log_path, os.path.join(st.dir, 'scenes', scene['file'])))


def cmd_test(st):
    """The owner's test, steps 2, 3, 4 and 6, run by script. Prints PASS / FAIL lines."""
    fails = 0

    def check(name, ok, detail=''):
        nonlocal fails
        fails += 0 if ok else 1
        print('%s  %s  %s' % ('PASS' if ok else 'FAIL', name, detail))
    scene = st.new_scene('a flooded crypt under a chapel', st.constants())
    n = len(sentences(scene['opening']))
    print('\nOPENING: %s\n' % scene['opening'])
    check('2 opening is 3 to 5 sentences', 3 <= n <= 5, '(%d)' % n)
    check('2 opening has no options or questions', not ASKING.search(scene['opening']) and '?' not in scene['opening'])
    leaked = [c['id'] for c in scene['clues'] if c['fact'].lower() in scene['opening'].lower()]
    check('2 opening gives no clue away', not leaked, str(leaked))
    check('scene has 3+ clues and a character', len(scene['clues']) >= 3 and len(scene['characters']) >= 1)
    found = 0
    for i in range(4):                                       # a failed roll is allowed; keep looking
        out = st.turn(scene, 'I search the walls for carvings')
        show(out)
        now = sum(c['found'] for c in scene['clues'])
        check('3 search %d gives at most one clue' % (i + 1), now - found <= 1, '(%d found)' % now)
        if now > found:
            found = now
            break
    check('3 a clue was found within 4 searches', found == 1)
    npc = next(c for c in scene['characters'] if not c.get('player'))
    before = len(st.calls)
    out = st.turn(scene, 'I ask %s, "What happened down here?"' % npc['name'])
    show(out)
    roles = [r for r, _ in st.calls[before:]]
    check('4 the character answers', out[-1][0] == npc['name'] and len(out[-1][1]) > 3, out[-1][1][:60])
    check('4 the DM does not answer for it', 'dm' not in roles, str(roles))
    check('4 the Voices model spoke', (('voice', st.voices) in st.calls[before:]))
    out = st.turn(scene, '', redo=True)
    check('regenerate keeps the turn count and the speaker', len(scene['turns']) == i + 2 and out[-1][0] == npc['name'])
    for k in range(SUMMARY_EVERY + KEEP_TURNS):
        st.turn(scene, ['I wade further in', 'I listen', 'I hold up my lantern', 'I wait', 'I touch the water',
                        'I look up', 'I step back'][k % 7])
    check('5 rolling summary was made', bool(scene['summary']), scene['summary'][:80])
    st.end_scene(scene, keep=[npc['name']])
    st2 = Studio(st.dir, st.dm, st.voices)
    check('6 promoted character is still there', any(c['name'] == npc['name'] for c in st2.constants()))
    check('6 session log is saved', os.path.getsize(st.log_path) > 0, st.log_path)
    print('\n%s' % ('ALL PASS' if not fails else '%d FAILED' % fails))
    return fails


def player_line(text, name):
    """the player model's reply -> one action: its first line, no "Wren:" prefix, at most 2 sentences"""
    text = re.sub(r'[*_#`]+', '', text).strip()
    text = next((l.strip() for l in text.splitlines() if l.strip()), '')
    text = re.sub(r'^\s*(%s|player|me|action)\s*:\s*' % re.escape(name), '', text, flags=re.I)
    return ' '.join(sentences(text)[:2])[:240] or 'I look around.'


def cmd_selfplay(st, idea, player_model, turns):
    """A model plays the player for `turns` turns. It sees only what a player at the table would:
    the opening, who is here, what it has found, the last exchanges; never the DM's notes.
    Prints the transcript and counts; saves both to work/selfplay/."""
    scene = st.new_scene(idea, st.constants())
    p = st.player()
    out = ['== %s ==  (DM %s, Voices %s, player %s)' % (scene['title'], st.dm, st.voices, player_model),
           'DM: ' + scene['opening']]
    kinds, found_at, repeats, last_dm, actions = {}, [], 0, '', []
    for n in range(1, turns + 1):
        known = ' '.join([c['fact'] for c in scene['clues'] if c['found']] +
                         [c['name'] + ': ' + c['secret'] for c in scene['characters'] if c.get('revealed')]) or 'nothing yet'
        skills = ', '.join('%s %+d' % (k, v) for k, v in p.get('skills', {}).items())
        action = player_line(st.chat('player', player_model, fill('player', name=p['name'], look=p['look'], wants=p['wants'],
                                                                     skills=skills),
                                     fill('player_user', opening=scene['opening'], who=who_line(scene), known=known,
                                          recent=recent_text(scene, p['name'])), temperature=0.9), p['name'])
        before = sum(c['found'] for c in scene['clues'])
        shown = st.turn(scene, action)
        ruling = scene['turns'][-1]['ruling']
        kinds[ruling['kind']] = kinds.get(ruling['kind'], 0) + 1
        if sum(c['found'] for c in scene['clues']) > before:
            found_at.append(n)
        reply = scene['turns'][-1]['reply']
        if scene['turns'][-1]['speaker'] == 'DM':
            if last_dm and len(set(reply.lower().split()) & set(last_dm.lower().split())) > 0.6 * min(len(reply.split()), len(last_dm.split())):
                repeats += 1
            last_dm = reply
        actions.append(action)
        out.append('\n%d. %s: %s   <%s%s>' % (n, p['name'], action, ruling['kind'], ('/' + ruling['who']) if ruling.get('who') else ''))
        for who, text in shown:
            out.append(('   [%s]' % text) if who == 'roll' else ('   [%s: %s]' % (who, text)) if who in ('clue', 'secret') else '%s: %s' % (who, text))
    nclues = len(scene['clues'])
    counts = ['', '== counts ==',
              'turns: %d; referee said: %s' % (turns, ', '.join('%s %d' % kv for kv in sorted(kinds.items()))),
              'clues found: %d of %d, at turns %s' % (len(found_at), nclues, found_at or '-'),
              'secrets revealed: %d' % sum(1 for c in scene['characters'] if c.get('revealed')),
              'narration nearly repeating the one before: %d' % repeats,
              'player repeated an action word for word: %d' % (len(actions) - len(set(actions))),
              'summary: %s' % (scene['summary'] or '-'),
              'truth (hidden): %s' % scene['truth']]
    st.end_scene(scene)
    text = '\n'.join(out + counts)
    print(text)
    folder = os.path.join(HERE, '..', 'work', 'selfplay')
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, time.strftime('%Y-%m-%d_%H%M%S_') + slug(scene['title']) + '.txt')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text + '\nlog: %s\n' % st.log_path)
    print('\ntranscript: %s\nlog: %s' % (path, st.log_path))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('cmd', choices=['models', 'load', 'unload', 'play', 'test', 'selfplay'])
    ap.add_argument('args', nargs='*')
    ap.add_argument('--dm', default='gemma-2-2b-it-abliterated')
    ap.add_argument('--voices', default=None)
    ap.add_argument('--player', default=None, help='selfplay: the model playing the player (default: the DM model)')
    ap.add_argument('--turns', type=int, default=20, help='selfplay: how many player turns')
    ap.add_argument('--data', default=os.path.join(HERE, '..', 'work', 'data'),
                    help='data folder (the stack uses LIB_DATA: Games/TTRPG)')
    a = ap.parse_args()
    if a.cmd == 'models':
        for i, s, t in models() or [('(server not running)', '', '')]:
            print('%-11s %-10s %s' % (s, t, i))
    elif a.cmd == 'load':
        print(load_models(a.args[0] if a.args else a.dm, a.args[1] if len(a.args) > 1 else a.voices)[2])
    elif a.cmd == 'unload':
        unload_models([i for i, s, _ in models() if s == 'loaded' and i in (a.args or [a.dm, a.voices])])
        print('unloaded')
    else:
        dm, voices, status = load_models(a.dm, a.voices)
        print(status)
        if not dm:
            return 1
        st = Studio(os.path.abspath(a.data), dm, voices)
        if a.cmd == 'test':
            return cmd_test(st)
        if a.cmd == 'selfplay':
            return cmd_selfplay(st, ' '.join(a.args) or 'a flooded crypt under a chapel', a.player or dm, a.turns)
        cmd_play(st, ' '.join(a.args) or 'a flooded crypt under a chapel')
    return 0


if __name__ == '__main__':
    sys.exit(main())
