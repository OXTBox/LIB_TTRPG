#!/usr/bin/env python3
"""ttrpg_world.py - the old TTRPG Studio's world code (Feb 2026, TTRPGtudioapilib_02092026), carried
into LIB_TTRPG (OPUS_BUILD step 9, 19 Nov 2026). The spec for livecode/lib_ttrpg_world.livecodescript.

A world is a map of cells (16 x 16 by default). Every cell is a location with one container of
gear; some cells also hold an NPC (a role from LIB_LISTS roles/) or a monster. Players stand on a
cell, look, take, drop, open, close, search and walk. The code holds what is hidden: the view and
the tile data only ever show visible things (the same rule as the Studio's clues and secrets).

Words come from LIB_LISTS by name, never copied (owner, 18 Nov):
    nouns/locations  nouns/monsters  nouns/ecosystem  nouns/containers   Lists/Equipment
    Lists/example_location_descriptions   roles/<Role>.txt (the file name is the role, the text its lore)

    python3 ref/ttrpg_world.py new [--seed N] [--cols 16 --rows 16]   make a world, save it, print counts
    python3 ref/ttrpg_world.py play [file]                            walk it in the terminal
    python3 ref/ttrpg_world.py vectors                                rewrite ref/world_vectors.json
    python3 ref/ttrpg_world.py test                                   check the vectors + a generated world

A world (all keyed arrays, so it is the same in xTalk):
    {name, cols, rows,
     locations: {"<Kind>_c3r5": {name, kind, col, row, ecosystem, description, containers}},
     npc:       {"<Role>_c3r5": {name, role, lore, location, attributes, containers}},
     monsters:  {"<Monster>_c3r5": {name, kind, location, attributes}},
     player:    {"Player1": {name, location, attributes, containers}}}
    containers = {"<name>": {name, open, locked, visible, items: {"<item>": {name, visible}}}}
"""
import json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LISTS = os.environ.get('LIB_LISTS') or os.path.normpath(os.path.join(HERE, '..', '..', 'LIB_LISTS'))
WORK = os.path.join(HERE, '..', 'work', 'data')
VECTORS = os.path.join(HERE, 'world_vectors.json')

ATTRIBUTES = ('Strength', 'Constitution', 'Dexterity', 'Intelligence', 'Wisdom', 'Charisma', 'AC', 'HP')
NAME_NOISE = ('the', 'a', 'an', 'of', 'old', 'young', 'elder', 'brother', 'sister', 'father', 'mother', 'sir', 'lady', 'lord', 'captain')
STEPS = {'north': (0, -1), 'south': (0, 1), 'east': (1, 0), 'west': (-1, 0)}
SHORT = {'n': 'north', 's': 'south', 'e': 'east', 'w': 'west'}
GROUND = 'ground'
PACK = 'Backpack'
HELD = 'held'
CFG = {'npc_chance': 25, 'monster_chance': 20, 'open_chance': 50, 'lock_chance': 25, 'hidden_chance': 50}


# ------------------------------------------------------------------ lists (LIB_LISTS, by name)

def read_list(name):
    """the non-empty lines of LIB_LISTS/<name>.txt; never printed by this tool"""
    path = os.path.join(LISTS, name + '.txt')
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8', errors='replace') as f:
        return [l.strip() for l in f.read().replace('\r', '\n').split('\n') if l.strip()]


def roles():
    folder = os.path.join(LISTS, 'roles')
    return sorted(f[:-4] for f in os.listdir(folder) if f.endswith('.txt')) if os.path.isdir(folder) else []


def role_lore(role):
    return ' '.join(read_list('roles/' + role))


# ------------------------------------------------------------------ small helpers (ported 1:1)

def d(x):
    """an array, or an empty one (xTalk saves an empty array as "")"""
    return x if isinstance(x, dict) else {}


def words(name):
    """'Old_Iron_Chest' -> 'Old Iron Chest'"""
    return name.replace('_', ' ').strip()


