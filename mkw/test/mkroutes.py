#!/usr/bin/env python3
# Routes over new content (13 Nov): other cups, characters and karts, so the runs meet pipelines no run met before (kept with BENCH_STATE=shared) and measure the
# tracks not run yet. Menu positions from the screenshots of 13 Nov: main menu Single Player / Multiplayer (player count 2, Right 3, Right 4); modes Grand Prix first;
# cups one row, cursor on Mushroom (Right: Flower, Star, Shell, Banana, Leaf, Lightning); then 50 / 100 / 150cc, cursor on 50.
# Character and kart grids, all cursors on the first (Mario, Standard Kart):
#   one player (x-menu-1p): characters 4 columns, rows Mario Luigi Peach Pauline / Yoshi Toad Koopa Troopa Baby Mario / Wario Waluigi Bowser Baby Luigi; karts 3 columns
#   split screen (gp150-2p-star, 18:11): each player's own grid, two rows high, scrolling sideways (8 pages of characters, 2 of karts). Characters by columns:
#   Mario Yoshi | Wario Luigi | Toad Waluigi | Peach Koopa Troopa | Bowser Pauline; Down from the second row wraps to the first (the 2P route meant for Peach and Bowser
#   picked Toad twice). Karts likewise, first column Standard Kart / Rally Kart
# Each route takes screenshots of its menus (ctl "shot" lines) to check what was picked.
# usage: mkroutes.py <worktree root> [route ...]   (no route: all; a route's .ctl file is written only when named or with no names given)
import sys, os
root = sys.argv[1]; only = set(sys.argv[2:])
tsv = root + '/dm/games/0400C3F00006E000/bench.tsv'
rdir = root + '/mkw/test/routes'
SH = os.environ.get('RSHOTS', '/tmp/mkw-rshots')   # where the routes' screenshots go

ONE_CHARS = [['Mario', 'Luigi', 'Peach', 'Pauline'], ['Yoshi', 'Toad', 'Koopa Troopa', 'Baby Mario'], ['Wario', 'Waluigi', 'Bowser', 'Baby Luigi']]
SPLIT_CHARS = ['Mario', 'Yoshi', 'Wario', 'Luigi', 'Toad', 'Waluigi', 'Peach', 'Koopa Troopa', 'Bowser', 'Pauline']   # by columns, two rows
MAXMOVES = 4   # the time between the screens holds four presses 0.4 s apart

def one_char(name):
    r = [i for i, row in enumerate(ONE_CHARS) if name in row][0]
    return ['Down'] * r + ['Right'] * ONE_CHARS[r].index(name)
def split_char(name):
    col, row = divmod(SPLIT_CHARS.index(name), 2)
    return ['Down'] * row + ['Right'] * col
def kart(row, col):   # 1-based position in the grid
    return ['Down'] * (row - 1) + ['Right'] * (col - 1)
ORD = {1: 'first', 2: 'second', 3: 'third', 4: 'fourth'}
def kname(rc): return f'the {ORD[rc[1]]} vehicle of the {ORD[rc[0]]} row'

def moves(t0, keys, step=0.4, most=MAXMOVES):
    assert len(keys) <= most, keys
    return [(round(t0 + i * step, 2), k) for i, k in enumerate(keys)]

def p1_keys(seq):
    return ','.join(f'{t:g}:{k}' for t, k in seq)

routes = {}
# one player, docked: A 40 title, 43 Single Player, 46 Grand Prix, 49 character, 52 kart, 58 cup, 59.5/60.2 Right to 150cc, 61 A, 64 A (OK), hold A from 99
def one(name, cup, char, krc, cupname):
    seq = [(40, 'A'), (43, 'A'), (46, 'A')] + moves(47.4, one_char(char)) + [(49, 'A')] + moves(50.4, kart(*krc)) + [(52, 'A')] + moves(54.8, ['Right'] * cup, 0.45, 6) \
          + [(58, 'A'), (59.5, 'Right'), (60.2, 'Right'), (61, 'A'), (64, 'A')]
    keys = p1_keys(seq) + ',99:A~9.5*112/10'
    ctl = [f'{t} shot {SH}/{name}_{int(t)}.png' for t in (48.9, 51.9, 57.9, 62.5, 110)]
    routes[name] = (keys, 120, 1090, f'one player, docked: the {cupname} Cup at 150cc, {char} in {kname(krc)} (new content: pipelines no run met)', ctl)
one('gp-flower-150', 1, 'Pauline', (1, 2), 'Flower')
one('gp-leaf-150', 5, 'Baby Mario', (2, 1), 'Leaf')
one('gp-lightning-150', 6, 'Bowser', (3, 1), 'Lightning')

