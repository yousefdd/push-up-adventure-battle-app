"""Builds every adventure picture and the Dart data that names them.

    python3 tool/art/build.py      (from the project root)

Sources are the painted cut-outs in tool/art/src (the user's own reference
art). Foes are recoloured per world, bosses get a glow, and every world's
two parallax layers are painted here in code.
"""
import math
import os
import random
import sys

import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from roster import CHAPTERS, GEAR, START_LEVELS  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SRC = os.path.join(HERE, 'src')
OUT = os.path.join(ROOT, 'assets', 'art')
DATA_ONLY = '--data' in sys.argv  # rewrite the Dart files only, keep the pictures
os.makedirs(OUT, exist_ok=True)
if not DATA_ONLY:
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))

INK = (27, 20, 38)


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# Cut-outs drawn looking right. Foes stand on the right of the battle, so
# these are mirrored to face the hero on the left.
# Checked one by one at full size against the hero's side (see
# docs/REFERENCE_SPEC.md, "Facing"); goblin, imp, nightmare_horse and
# void_scorpion already face left in their cut-outs.
FACES_RIGHT = {'abyss_shark', 'frog', 'frost_wolf', 'griffin', 'lava_dragon', 'lava_beast',
               'venom_serpent', 'snail', 'dragonfly', 'spiked_maw'}

# Cut-outs drawn facing the viewer. In a fight they get a slight perspective
# turn toward the hero so the two still look at each other.
FRONT = {'slime', 'mushroom', 'rock_sprout', 'elder_treant', 'swamp_toad', 'bog_sludge', 'rot_brute', 'moss_troll',
         'night_bat', 'shadow_bat', 'hornet', 'mantis_fairy', 'cyclops_blob', 'crystal_spider', 'widow_spider',
         'stone_golem', 'crystal_colossus', 'ice_golem', 'magma_golem', 'spike_ball', 'crab', 'wisp', 'flame_penguin',
         'jellyfish', 'skeleton_knight', 'grave_reaper', 'soul_reaper', 'grimoire', 'fire_elemental', 'red_demon',
         'blood_demon', 'kraken_eye', 'beholder', 'moss_mammoth'}

# One special ability per creature type (see FoeAbility in chapters.dart).
ABILITY = {}
for _ab, _kinds in {
    'regen': 'slime elder_treant moss_troll snap_plant mushroom bog_sludge swamp_toad rot_brute frog cyclops_blob',
    'stoneSkin': 'stone_golem ice_golem crystal_colossus crab crystal_beetle snail rock_sprout spike_ball '
                 'skeleton_knight magma_golem moss_mammoth',
    'frenzy': 'wolf frost_wolf boar abyss_shark gremlin goblin nightmare_horse lava_beast spiked_maw blood_demon',
    'drain': 'night_bat shadow_bat soul_reaper grave_reaper wisp jellyfish kraken_eye frost_spirit',
    'venom': 'widow_spider crystal_spider venom_serpent void_scorpion hornet',
    'breath': 'baby_dragon lava_dragon fire_elemental salamander flame_penguin red_demon',
    'hex': 'beholder grimoire imp',
    'evasive': 'dragonfly griffin mantis_fairy',
}.items():
    for _k in _kinds.split():
        ABILITY[_k] = _ab


def src(name):
    """A cut-out with stray specks from its neighbours removed."""
    img = Image.open(os.path.join(SRC, name + '.png')).convert('RGBA')
    if name in FACES_RIGHT:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.asarray(img).copy()
    lab, n = ndimage.label(a[..., 3] > 40)
    if n > 1:
        sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
        keep = np.isin(lab, [i + 1 for i, sz in enumerate(sizes) if sz >= sizes.max() * 0.04])
        a[..., 3] = np.where(ndimage.binary_dilation(keep, iterations=3), a[..., 3], 0)
    return Image.fromarray(a, 'RGBA')


# ------------------------------------------------------------ recolour

def _rgb2hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h / 6, s, mx


def _hsv2rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[sel] = np.stack([a[sel], b[sel], c[sel]], -1)
    return out