def under(name):
    return re.sub(r'\s+', '_', name.strip())


def cell_name(word, col, row):
    """old naming: the word, spaces -> _, then _c<col>r<row>"""
    return '%s_c%dr%d' % (under(word), col, row) if word else 'c%dr%d' % (col, row)


def cell_of(name):
    """'House_c3r12' -> (3, 12), or None (was entities.at.colrowname)"""
    m = re.search(r'c(\d+)r(\d+)$', name or '')
    return (int(m.group(1)), int(m.group(2))) if m else None


def name_words(name):
    out = [w for w in re.findall(r'[a-z]+', words(name).lower()) if w not in NAME_NOISE and len(w) > 2]
    return out or [words(name).lower()]


def ordered(keys):
    return sorted(keys, key=lambda k: (k.lower(), k))


def best_match(names, text):
    """the name whose words the text says most of; ties -> first in order; none -> ''"""
    said = set(re.findall(r'[a-z]+', text.lower()))
    best, score = '', 0
    for n in ordered(names):
        s = sum(1 for w in name_words(n) if w in said)
        if s > score:
            best, score = n, s
    return best


def join_and(items):
    items = list(items)
    if not items:
        return ''
    if len(items) == 1:
        return items[0]
    return ', '.join(items[:-1]) + ' and ' + items[-1]


# ------------------------------------------------------------------ making a world (random)

def attributes(rng):
    """was class.attributes.array.generator: 3 + d15 for each (it put the roll into the key too)"""
    return {a: 3 + rng.randint(1, 15) for a in ATTRIBUTES}


def chance(rng, pct):
    return rng.randint(1, 100) <= pct


def container(name, rng, gear, kind='place'):
    """was generate.container.and.AdventureGear: 2-3 pieces of gear, each visible or not"""
    c = {'name': name, 'open': True, 'locked': False, 'visible': True, 'items': {}}
    if kind == 'place':
        c['open'] = chance(rng, CFG['open_chance'])
        c['locked'] = (not c['open']) and chance(rng, CFG['lock_chance'])
    for _ in range(rng.randint(1, 2) + 1):
        if gear:
            item = rng.choice(gear)
            c['items'][item] = {'name': item, 'visible': not chance(rng, CFG['hidden_chance'])}
    return c


def new_world(name='Example_01_World', cols=16, rows=16, seed=None):
    """was init.RandomMapGenerator + entity.type.x.y.z.world + insert.location.entities"""
    rng = random.Random(seed)
    kinds, beasts, moods = read_list('nouns/locations'), read_list('nouns/monsters'), read_list('nouns/ecosystem')
    boxes, gear, descs = read_list('nouns/containers'), read_list('Lists/Equipment'), read_list('Lists/example_location_descriptions')
    people = roles()
    w = {'name': under(name), 'cols': cols, 'rows': rows, 'locations': {}, 'npc': {}, 'monsters': {}, 'player': {}}
    for r in range(1, rows + 1):
        for c in range(1, cols + 1):
            kind = rng.choice(kinds) if kinds else 'Place'
            loc = cell_name(kind, c, r)
            box = rng.choice(boxes) if boxes else 'Chest'
            w['locations'][loc] = {'name': loc, 'kind': kind, 'col': c, 'row': r,
                                   'ecosystem': rng.choice(moods) if moods else '',
                                   'description': rng.choice(descs) if descs else '',
                                   'containers': {box: container(box, rng, gear)}}
            if people and chance(rng, CFG['npc_chance']):
                role = rng.choice(people)
                n = cell_name(role, c, r)
                w['npc'][n] = {'name': n, 'role': role, 'lore': role_lore(role), 'location': loc,
                               'attributes': attributes(rng), 'containers': {HELD: container(HELD, rng, gear, 'actor')}}
            if beasts and chance(rng, CFG['monster_chance']):
                kind_m = rng.choice(beasts)
                n = cell_name(kind_m, c, r)
                w['monsters'][n] = {'name': n, 'kind': kind_m, 'location': loc, 'attributes': attributes(rng)}
    return w


