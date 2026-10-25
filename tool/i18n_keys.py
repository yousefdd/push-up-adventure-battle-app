"""Lists every English string the app passes through tr(): literal tr('...')
calls in lib/, plus the data tables whose fields are translated where they are
shown. test/i18n_test.dart checks each has Arabic in lib/i18n/ar.dart.

    python3 tool/i18n_keys.py          (prints one key per line)
"""
import glob
import re

LIT = r"'((?:[^'\\]|\\.)*)'"


def unq(s):
    return s.replace("\\'", "'").replace('\\$', '$')


keys = []


def add(k):
    if k and k not in keys:
        keys.append(k)


for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
    if f.split('/')[-1] in ('world_data.dart', 'world_ar.dart', 'ar.dart'):
        continue
    src = open(f).read()
    for m in re.finditer(r"\btr\(\s*" + LIT, src):
        add(unq(m.group(1)))
    for m in re.finditer(r"\btr\(\s*(?:const\s*)?\[([^\]]*)\]", src):  # tr(const ['A', 'B'][i])
        for x in re.finditer(LIT, m.group(1)):
            add(unq(x.group(1)))
    for m in re.finditer(r"\btr\([^()]*\?\s*" + LIT + r"\s*:\s*" + LIT, src):  # tr(c ? 'a' : 'b')
        add(unq(m.group(1)))
        add(unq(m.group(2)))

DATA = {
    'lib/modes/rpg/adventure_rules.dart': [
        r"Skill\('\w+',\s*" + LIT + r",\s*" + LIT,          # name, text
        r"Story\(\s*" + LIT,                                 # story text
        r"Effect\(\s*" + LIT,                                # tags
        r"WheelSlice\(\s*" + LIT,                            # wheel labels
        r"Choice\(\s*" + LIT,                                # choice text
        r"ChoiceOption\(\s*" + LIT,                          # choice labels
        r"Loot\([^,]+,\s*'[^']*',\s*" + LIT,                 # loot names
    ],
    'lib/modes/rpg/chapters.dart': [
        r"HeroClass\(\s*'\w+',\s*" + LIT + r",\s*" + LIT + r",\s*" + LIT,
        r"special:\s*" + LIT, r"specialText:\s*" + LIT,
        r"^\s*\w+\(" + LIT + r",\s*[\d.]+\)",               # tiers
    ],
    'lib/modes/rpg/gear.dart': [r"GearKind\('\w+',\s*Slot\.\w+,\s*" + LIT, r"^\s*\w+\(" + LIT + r",\s*[\d.]+\)"],
    'lib/engine/exercise.dart': [r"label:\s*" + LIT, r"blurb:\s*" + LIT],
    'lib/engine/rep_engine.dart': [r"return\s+" + LIT, r'return\s+"([^"]*)"'],
    'lib/modes/online/duel_math.dart': [r"const taunts = \[([^\]]*)\]"],
    'lib/modes/rpg/run_controller.dart': [r"switch \(stat\) \{([^}]*)\}"],
}
for f, pats in DATA.items():
    src = open(f).read()
    for p in pats:
        for m in re.finditer(p, src, re.M):
            for g in m.groups():
                if g is None:
                    continue
                inner = list(re.finditer(LIT, g))
                if p.startswith('switch'):
                    for x in re.finditer(r"=> " + LIT, g):
                        add(unq(x.group(1)))
                elif p.startswith('const taunts'):
                    for x in inner:
                        add(unq(x.group(1)))
                else:
                    add(unq(g))

if __name__ == '__main__':
    for k in keys:
        print(k)