def recolor(img, hue=0, sat=1.0, val=1.0, tint=None, amt=0.0, band=None):
    """band=(lo, hi) in degrees limits the hue turn to those colours (a gem, not its gold)."""
    a = np.asarray(img).astype(float) / 255
    rgb, al = a[..., :3], a[..., 3:]
    h, s, v = _rgb2hsv(rgb)
    if band:
        deg = h * 360
        h = np.where((deg >= band[0]) & (deg <= band[1]) & (s > 0.18), (h + hue / 360) % 1, h)
    else:
        h = (h + hue / 360) % 1
    s = np.clip(s * sat, 0, 1)
    v = np.clip(v * val, 0, 1)
    rgb = _hsv2rgb(h, s, v)
    if tint and amt:
        t = np.array(hexrgb(tint)) / 255
        lum = (rgb * [0.299, 0.587, 0.114]).sum(-1, keepdims=True)
        tl = (t * [0.299, 0.587, 0.114]).sum()
        rgb = rgb * (1 - amt) + np.clip(lum / max(tl, 0.05) * t, 0, 1) * amt
    return Image.fromarray((np.concatenate([rgb, al], -1) * 255).astype(np.uint8), 'RGBA')


# ------------------------------------------------------------ sprites

def sticker(img, rim=3):
    """A dark rim around the cut-out so it reads on any background."""
    a = img.getchannel('A')
    grown = a.filter(ImageFilter.MaxFilter(rim * 2 + 1)).filter(ImageFilter.GaussianBlur(0.8))
    rimg = Image.new('RGBA', img.size, INK + (0,))
    rimg.putalpha(grown.point(lambda x: int(x * 0.9)))
    rimg.alpha_composite(img)
    return rimg


def glow(img, color, radius):
    a = img.getchannel('A').filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(radius))
    g = Image.new('RGBA', img.size, hexrgb(color) + (0,))
    g.putalpha(a.point(lambda x: min(255, int(x * 1.6))))
    g.alpha_composite(img)
    return g