def spawn_player(w, rng=None, name=None):
    """was player.random.spawn: a new PlayerN on a random cell, with a Backpack of gear"""
    rng = rng or random.Random()
    name = name or 'Player%d' % (len(d(w.get('player'))) + 1)
    loc = cell_name_at(w, rng.randint(1, w['cols']), rng.randint(1, w['rows']))
    p = {'name': name, 'location': loc, 'attributes': attributes(rng),
         'containers': {PACK: container(PACK, rng, read_list('Lists/Equipment'), 'actor')}}
    w.setdefault('player', {})
    if not isinstance(w['player'], dict):
        w['player'] = {}
    w['player'][name] = p
    return name


# ------------------------------------------------------------------ reading a world (pure)

def cell_name_at(w, col, row):
    """the location on a cell, or '' (was world.random.location.name / world.location.array.by.name)"""
    suffix = 'c%dr%d' % (col, row)
    for k in ordered(d(w.get('locations'))):
        if cell_of(k) == (col, row) and k.endswith(suffix):
            return k
    return ''


def here(w, loc, kind):
    """names of the npc / monsters standing on a location"""
    return ordered(k for k, v in d(w.get(kind)).items() if d(v).get('location') == loc)


def visible_tile(w, loc):
    """was GetVisibleRoomStateForPlayer + BuildTileDescription's data: only what can be seen.
    Containers that are hidden are left out; items show only from open, unlocked containers and
    only when visible. Locked shows as closed (you find out it is locked by trying)."""
    L = d(d(w.get('locations')).get(loc))
    out = {'name': loc, 'kind': L.get('kind', ''), 'ecosystem': L.get('ecosystem', ''),
           'description': L.get('description', ''), 'containers': {},
           'npc': {}, 'monsters': {}}
    for cn, c in d(L.get('containers')).items():
        c = d(c)
        if c.get('visible') is not True or (cn == GROUND and not d(c.get('items'))):
            continue
        shown = {'name': cn, 'open': c.get('open') is True, 'items': {}}
        if c.get('open') is True and c.get('locked') is not True:
            for iname, it in d(c.get('items')).items():
                if d(it).get('visible') is True:
                    shown['items'][iname] = {'name': iname}
        out['containers'][cn] = shown
    for n in here(w, loc, 'npc'):
        out['npc'][n] = {'name': n, 'role': words(d(w['npc'][n]).get('role', ''))}
    for n in here(w, loc, 'monsters'):
        out['monsters'][n] = {'name': n, 'kind': d(w['monsters'][n]).get('kind', '')}
    return out


def exits(w, loc):
    cr = cell_of(loc)
    if not cr:
        return []
    out = []
    for way in ('north', 'south', 'east', 'west'):
        dc, dr = STEPS[way]
        if cell_name_at(w, cr[0] + dc, cr[1] + dr):
            out.append(way)
    return out


def view(w, player):
    """what the player sees, as text (was BuildPlayerTurnPrompt; its prompt part is prompts/world_tile.txt)"""
    p = d(d(w.get('player')).get(player))
    loc = p.get('location', '')
    t = visible_tile(w, loc)
    cr = cell_of(loc) or (0, 0)
    lines = ['You are at: %s (column %d, row %d)' % (words(t['kind']) or words(loc), cr[0], cr[1])]
    if t['description']:
        lines.append(t['description'])
    if t['ecosystem']:
        lines.append('The air carries a sense of %s.' % t['ecosystem'])
    who = [words(v['role']) for k, v in ordered_items(t['npc'])] + [words(v['kind']) for k, v in ordered_items(t['monsters'])]
    lines.append('Here: %s.' % join_and(who) if who else 'Nobody else is here.')
    boxes = ['%s (%s)' % (words(cn), 'open' if c['open'] else 'closed') for cn, c in ordered_items(t['containers'])]
    lines.append('Containers: %s.' % join_and(boxes) if boxes else 'No containers.')
    seen = ['%s in the %s' % (words(i), words(cn)) for cn, c in ordered_items(t['containers']) for i in ordered(c['items'])]
    lines.append('You can see: %s.' % join_and(seen) if seen else 'You see nothing to take.')
    carried = []
    for cn, c in ordered_items(d(p.get('containers'))):
        its = [words(i) for i in ordered(d(d(c).get('items')))]
        carried.append('%s: %s' % (words(cn), join_and(its) if its else 'empty'))
    lines.append('You carry: %s.' % '; '.join(carried) if carried else 'You carry nothing.')
    ways = exits(w, loc)
    lines.append('Ways out: %s.' % join_and(ways) if ways else 'No way out.')
    return '\n'.join(lines)


