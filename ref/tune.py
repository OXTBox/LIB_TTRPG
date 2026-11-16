#!/usr/bin/env python3
"""tune: measure the weak spots of DESIGN.md (1 to 4) with real models, A against B.

    python3 ref/tune.py all  --dm gemma-2-2b-it-abliterated [--voices M] [--n 8]
    python3 ref/tune.py w2   ...      only one of w1 w2 w3 w4

Models must already be loaded (python3 ref/ttrpg_ref.py load DM [VOICES]). Every call is in the
session log under work/tune/<dm>/logs. Results go to the terminal; TUNING.md records them.
  W1  does the narration word the found clue?        share of the clue's content words in the narration
  W2  does a character let its secret slip?           A: guard in the system prompt (now)
                                                      B: + the secret in the user message, "say this now"
  W3  does the same action get the same narration?    word overlap of two replies to one action
                                                      A: prompts as now; B: + "say something new" line;
                                                      C: code asks again (temperature 1.1) when overlap > 0.6
  W4  do the scene maker's clues point at the truth?  scenes printed for reading, + truth words in clues
"""
import argparse, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttrpg_ref as T

STOP = set('a an the of to in on at and or is are was were be it its this that with for from by as you your they them their he she his her i my me not no but into out up down there here what who has have had one some'.split())
IDEAS = ['a flooded crypt under a chapel', 'a toll bridge run by goblins', 'a lighthouse whose keeper vanished',
         'a market stall selling cursed masks']


def content(text):
    return {w for w in re.findall(r"[a-z']+", text.lower()) if w not in STOP and len(w) > 2}


def overlap(a, b):
    a, b = content(a), content(b)
    return len(a & b) / max(1, min(len(a), len(b)))


def scene_for(st, idea):
    return st.new_scene(idea, [])


def w1(st, n):
    """found clue -> how much of it the narration carries"""
    scores = []
    for k in range(n):
        sc = scene_for(st, IDEAS[k % len(IDEAS)])
        c = sc['clues'][0]
        ruling = {'kind': 'look', 'skill': c['skill'], 'success': True, 'clue': c['id'],
                  'result': 'The player discovers exactly this, and nothing more: ' + c['fact']}
        c['found'] = True
        p = st.player()
        text = T.clean_narration(st.chat('dm', st.dm, T.fill('dm_turn'), T.fill(
            'dm_turn_user', place=sc['place'], who=T.who_line(sc), summary='The scene has just begun.', known='nothing yet',
            recent=sc['opening'], player=p['name'], action='I examine ' + c['where'], result=ruling['result'])), 4)
        s = len(content(c['fact']) & content(text)) / max(1, len(content(c['fact'])))
        scores.append(s)
        print('  W1 %.2f  clue: %s\n         said: %s' % (s, c['fact'], text))
    print('W1 mean share of clue words in the narration: %.2f (n=%d)' % (sum(scores) / len(scores), len(scores)))


def w2(st, n):
    """a successful Persuasion: does the secret come out?"""
    res = {'A': [], 'B': []}
    sc = scene_for(st, IDEAS[0])
    npc = next(c for c in sc['characters'] if c.get('secret'))
    print('  W2 character: %s; secret: %s' % (npc['name'], npc['secret']))
    p = st.player()
    action = 'I look %s in the eye. "I know you are hiding something. Tell me the truth."' % npc['name']
    guard = 'The player has earned your trust or seen through you: let your secret slip now.'
    for k in range(n):
        for v in ('A', 'B'):
            user = T.fill('voice_user', place=sc['place'], recent=sc['opening'], player=p['name'], action=action)
            if v == 'B':
                user += '\n(Say this now, in your own words: %s)' % npc['secret']
            text = T.clean_speech(st.chat('voice', st.voices, T.fill('voice', guard=guard, **{
                key: npc.get(key, '') for key in ('name', 'look', 'voice', 'wants', 'secret')}), user, temperature=0.9), npc['name'])
            s = len(content(npc['secret']) & content(text)) / max(1, len(content(npc['secret'])))
            res[v].append(s)
            print('  W2 %s %.2f  %s' % (v, s, text))
    for v in res:
        print('W2 %s mean share of secret words said: %.2f; said at least a third: %d/%d' % (
            v, sum(res[v]) / n, sum(1 for s in res[v] if s >= 0.34), n))


def w3(st, n):
    """the same action twice in a row: how alike are the two narrations?"""
    res = {'A': [], 'B': [], 'C': []}
    for k in range(n):
        sc = scene_for(st, IDEAS[k % len(IDEAS)])
        p = st.player()
        for v in ('A', 'B', 'C'):
            replies, turns = [], []
            for rep in range(2):
                recent = ' '.join('%s: %s %s: %s' % (p['name'], t[0], 'DM', t[1]) for t in turns) or sc['opening']
                user = T.fill('dm_turn_user', place=sc['place'], who=T.who_line(sc), summary='The scene has just begun.',
                              known='nothing yet', recent=recent, player=p['name'], action='I look around',
                              result='The action works; describe its plain, immediate effect.')
                if v == 'B':
                    user += '\nSay something new: do not reuse the wording of "Just before".'
                text = T.clean_narration(st.chat('dm', st.dm, T.fill('dm_turn'), user), 4)
                if v == 'C' and replies and overlap(text, replies[-1]) > 0.6:
                    # code-side: nearly the same words again -> ask once more, hotter
                    text = T.clean_narration(st.chat('dm', st.dm, T.fill('dm_turn'), user, temperature=1.1), 4)
                replies.append(text)
                turns.append(('I look around', text))
            s = overlap(replies[0], replies[1])
            res[v].append(s)
            print('  W3 %s %.2f\n     1: %s\n     2: %s' % (v, s, replies[0], replies[1]))
    for v in res:
        print('W3 %s mean overlap of the two replies: %.2f (n=%d)' % (v, sum(res[v]) / n, n))


def w4(st, n):
    """scenes for reading: do the clues point at the truth?"""
    scores = []
    for k in range(n):
        sc = scene_for(st, IDEAS[k % len(IDEAS)])
        t = content(sc['truth'])
        hits = sum(1 for c in sc['clues'] if t & content(c['fact']))
        scores.append(hits / max(1, len(sc['clues'])))
        print('  W4 %s\n     TRUTH: %s' % (sc['title'], sc['truth']))
        for c in sc['clues']:
            print('     - %s (%s): %s' % (c['where'], c['skill'], c['fact']))
        print('     opening: %s' % sc['opening'])
    print('W4 share of clues sharing a word with the truth: %.2f (n=%d)' % (sum(scores) / n, n))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('what', choices=['all', 'w1', 'w2', 'w3', 'w4'])
    ap.add_argument('--dm', default='gemma-2-2b-it-abliterated')
    ap.add_argument('--voices', default=None)
    ap.add_argument('--n', type=int, default=6)
    a = ap.parse_args()
    data = os.path.join(T.HERE, '..', 'work', 'tune', a.dm)
    st = T.Studio(os.path.abspath(data), a.dm, a.voices)
    print('DM %s, Voices %s, log %s' % (st.dm, st.voices, st.log_path))
    for name in ('w1', 'w2', 'w3', 'w4'):
        if a.what in ('all', name):
            globals()[name](st, a.n)
    return 0


if __name__ == '__main__':
    sys.exit(main())