# split screen: A 40, Down 43 (Multiplayer, 2 players), Right 44 / 45 (3 / 4), A 46 (applet), A 50 Grand Prix, characters from 51.8 (P1 A 53.5, others 54.0),
# karts from 55.6 (P1 A 57.5, others 58.0), cups from 61.3 (A 63.5), 66.0 / 66.7 Right to 150cc, A 67.5, A 70.5 (OK), all hold A from 106
def multi(name, n, cup, chars, karts, desc):
    seq = [(40, 'A'), (43, 'Down')] + [(44 + i, 'Right') for i in range(n - 2)] + [(46, 'A'), (50, 'A')] + moves(51.8, chars[0]) + [(53.5, 'A')] \
          + moves(55.6, karts[0]) + [(57.5, 'A')] + moves(61.3, ['Right'] * cup, 0.5, 4) + [(63.5, 'A'), (66.0, 'Right'), (66.7, 'Right'), (67.5, 'A'), (70.5, 'A')]
    keys = p1_keys(seq) + ',106:A~9.5*112/10'
    ctl = []
    for p in range(2, n + 1):
        ctl.append(f'{42.0 + (p - 2) * 0.1:.1f} p{p}:ZL')
        for t, k in moves(51.9 + (p - 2) * 0.05, chars[p - 1]): ctl.append(f'{t:.2f} p{p}:{k}')
        ctl.append(f'{54.0 + (p - 2) * 0.1:.1f} p{p}:A')
        for t, k in moves(55.7 + (p - 2) * 0.05, karts[p - 1]): ctl.append(f'{t:.2f} p{p}:{k}')
        ctl.append(f'{58.0 + (p - 2) * 0.1:.1f} p{p}:A')
    for p in range(2, n + 1): ctl.append(f'{106.0 + (p - 2) * 0.1:.1f} p{p}:A~1110')
    ctl += [f'{t} shot {SH}/{name}_{int(t)}.png' for t in (53.3, 57.3, 63.3, 69.0, 115)]
    ctl.sort(key=lambda l: float(l.split()[0]))
    routes[name] = (keys, 120, 1090, desc, ctl)
def multi_named(name, n, cup, cupname, chars, karts):
    others = 'players 2' + (f' to {n}' if n > 3 else ' and 3' if n == 3 else '')
    who = ', '.join(chars[:-1]) + ' and ' + chars[-1]
    multi(name, n, cup, [split_char(c) for c in chars], [kart(*k) for k in karts],
          f'{["", "", "two", "three", "four"][n]} players, split screen: the {cupname} Cup at 150cc, {who} (new content); {others} from mkw/test/routes/{name}.ctl')
# run on 13 Nov 18:10 as written: in the split-screen grid these moves pick Toad for both (Rally Kart and Standard Kart)
multi('gp150-2p-star', 2, 2, [['Right', 'Right'], ['Down', 'Down', 'Right', 'Right']], [['Down'], ['Down', 'Down']],
      'two players, split screen: the Star Cup at 150cc, Toad for both, in Rally Kart and Standard Kart (new content); player 2 from mkw/test/routes/gp150-2p-star.ctl')
multi_named('gp150-3p-shell', 3, 3, 'Shell', ['Wario', 'Waluigi', 'Peach'], [(1, 2), (1, 4), (2, 3)])
multi_named('gp150-4p-banana', 4, 4, 'Banana', ['Koopa Troopa', 'Luigi', 'Yoshi', 'Bowser'], [(2, 2), (2, 4), (1, 3), (2, 1)])

s = open(tsv).read(); lines = s.split('\n')
for name, (keys, start, secs, desc, ctl) in routes.items():
    row = f'{name}\t{keys}\t{start}\t{secs}\t{desc}'
    idx = [i for i, l in enumerate(lines) if l.startswith(name + '\t')]
    if idx: lines[idx[0]] = row
    else:
        last = max(i for i, l in enumerate(lines) if l.strip()); lines.insert(last + 1, row)
    if not only or name in only:
        with open(f'{rdir}/{name}.ctl.tmp', 'w') as f:
            f.write(f'# {name}: seconds from the host\'s start, then a DM_CTL line (mkw/test/ctl_feed.py); generated by mkw/test/mkroutes.py (13 Nov)\n')
            f.write('\n'.join(ctl) + '\n')
        os.replace(f'{rdir}/{name}.ctl.tmp', f'{rdir}/{name}.ctl')
        print('ctl', name)
    print(name, keys, '|', desc)
with open(tsv + '.tmp', 'w') as f: f.write('\n'.join(lines))
os.replace(tsv + '.tmp', tsv)
os.makedirs(SH, exist_ok=True)