def ordered_items(a):
    a = d(a)
    return [(k, d(a[k])) for k in ordered(a)]


def scene_idea(w, player):
    """a one-line idea for the Studio's New Scene, made from the player's cell"""
    p = d(d(w.get('player')).get(player))
    t = visible_tile(w, p.get('location', ''))
    idea = words(t['kind']) or 'a place'
    if t['ecosystem']:
        idea += ', ' + t['ecosystem']
    if t['description']:
        idea += ': ' + t['description']
    who = [words(v['role']) for k, v in ordered_items(t['npc'])] + [words(v['kind']) for k, v in ordered_items(t['monsters'])]
    if who:
        idea += ' With ' + join_and(who) + '.'
    return idea


def character_ask(w, npc):
    """a one-line ask for the Studio's Add Character, from an NPC's role and lore"""
    n = d(d(w.get('npc')).get(npc))
    ask = words(n.get('role', '')) or words(npc)
    if n.get('lore'):
        ask += ': ' + n['lore']
    return ask


def tile_prompt(w, loc):
    """prompts/world_tile.txt (was describe_a_tile) with the VISIBLE tile only"""
    from ttrpg_ref import fill
    return fill('world_tile', tile=json.dumps(visible_tile(w, loc), indent=1, ensure_ascii=False))


def npc_prompt(w, npc):
    """prompts/world_npc.txt (was ttrpg.entity.styler.prompt + nouns.npc.lore.text)"""
    from ttrpg_ref import fill
    n = d(d(w.get('npc')).get(npc))
    return fill('world_npc', role=words(n.get('role', '')), name=words(n.get('role', '')) or words(npc), lore=n.get('lore', ''))


# ------------------------------------------------------------------ changing a world (pure on w)