def place(img, size, fill=0.9, aura=None, rim=3):
    """Fit into a square canvas, centred, feet on the bottom edge."""
    pad = 24 if aura else 8
    big = Image.new('RGBA', (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    big.paste(img, (pad, pad))
    sc = min(size * fill / big.width, size * (fill + 0.06) / big.height)
    big = big.resize((max(1, round(big.width * sc)), max(1, round(big.height * sc))), Image.LANCZOS)
    big = sticker(big, rim)
    if aura:
        big = glow(big, aura, 10)
    can = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    can.alpha_composite(big, ((size - big.width) // 2, size - big.height + int(pad * sc * 0.7)))
    return can


def save(img, name, q=88):
    img.save(os.path.join(OUT, name + '.webp'), 'WEBP', quality=q, method=6)


def slug(name):
    s = ''.join(ch if ch.isalnum() else '_' for ch in name.lower().replace('the ', ''))
    while '__' in s:
        s = s.replace('__', '_')
    return s.strip('_')


# ------------------------------------------------------------ backgrounds

W, H, GROUND = 1024, 448, 368
SS = 2  # supersample


def ridge(rng, amp, base, n=6, rough=1.0):
    """A horizon line that wraps at W (integer periods only)."""
    xs = np.arange(W * SS) / (W * SS)
    y = np.zeros_like(xs)
    for k in range(1, n + 1):
        y += rng.uniform(0.3, 1) / k ** (1.2 / rough) * np.sin(2 * math.pi * k * xs + rng.uniform(0, 6.3))
    y = (y - y.min()) / (y.max() - y.min() + 1e-9)
    return (base - y * amp) * SS


def fill_ridge(draw, ys, color):
    pts = [(i, float(y)) for i, y in enumerate(ys)] + [(W * SS, H * SS), (0, H * SS)]
    draw.polygon(pts, fill=color)


def wrap(fn, x, *a):
    for dx in (-W * SS, 0, W * SS):
        fn(x + dx, *a)


def far(ch, rng):
    top, hor = hexrgb(ch['sky'][0]), hexrgb(ch['sky'][1])
    ground, acc = hexrgb(ch['ground']), hexrgb(ch['accent'])
    px = np.zeros((H * SS, W * SS, 3))
    t = np.clip(np.arange(H * SS) / (GROUND * SS * 0.95), 0, 1)[:, None]
    px[:] = (np.array(top) * (1 - t) + np.array(hor) * t)[:, None, :]
    img = Image.fromarray(px.astype(np.uint8))
    dark = ch['props'] in ('crystals', 'graves', 'void', 'spires', 'columns', 'webs', 'forge', 'roost', 'court')
    # glow / sun
    lay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    sx, sy = rng.uniform(0.15, 0.85) * W * SS, rng.uniform(0.18, 0.35) * H * SS
    sun = acc if dark or ch['props'] in ('volcano',) else (255, 250, 220)
    for r, al in ((150, 40), (90, 60), (48, 130 if not dark else 70)):
        wrap(lambda x, r=r, al=al: d.ellipse((x - r * SS, sy - r * SS, x + r * SS, sy + r * SS), fill=sun + (al,)), sx)
    if dark:
        for _ in range(140):
            x, y, r = rng.uniform(0, W * SS), rng.uniform(0, GROUND * SS * 0.8), rng.choice((1, 1, 2, 3))
            d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, rng.randint(80, 220)))
    lay = lay.filter(ImageFilter.GaussianBlur(6 * SS))
    img = img.convert('RGBA')
    img.alpha_composite(lay)
    # clouds / mist bands
    mist = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(mist)
    for _ in range(9):
        x, y = rng.uniform(0, W * SS), rng.uniform(0.1, 0.55) * H * SS
        w, h = rng.uniform(120, 260) * SS, rng.uniform(18, 40) * SS
        col = (255, 255, 255, 90) if not dark else hor + (60,)
        wrap(lambda x: d.ellipse((x - w, y - h, x + w, y + h), fill=col), x)
    img.alpha_composite(mist.filter(ImageFilter.GaussianBlur(14 * SS)))
    # three ridges, far to near
    for i, (amp, base, k) in enumerate(((150, 300, 0.75), (110, 330, 0.55), (70, 352, 0.3))):
        col = mix(ground, hor, k) if not dark else mix(mix(ground, top, 0.5), hor, k * 0.8)
        layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ys = ridge(rng, amp, base, rough=1.4 if ch['props'] in ('peaks', 'spires', 'crystals') else 0.9)
        fill_ridge(ld, ys, col + (255,))
        props(ch['props'], ld, ys, rng, col, acc, i)
        # light from above: a soft lighter rim
        layer = layer.filter(ImageFilter.GaussianBlur((2 - i * 0.8) * SS + 0.1))
        img.alpha_composite(layer)
        haze = Image.new('RGBA', img.size, hor + (0,))
        hz = np.zeros((H * SS, W * SS), np.uint8)
        hz[int(base * SS - amp * SS * 0.2):, :] = int(40 * (1 - i / 3))
        haze.putalpha(Image.fromarray(hz).filter(ImageFilter.GaussianBlur(20 * SS)))
        img.alpha_composite(haze)
    return img.resize((W, H), Image.LANCZOS).convert('RGB')


def props(kind, d, ys, rng, col, acc, depth):
    """World props standing on a ridge line, in the ridge's own colour."""
    n = (5, 7, 9)[depth]
    darker = mix(col, (10, 10, 20), 0.12 + depth * 0.06)

    def at(x):
        return float(ys[int(x) % len(ys)])

    for _ in range(n):
        x = rng.uniform(0, W * SS)
        y = at(x) + 6 * SS
        s = rng.uniform(0.7, 1.3) * (0.6 + depth * 0.25) * SS
        if kind == 'trees':
            def tree(x):
                d.rectangle((x - 5 * s, y - 40 * s, x + 5 * s, y), fill=darker)
                for dx, dy, r in ((0, -70, 34), (-22, -52, 24), (22, -50, 26), (0, -95, 24)):
                    d.ellipse((x + (dx - r) * s, y + (dy - r) * s, x + (dx + r) * s, y + (dy + r) * s), fill=darker)
            wrap(tree, x)
        elif kind == 'deadtrees':
            def dtree(x):
                d.line((x, y, x + 6 * s, y - 90 * s), fill=darker, width=int(8 * s))
                d.line((x + 4 * s, y - 50 * s, x - 26 * s, y - 80 * s), fill=darker, width=int(5 * s))
                d.line((x + 5 * s, y - 70 * s, x + 32 * s, y - 100 * s), fill=darker, width=int(4 * s))
            wrap(dtree, x)
        elif kind == 'crystals':
            c = mix(darker, acc, 0.35 + 0.15 * depth)
            def crys(x):
                for dx, h, w in ((0, 90, 16), (-18, 55, 11), (17, 64, 12)):
                    d.polygon([(x + (dx - w) * s, y), (x + dx * s, y - h * s), (x + (dx + w) * s, y)], fill=c)
            wrap(crys, x)
        elif kind == 'pyramids' and depth < 2:
            def pyr(x):
                d.polygon([(x - 90 * s, y + 10), (x, y - 90 * s), (x + 90 * s, y + 10)], fill=darker)
                d.polygon([(x, y - 90 * s), (x + 90 * s, y + 10), (x + 30 * s, y + 10)], fill=mix(darker, (0, 0, 0), 0.12))
            if rng.random() < 0.5:
                wrap(pyr, x)
        elif kind == 'peaks' and depth < 2:
            def snow(x):
                yy = at(x)
                d.polygon([(x - 30 * s, yy + 34 * s), (x, yy - 2), (x + 30 * s, yy + 34 * s), (x + 10 * s, yy + 24 * s),
                           (x - 8 * s, yy + 30 * s)], fill=(250, 252, 255))
            snow(float(np.argmin(ys[int(x) - 200 if x > 200 else 0:int(x) + 200]) + max(0, int(x) - 200)))
        elif kind == 'graves':
            def grave(x):
                if rng.random() < 0.5:
                    d.rounded_rectangle((x - 12 * s, y - 34 * s, x + 12 * s, y), radius=int(10 * s), fill=darker)
                else:
                    d.rectangle((x - 3 * s, y - 40 * s, x + 3 * s, y), fill=darker)
                    d.rectangle((x - 13 * s, y - 30 * s, x + 13 * s, y - 24 * s), fill=darker)
            wrap(grave, x)
        elif kind == 'volcano' and depth == 0:
            def volc(x):
                d.polygon([(x - 170 * s, y + 20), (x - 30 * s, y - 120 * s), (x + 30 * s, y - 120 * s), (x + 170 * s, y + 20)], fill=darker)
                d.polygon([(x - 26 * s, y - 120 * s), (x + 26 * s, y - 120 * s), (x + 8 * s, y - 60 * s)], fill=acc)
            if rng.random() < 0.4:
                wrap(volc, x)
        elif kind == 'columns':
            def col_(x):
                h = rng.uniform(60, 110)
                d.rectangle((x - 9 * s, y - h * s, x + 9 * s, y), fill=darker)
                d.rectangle((x - 14 * s, y - h * s - 8 * s, x + 14 * s, y - h * s), fill=darker)
            wrap(col_, x)
        elif kind == 'spires':
            def spire(x):
                h = rng.uniform(90, 160)
                d.rectangle((x - 14 * s, y - h * s, x + 14 * s, y), fill=darker)
                d.polygon([(x - 20 * s, y - h * s), (x, y - (h + 50) * s), (x + 20 * s, y - h * s)], fill=darker)
                d.rectangle((x - 3 * s, y - (h - 30) * s, x + 3 * s, y - (h - 44) * s), fill=acc)
            wrap(spire, x)
        elif kind == 'void' and depth < 2:
            def rock(x):
                yy = y - rng.uniform(120, 220) * SS
                d.polygon([(x - 40 * s, yy), (x + 36 * s, yy - 6 * s), (x + 20 * s, yy + 30 * s), (x - 6 * s, yy + 44 * s)], fill=darker)
            wrap(rock, x)
        elif kind == 'webs':
            def wtree(x):
                d.line((x, y, x + 6 * s, y - 110 * s), fill=darker, width=int(9 * s))
                d.line((x + 4 * s, y - 60 * s, x - 34 * s, y - 95 * s), fill=darker, width=int(5 * s))
                d.line((x + 5 * s, y - 85 * s, x + 40 * s, y - 120 * s), fill=darker, width=int(4 * s))
                web = mix(darker, (230, 240, 235), 0.45)
                cx, cy = x + 4 * s, y - 92 * s
                for a in range(8):
                    ang = a * math.pi / 4
                    d.line((cx, cy, cx + 34 * s * math.cos(ang), cy + 34 * s * math.sin(ang)), fill=web, width=max(1, int(1.5 * s)))
                for r in (12, 22, 32):
                    d.ellipse((cx - r * s, cy - r * s, cx + r * s, cy + r * s), outline=web, width=max(1, int(1.3 * s)))
            wrap(wtree, x)
        elif kind == 'isles' and depth < 2:
            def isle(x):
                yy = y - rng.uniform(110, 200) * SS
                w = rng.uniform(50, 90) * s
                d.polygon([(x - w, yy), (x + w, yy), (x + w * 0.4, yy + w * 0.6), (x, yy + w * 1.1), (x - w * 0.5, yy + w * 0.5)],
                          fill=mix(darker, (120, 90, 70), 0.4))
                d.ellipse((x - w * 1.05, yy - 12 * s, x + w * 1.05, yy + 10 * s), fill=mix(col, (90, 180, 80), 0.5))
            wrap(isle, x)
        elif kind == 'forge':
            def chim(x):
                h = rng.uniform(80, 150)
                d.rectangle((x - 16 * s, y - h * s, x + 16 * s, y), fill=darker)
                d.rectangle((x - 20 * s, y - h * s - 8 * s, x + 20 * s, y - h * s), fill=darker)
                for k in range(2):
                    d.rectangle((x - 6 * s, y - (h - 25 - k * 35) * s, x + 6 * s, y - (h - 37 - k * 35) * s), fill=acc)
            wrap(chim, x)
        elif kind == 'roost':
            def crag(x):
                h = rng.uniform(80, 170)
                d.polygon([(x - 40 * s, y + 5), (x - 8 * s, y - h * s), (x + 4 * s, y - (h - 30) * s), (x + 36 * s, y + 5)], fill=darker)
                if rng.random() < 0.4:
                    d.ellipse((x - 26 * s, y - (h - 10) * s, x + 20 * s, y - (h - 30) * s), fill=mix(darker, acc, 0.35))
            wrap(crag, x)
        elif kind == 'court':
            def tower(x):
                h = rng.uniform(80, 150)
                d.rectangle((x - 18 * s, y - h * s, x + 18 * s, y), fill=darker)
                d.ellipse((x - 24 * s, y - (h + 34) * s, x + 24 * s, y - (h - 8) * s), fill=darker)
                d.polygon([(x - 4 * s, y - (h + 30) * s), (x, y - (h + 60) * s), (x + 4 * s, y - (h + 30) * s)], fill=darker)
                for k in range(3):
                    d.rounded_rectangle((x - 5 * s, y - (h - 20 - k * 30) * s, x + 5 * s, y - (h - 34 - k * 30) * s),
                                        radius=int(4 * s), fill=acc)
            wrap(tower, x)


def runes(d, x, y, s, col, rng):
    """A short carved glyph, made of two or three strokes."""
    d.line((x, y, x, y + 16 * s), fill=col, width=max(1, int(2.2 * s)))
    for _ in range(rng.randint(1, 2)):
        a, b = rng.choice(((0, 0), (0, 6), (0, 10))), rng.choice((-7, 7))
        d.line((x, y + a[1] * s, x + b * s, y + (a[1] + rng.choice((4, -4, 6))) * s), fill=col, width=max(1, int(2.2 * s)))


def near(ch, rng):
    """Transparent above the ground, then the rune-stone path."""
    ground, acc = hexrgb(ch['ground']), hexrgb(ch['accent'])
    stone = mix((132, 132, 122), ground, 0.28)
    dark = ch['props'] in ('crystals', 'graves', 'void', 'spires', 'columns', 'volcano', 'webs', 'forge', 'roost', 'court')
    if dark:
        stone = mix(stone, (40, 34, 60), 0.35)
    img = Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top, face = (GROUND - 10) * SS, (GROUND + 30) * SS
    # top slabs
    d.rectangle((0, top, W * SS, face), fill=mix(stone, (0, 0, 0), 0.25) + (255,))
    x = 0
    while x < W * SS:
        w = rng.uniform(70, 130) * SS
        for row, (y0, y1) in enumerate(((top + 2 * SS, top + 18 * SS), (top + 20 * SS, face - 2 * SS))):
            off = 0 if row == 0 else w * 0.45
            c = mix(stone, (255, 255, 255), rng.uniform(0.0, 0.14))
            def slab(xx):
                d.rounded_rectangle((xx + off + 2 * SS, y0, xx + off + w - 2 * SS, y1), radius=6 * SS, fill=c + (255,))
                d.line((xx + off + 6 * SS, y0 + 2 * SS, xx + off + w - 8 * SS, y0 + 2 * SS),
                       fill=mix(c, (255, 255, 255), 0.25) + (255,), width=2 * SS)
            wrap(slab, x)
        x += w
    # front face: big blocks with carved runes
    d.rectangle((0, face, W * SS, H * SS), fill=mix(stone, (0, 0, 0), 0.4) + (255,))
    x, bw = 0, W * SS / 4
    for i in range(4):
        c = mix(stone, (0, 0, 0), rng.uniform(0.12, 0.2))
        d.rounded_rectangle((x + 3 * SS, face + 3 * SS, x + bw - 3 * SS, H * SS + 10), radius=5 * SS, fill=c + (255,))
        d.line((x + 8 * SS, face + 5 * SS, x + bw - 8 * SS, face + 5 * SS), fill=mix(c, (255, 255, 255), 0.18) + (255,), width=2 * SS)
        gx = x + 22 * SS
        rcol = mix(c, (0, 0, 0), 0.45) + (255,)
        while gx < x + bw - 22 * SS:
            runes(d, gx, face + 20 * SS, SS, rcol, rng)
            gx += rng.uniform(26, 34) * SS
        x += bw
    # moss / snow / embers on the lip
    lip = {'peaks': (245, 250, 255), 'dunes': (236, 200, 120), 'volcano': acc, 'void': acc, 'crystals': acc}.get(
        ch['props'], mix(ground, acc, 0.25))
    for _ in range(70):
        x = rng.uniform(0, W * SS)
        r = rng.uniform(4, 11) * SS
        al = 255 if ch['props'] not in ('volcano', 'void', 'crystals') else 170
        def tuft(x):
            d.ellipse((x - r * 1.6, top - r * 0.6, x + r * 1.6, top + r * 0.7), fill=lip + (al,))
        wrap(tuft, x)
    img = img.filter(ImageFilter.GaussianBlur(0.6 * SS))
    # glow runes on the face for dark worlds
    if dark:
        g = Image.new('RGBA', img.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(g)
        x = 0
        for i in range(4):
            gx = x + 22 * SS
            while gx < x + bw - 22 * SS:
                runes(gd, gx, face + 20 * SS, SS, acc + (200,), rng)
                gx += rng.uniform(26, 34) * SS
            x += bw
        img.alpha_composite(g.filter(ImageFilter.GaussianBlur(3 * SS)))
        img.alpha_composite(g)
    return img.resize((W, H), Image.LANCZOS)


# ------------------------------------------------------------ build

data = []
for ch in CHAPTERS:
    foes = []
    for idx, (name, ar, kind, look, quote, quote_ar) in enumerate(ch['foes'] + [ch['boss']]):
        boss = idx == 5
        fid = 'foe_' + slug(name)
        foes.append(dict(name=name, ar=ar, img=fid, kind=kind, quote=quote, quote_ar=quote_ar))
        if DATA_ONLY:
            continue
        img = recolor(src(kind), **look)
        save(place(img, 320, aura=ch['accent'] if boss else None), fid)
    data.append(dict(ch, foes=foes))
    if DATA_ONLY:
        continue
    rng = random.Random(ch['id'])
    save(far(ch, rng), f'bg_{ch["id"]}_far', q=84)
    save(near(ch, rng), f'bg_{ch["id"]}_near', q=88)

for cls in () if DATA_ONLY else ('knight', 'ranger', 'monk', 'berserker'):
    save(place(src(cls), 320, fill=0.86), 'hero_' + cls)
if not DATA_ONLY:
    save(place(recolor(src('slime'), hue=-100, sat=1.05, val=1.08), 192), 'pet_pip')
for kind, (pic, look) in () if DATA_ONLY else GEAR.items():
    save(place(recolor(src(pic), **look), 192, fill=0.84, rim=2), 'gear_' + kind)

print('worlds', len(data), 'foes', sum(len(d['foes']) for d in data), 'files', len(os.listdir(OUT)),
      'kB', sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT)) // 1024)

# ------------------------------------------------------------ Dart data

ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'XIII', 'XIV', 'XV']
STEP = [1.0, 1.15, 1.3, 1.45, 1.6]
GROW = 1.10  # each world hits this much harder than the one before


def dstr(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


lines = ['// GENERATED by tool/art/build.py from tool/art/roster.py. Do not edit.',
         '// Every creature here is painted art in assets/art.',
         '', "part of 'chapters.dart';", '', 'const chapters = [']
ar = {}
for i, ch in enumerate(data):
    base = 0.5 * GROW ** i
    foes = ch['foes']
    ar[ch['name']] = ch['ar']
    ar[ch['blurb']] = ch['blurb_ar']
    lines.append('  ChapterDef(')
    lines.append(f'    number: {i + 1},')
    lines.append(f"    id: '{ch['id']}',")
    lines.append(f"    roman: 'Chapter {ROMAN[i]}',")
    lines.append(f"    name: {dstr(ch['name'])},")
    lines.append(f"    blurb: {dstr(ch['blurb'])},")
    lines.append('    foes: [')
    for f, step in zip(foes[:5], STEP):
        lines.append(f"      FoeKind({dstr(f['name'])}, '{f['img']}', {base * step:.3f}, {dstr(f['quote'])}, "
                     f"FoeAbility.{ABILITY[f['kind']]}{', true' if f['kind'] in FRONT else ''}),")
    lines.append('    ],')
    b = foes[5]
    lines.append(f"    boss: FoeKind({dstr(b['name'])}, '{b['img']}', {base * 2.2:.3f}, {dstr(b['quote'])}, "
                 f"FoeAbility.{ABILITY[b['kind']]}{', true' if b['kind'] in FRONT else ''}),")
    lines.append(f'    startLevel: {START_LEVELS[i]},')
    lines.append(f"    ground: 0xFF{ch['ground'].lstrip('#').upper()},")
    lines.append('  ),')
    for f in foes:
        ar[f['name']] = f['ar']
        ar[f['quote']] = f['quote_ar']
lines.append('];')
open(os.path.join(ROOT, 'lib', 'modes', 'rpg', 'world_data.dart'), 'w').write('\n'.join(lines) + '\n')
os.makedirs(os.path.join(ROOT, 'lib', 'i18n'), exist_ok=True)
open(os.path.join(ROOT, 'lib', 'i18n', 'world_ar.dart'), 'w').write(
    '// GENERATED by tool/art/build.py from tool/art/roster.py. Do not edit.\n\n'
    'const worldAr = <String, String>{\n' + ''.join(f'  {dstr(k)}: {dstr(v)},\n' for k, v in ar.items()) + '};\n')
print('wrote lib/modes/rpg/world_data.dart and lib/i18n/world_ar.dart')