def act(w, player, text):
    """was InterpregPlayerAction (never finished): one world action. Returns the reply, or '' when
    the words are not a world action (then the Studio's turn handles them as before)."""
    p = d(d(w.get('player')).get(player))
    if not p:
        return ''
    loc = p.get('location', '')
    L = d(d(w.get('locations')).get(loc))
    said = re.findall(r"[a-z']+", text.lower())
    if not said:
        return ''
    verb = said[0]
    if verb == 'pick' and len(said) > 1 and said[1] == 'up':
        verb = 'take'
    if verb in ('look', 'l'):
        return view(w, player)
    if verb in ('go', 'walk', 'move', 'head') or verb in STEPS or verb in SHORT:
        way = verb if verb in STEPS else SHORT.get(verb, '')
        if not way:
            way = next((SHORT.get(x, x) for x in said[1:] if SHORT.get(x, x) in STEPS), '')
        if not way:
            return 'Which way? %s.' % join_and(exits(w, loc)).capitalize()
        cr = cell_of(loc)
        to = cell_name_at(w, cr[0] + STEPS[way][0], cr[1] + STEPS[way][1]) if cr else ''
        if not to:
            return 'You cannot go %s from here.' % way
        p['location'] = to
        return view(w, player)
    boxes = d(L.get('containers'))
    seen_boxes = [cn for cn, c in boxes.items() if d(c).get('visible') is True]
    if verb in ('open', 'close', 'shut', 'unlock'):
        cn = best_match(seen_boxes, text)
        if not cn:
            return 'You see nothing like that to %s.' % verb
        c = boxes[cn]
        if verb == 'open':
            if c.get('open') is True:
                return 'The %s is already open.' % words(cn)
            if c.get('locked') is True:
                return 'The %s is locked.' % words(cn)
            c['open'] = True
            inside = [words(i) for i in ordered(d(c.get('items'))) if d(c['items'][i]).get('visible') is True]
            return 'You open the %s.%s' % (words(cn), (' Inside: %s.' % join_and(inside)) if inside else ' It looks empty.')
        if verb == 'unlock':
            return 'The %s is not locked.' % words(cn) if c.get('locked') is not True else 'You have no key for the %s.' % words(cn)
        if c.get('open') is not True:
            return 'The %s is already closed.' % words(cn)
        c['open'] = False
        return 'You close the %s.' % words(cn)
    if verb in ('take', 'grab', 'get', 'pick'):
        where = {}
        for cn in seen_boxes:
            c = boxes[cn]
            if c.get('open') is True and c.get('locked') is not True:
                for i, it in d(c.get('items')).items():
                    if d(it).get('visible') is True and i not in where:
                        where[i] = cn
        item = best_match(list(where), text)
        if not item:
            return 'You see nothing like that to take.'
        cn = where[item]
        put_item(p, PACK, item, take_item(boxes[cn], item))
        return 'You take the %s from the %s.' % (words(item), words(cn))
    if verb in ('drop', 'leave'):
        mine = {}
        for cn, c in d(p.get('containers')).items():
            for i in d(d(c).get('items')):
                if i not in mine:
                    mine[i] = cn
        item = best_match(list(mine), text)
        if not item:
            return 'You carry nothing like that.'
        it = take_item(p['containers'][mine[item]], item)
        if GROUND not in boxes or not isinstance(boxes[GROUND], dict):
            boxes[GROUND] = {'name': GROUND, 'open': True, 'locked': False, 'visible': True, 'items': {}}
        boxes[GROUND].setdefault('items', {})
        if not isinstance(boxes[GROUND]['items'], dict):
            boxes[GROUND]['items'] = {}
        it['visible'] = True
        boxes[GROUND]['items'][item] = it
        L['containers'] = boxes
        return 'You drop the %s.' % words(item)
    if verb in ('search', 'examine'):
        found = []
        for cn in ordered(seen_boxes):
            c = boxes[cn]
            if c.get('open') is True and c.get('locked') is not True:
                for i in ordered(d(c.get('items'))):
                    if d(c['items'][i]).get('visible') is not True:
                        c['items'][i]['visible'] = True
                        found.append('%s in the %s' % (words(i), words(cn)))
        return 'You search and find %s.' % join_and(found) if found else 'You search and find nothing new.'
    return ''


def take_item(c, item):
    items = d(c.get('items'))
    it = d(items.pop(item, None)) or {'name': item}
    c['items'] = items
    return it


def put_item(actor, cn, item, it):
    boxes = d(actor.get('containers'))
    c = d(boxes.get(cn)) or {'name': cn, 'open': True, 'locked': False, 'visible': True, 'items': {}}
    items = d(c.get('items'))
    it = dict(it)
    it['name'] = item
    it['visible'] = True
    items[item] = it
    c['items'] = items
    boxes[cn] = c
    actor['containers'] = boxes


# ------------------------------------------------------------------ files

def save_world(w, folder=WORK):
    path = os.path.join(folder, 'worlds', w['name'] + '.json')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(w, f, indent=1, ensure_ascii=False)
    return path


def load_world(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def save_object(w, kind, name, folder=WORK):
    """one actor / location on its own (was the two SaveWorldObjectToJSON, SaveActorToJSON, SaveLocationToJSON)"""
    obj = d(d(w.get(kind)).get(name))
    if not obj:
        return ''
    path = os.path.join(folder, 'worlds', w['name'], kind, name + '.json')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
    return path


def load_object(w, kind, path):
    obj = load_world(path)
    w.setdefault(kind, {})
    if not isinstance(w[kind], dict):
        w[kind] = {}
    w[kind][obj['name']] = obj
    return obj['name']


# ------------------------------------------------------------------ vectors (the xTalk port must match)

def sample_world():
    """a small fixed world in our own words (no LIB_LISTS words in the vectors)"""
    def box(name, open_, locked, items):
        return {'name': name, 'open': open_, 'locked': locked, 'visible': True,
                'items': {i: {'name': i, 'visible': v} for i, v in items}}
    w = {'name': 'Vector_World', 'cols': 2, 'rows': 2, 'locations': {}, 'npc': {}, 'monsters': {}, 'player': {}}
    w['locations']['Old_Mill_c1r1'] = {'name': 'Old_Mill_c1r1', 'kind': 'Old Mill', 'col': 1, 'row': 1, 'ecosystem': 'damp moss',
                                       'description': 'A wheel creaks in the dark.',
                                       'containers': {'Iron Chest': box('Iron Chest', True, False, [('Rope', True), ('Silver Key', False)]),
                                                      'Crate': box('Crate', False, False, [('Lantern', True)])}}
    w['locations']['Bog_c2r1'] = {'name': 'Bog_c2r1', 'kind': 'Bog', 'col': 2, 'row': 1, 'ecosystem': 'rot', 'description': '',
                                  'containers': {'Sack': box('Sack', False, True, [('Gold Coin', True)])}}
    w['locations']['Tower_c1r2'] = {'name': 'Tower_c1r2', 'kind': 'Tower', 'col': 1, 'row': 2, 'ecosystem': '', 'description': 'Stairs go up.',
                                    'containers': {}}
    w['npc']['Old_Miller_c1r1'] = {'name': 'Old_Miller_c1r1', 'role': 'Old_Miller', 'lore': 'Grinds bones, not wheat.',
                                   'location': 'Old_Mill_c1r1', 'attributes': {}, 'containers': {}}
    w['monsters']['Bog_Toad_c2r1'] = {'name': 'Bog_Toad_c2r1', 'kind': 'Bog Toad', 'location': 'Bog_c2r1', 'attributes': {}}
    w['player']['Player1'] = {'name': 'Player1', 'location': 'Old_Mill_c1r1', 'attributes': {},
                              'containers': {PACK: box(PACK, True, False, [('Torch', True)])}}
    return w


ACTIONS = ['look', 'take the rope', 'take the key', 'search the chest', 'take the silver key', 'open the crate',
           'open the crate', 'grab lantern', 'close the crate', 'drop the torch', 'take torch', 'dance wildly',
           'go up', 'go north', 'east', 'open the sack', 'take the coin', 'w', 's', 'look', 'n', 'drop rope']


def make_vectors():
    w = sample_world()
    out = {'cell_of': [[n, list(cell_of(n) or [])] for n in ('House_c3r12', 'c1r1', 'Big_Old_House_c10r5', 'nothing', '')],
           'best_match': [[['Iron Chest', 'Crate', 'Old Iron Box'], t, best_match(['Iron Chest', 'Crate', 'Old Iron Box'], t)]
                          for t in ('open the iron box', 'open the chest', 'kick it', 'old crate please')],
           'join_and': [[x, join_and(x)] for x in ([], ['a'], ['a', 'b'], ['a', 'b', 'c'])],
           'start': w, 'steps': []}
    w = json.loads(json.dumps(w))
    for a in ACTIONS:
        reply = act(w, 'Player1', a)
        out['steps'].append({'action': a, 'reply': reply, 'world': json.loads(json.dumps(w))})
    out['scene_idea'] = scene_idea(sample_world(), 'Player1')
    out['character_ask'] = character_ask(sample_world(), 'Old_Miller_c1r1')
    out['tile'] = visible_tile(sample_world(), 'Old_Mill_c1r1')
    return out


def check_vectors(v):
    fails = []
    for n, want in v['cell_of']:
        got = list(cell_of(n) or [])
        if got != want:
            fails.append('cell_of %r: %r' % (n, got))
    for names, t, want in v['best_match']:
        if best_match(names, t) != want:
            fails.append('best_match %r' % t)
    w = json.loads(json.dumps(v['start']))
    for s in v['steps']:
        reply = act(w, 'Player1', s['action'])
        if reply != s['reply']:
            fails.append('act %r: %r' % (s['action'], reply))
        if norm(w) != norm(s['world']):
            fails.append('act %r: world differs' % s['action'])
    if scene_idea(v['start'], 'Player1') != v['scene_idea']:
        fails.append('scene_idea')
    if norm(visible_tile(v['start'], 'Old_Mill_c1r1')) != norm(v['tile']):
        fails.append('tile')
    tp = tile_prompt(v['start'], 'Old_Mill_c1r1')
    if 'Silver Key' in tp or 'Lantern' in tp or 'Rope' not in tp:
        fails.append('tile prompt shows a hidden or shut-away item, or misses a visible one')
    return fails


def norm(x):
    """compare worlds the way xTalk can: empty arrays = empty"""
    if isinstance(x, dict):
        return {k: norm(v) for k, v in x.items() if not (isinstance(v, (dict, str)) and not v)}
    return x


def check_generated(w):
    """facts any generated world must keep (randomness differs between Python and xTalk)"""
    fails = []
    n = w['cols'] * w['rows']
    if len(w['locations']) != n:
        fails.append('locations %d, want %d' % (len(w['locations']), n))
    for k, L in w['locations'].items():
        if cell_of(k) != (L['col'], L['row']):
            fails.append('cell name ' + k)
            break
        if len(L['containers']) != 1:
            fails.append('containers at ' + k)
            break
    for kind in ('npc', 'monsters', 'player'):
        for k, a in d(w.get(kind)).items():
            if a['location'] not in w['locations']:
                fails.append('%s %s stands nowhere' % (kind, k))
                break
    return fails


# ------------------------------------------------------------------ terminal

def main():
    a = sys.argv[1:]
    cmd = a[0] if a else 'help'
    opt = lambda k, dflt: type(dflt)(a[a.index(k) + 1]) if k in a else dflt
    if cmd == 'vectors':
        with open(VECTORS, 'w', encoding='utf-8') as f:
            json.dump(make_vectors(), f, indent=1, ensure_ascii=False)
        print('wrote', VECTORS)
    elif cmd == 'test':
        fails = check_vectors(json.load(open(VECTORS, encoding='utf-8')))
        w = new_world(seed=1)
        spawn_player(w, random.Random(1))
        fails += check_generated(w)
        if not os.path.isdir(LISTS):
            fails.append('LIB_LISTS not found at ' + LISTS)
        for f in fails:
            print('FAIL', f)
        print('PASS' if not fails else '%d FAIL' % len(fails),
              '- generated: %d locations, %d npc, %d monsters' % (len(w['locations']), len(w['npc']), len(w['monsters'])))
        return 1 if fails else 0
    elif cmd == 'new':
        w = new_world(opt('--name', 'Example_01_World'), opt('--cols', 16), opt('--rows', 16), opt('--seed', 0) or None)
        spawn_player(w)
        print('saved', save_world(w), '-', len(w['locations']), 'locations,', len(w['npc']), 'npc,', len(w['monsters']), 'monsters')
    elif cmd == 'play':
        path = a[1] if len(a) > 1 else os.path.join(WORK, 'worlds', 'Example_01_World.json')
        w = load_world(path)
        player = ordered(w['player'])[0]
        print(view(w, player))
        while True:
            try:
                line = input('> ').strip()
            except EOFError:
                break
            if line in ('quit', 'q', 'exit'):
                break
            if line == 'idea':
                print(scene_idea(w, player))
                continue
            print(act(w, player, line) or '(not a world action: the Studio would play it as a turn)')
        save_world(w)
    else:
        print(__doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main())
