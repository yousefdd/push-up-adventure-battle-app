"""RepRaid's adventure roster: fifteen worlds, five foes and a boss each.

Every foe is one of the six painted cut-outs in tool/art/src (the user's own
reference art), recoloured for its world with a look L(...). `build.py` turns this into
sprites, backgrounds, lib/modes/rpg/world_data.dart and the Arabic names in
lib/i18n/world_ar.dart.

Each foe: (English name, Arabic name, creature, look, English line, Arabic line).
"""


def L(hue=0, sat=1.0, val=1.0, tint=None, amt=0.0, band=None):
    return dict(hue=hue, sat=sat, val=val, tint=tint, amt=amt, band=band)


CUTOUTS = ('slime', 'boar', 'mushroom', 'wolf', 'imp', 'beholder')

CHAPTERS = [
    dict(id='glade', name='Greenwood Glade', ar='غابة الخُضرة',
         blurb='Soft hills and old oaks. Every legend starts with one correct rep.',
         blurb_ar='تلال ناعمة وأشجار بلوط عتيقة. كل أسطورة تبدأ بضغطة صحيحة واحدة.',
         sky=('#6cc4ea', '#e4f6ff'), ground='#5aa04a', accent='#a8ff7a', props='trees', foes=[
            ('Moss Slime', 'هلام الطحلب', 'slime', L(), 'It wobbles. It is also furious.', 'يتمايل… وهو غاضب جدًا أيضًا.'),
            ('Capling', 'فُطيرة', 'mushroom', L(), 'Small, spotted and stubborn.', 'صغير، مُنقّط، وعنيد.'),
            ('Rocklet', 'حُجيرة', 'rock_sprout', L(), 'A pebble that learned to bite.', 'حصاة تعلّمت العضّ.'),
            ('Meadow Frog', 'ضفدع المرج', 'frog', L(), 'Its tongue is faster than you.', 'لسانه أسرع منك.'),
            ('Shell Snail', 'الحلزون المدرّع', 'snail', L(), 'Slow, but it never stops.', 'بطيء، لكنه لا يتوقف أبدًا.'),
         ], boss=('The Elder Oak', 'البلّوطة العتيقة', 'elder_treant', L(),
                  'Older than the glade, and angrier.', 'أقدم من الغابة… وأشدّ غضبًا.')),
    dict(id='bog', name='Murkmire Bog', ar='مستنقع الوحل',
         blurb='Black water, rotten logs, and something humming under the reeds.',
         blurb_ar='ماء أسود، جذوع متعفنة، وشيء يهمهم تحت القصب.',
         sky=('#5e6e52', '#b8c08a'), ground='#4a5a3a', accent='#c8ff60', props='deadtrees', foes=[
            ('Bog Toad', 'علجوم المستنقع', 'swamp_toad', L(), 'Sits in the mud and waits for you.', 'يجلس في الوحل وينتظرك.'),
            ('Swamp Snapper', 'النبتة المفترسة', 'snap_plant', L(), 'Pretty petals, prettier teeth.', 'بتلات جميلة… وأسنان أجمل.'),
            ('Bog Sludge', 'وحل المستنقع', 'bog_sludge', L(), 'Smells exactly like it looks.', 'رائحته تمامًا كما يبدو.'),
            ('Venom Serpent', 'أفعى السمّ', 'venom_serpent', L(), 'It coils where the water is deepest.', 'تلتفّ حيث الماء أعمق.'),
            ('Rotcap Brute', 'عملاق العفن', 'rot_brute', L(), 'Its spores make knees wobble.', 'أبواغه ترخي الركب.'),
         ], boss=('The Bog Troll', 'غول المستنقع', 'moss_troll', L(),
                  'The bog grew a fist.', 'المستنقع نبتت له قبضة.')),
    dict(id='webwood', name='Webwood Hollow', ar='جوف الشِّباك',
         blurb='Trees wrapped in silk. Every branch is a trap, every shadow has legs.',
         blurb_ar='أشجار ملفوفة بالحرير. كل غصن فخّ، وكل ظلّ له أرجل.',
         sky=('#2a3a3a', '#6a8a7a'), ground='#3a4a3a', accent='#c0ffd0', props='webs', foes=[
            ('Night Bat', 'خفاش الليل', 'night_bat', L(), 'It sees you. You don’t see it.', 'يراك… وأنت لا تراه.'),
            ('Giant Hornet', 'الدبّور العملاق', 'hornet', L(), 'You hear it before you see it.', 'تسمعه قبل أن تراه.'),
            ('Gremlin', 'العفريت المشاغب', 'gremlin', L(), 'Giggles from the treetops.', 'يقهقه من أعالي الشجر.'),
            ('Mantis Sprite', 'جنّية السرعوف', 'mantis_fairy', L(), 'Beautiful wings, sharper arms.', 'أجنحة جميلة وأذرع أحدّ.'),
            ('Shadow Wolf', 'ذئب الظلال', 'wolf', L(val=0.6, tint='#6a4aa0', amt=0.35), 'Only its eyes catch the light.', 'لا يلمع منه إلا عيناه.'),
         ], boss=('The Hollow Maw', 'الفمّ الأجوف', 'spiked_maw', L(),
                  'Every path in the wood ends in its mouth.', 'كل درب في الغابة ينتهي في فمه.')),
    dict(id='caves', name='Glimmer Caves', ar='كهوف البريق',
         blurb='Crystals hum in the dark. Every echo is a warning.',
         blurb_ar='بلّورات تطنّ في الظلام. كل صدى هو تحذير.',
         sky=('#1e1a3a', '#4a3e7a'), ground='#3a3450', accent='#6af0ff', props='crystals', foes=[
            ('Crystal Slime', 'هلام البلّور', 'slime', L(hue=65), 'Pretty. Pointy. Angry.', 'جميل. حادّ. غاضب.'),
            ('Crystal Beetle', 'خنفساء البلّور', 'crystal_beetle', L(), 'Its shell is worth a fortune. Try taking it.', 'صدفتها تساوي ثروة… حاول أن تأخذها.'),
            ('Cave Cyclops', 'العين الواحدة', 'cyclops_blob', L(), 'One eye, zero blinking.', 'عين واحدة، ولا ترمش أبدًا.'),
            ('Shard Spider', 'عنكبوت الشظايا', 'crystal_spider', L(), 'Eight legs, all of them blades.', 'ثماني أرجل، كلها شفرات.'),
            ('Stone Golem', 'عملاق الحجر', 'stone_golem', L(), 'A rock with a grudge.', 'صخرة تحمل ضغينة.'),
         ], boss=('Crystal Colossus', 'عملاق البلّور الأكبر', 'crystal_colossus', L(),
                  'The mountain’s heart, and it beats.', 'قلب الجبل… وهو ينبض.')),
    dict(id='dunes', name='Sunscorch Dunes', ar='كثبان الشمس الحارقة',
         blurb='Heat shimmers over endless sand. Old kings sleep under it.',
         blurb_ar='سراب فوق رمال لا تنتهي، وتحتها ينام ملوك قدامى.',
         sky=('#f09a48', '#fff0c0'), ground='#e0b060', accent='#ffe060', props='pyramids', foes=[
            ('Cactus Puff', 'كرة الصبّار', 'spike_ball', L(hue=35, sat=0.8, val=1.1), 'Do not hug.', 'لا تعانقه.'),
            ('Sun Crab', 'سلطعون الشمس', 'crab', L(hue=30, val=1.1), 'It burrows, then it pinches.', 'يحفر… ثم يقرص.'),
            ('Dune Goblin', 'غوبلن الكثبان', 'goblin', L(hue=15, val=1.2, sat=0.8), 'A whirlwind with teeth.', 'زوبعة لها أسنان.'),
            ('Sand Scorpion', 'عقرب الرمال', 'void_scorpion', L(hue=150, val=1.15), 'Golden shell, poison tail.', 'درع ذهبي وذيل سامّ.'),
            ('Bone Jackal', 'ابن آوى العظمي', 'wolf', L(tint='#d8b070', amt=0.5, val=1.05), 'It guards the tombs.', 'يحرس المقابر.'),
         ], boss=('The Sand Wyrm', 'تنين الرمال', 'venom_serpent', L(hue=-80, val=1.1),
                  'The dunes move when it breathes.', 'الكثبان تتحرك حين يتنفّس.')),
    dict(id='isles', name='Sky Isles', ar='الجزر الطائرة',
         blurb='Islands adrift on the wind. Don’t look down.',
         blurb_ar='جزر تطفو على الريح. لا تنظر إلى الأسفل.',
         sky=('#4aa8f0', '#e8f8ff'), ground='#7ac06a', accent='#ffffff', props='isles', foes=[
            ('Cloud Wisp', 'طيف الغيم', 'wisp', L(sat=0.3, val=1.15), 'Soft as a cloud, mean as a storm.', 'ناعم كالغيمة، شرس كالعاصفة.'),
            ('Sky Dragonfly', 'يعسوب السماء', 'dragonfly', L(), 'It rides the wind like a kite.', 'يركب الريح كالطائرة الورقية.'),
            ('Cloud Penguin', 'بطريق الغيم', 'flame_penguin', L(sat=0.3, val=1.35), 'It flies. Nobody told it penguins can’t.', 'يطير… لم يخبره أحد أن البطاريق لا تطير.'),
            ('Cloud Jelly', 'قنديل الغيم', 'jellyfish', L(sat=0.35, val=1.2), 'It drifts in, stings, drifts off.', 'يطفو، يلسع، ثم يطفو بعيدًا.'),
            ('Breeze Sprite', 'جنّي النسيم', 'imp', L(hue=175, sat=0.6, val=1.15), 'Laughs like a whistle.', 'ضحكته كالصفير.'),
         ], boss=('The Storm Griffin', 'عنقاء العاصفة', 'griffin', L(),
                  'King of every wind that blows.', 'ملك كل ريح تهبّ.')),
    dict(id='frost', name='Frostfang Peaks', ar='قمم الناب الجليدي',
         blurb='Wind like knives. The snow remembers every footstep.',
         blurb_ar='ريح كالسكاكين. والثلج يتذكر كل خطوة.',
         sky=('#8cc0ec', '#eef8ff'), ground='#e0ecf8', accent='#bff0ff', props='peaks', foes=[
            ('Frost Slime', 'هلام الصقيع', 'slime', L(hue=70, sat=0.65, val=1.15), 'Half slime, half ice cube.', 'نصفه هلام ونصفه مكعّب ثلج.'),
            ('Frost Wolf', 'ذئب الصقيع', 'frost_wolf', L(), 'White on white. Watch the eyes.', 'أبيض على أبيض… راقب العينين.'),
            ('Ice Golem', 'عملاق الجليد', 'ice_golem', L(), 'Carved from a glacier.', 'منحوت من نهر جليدي.'),
            ('Frostflame Penguin', 'بطريق اللهب البارد', 'flame_penguin', L(), 'Cute. Freezing. Furious.', 'لطيف… متجمّد… وغاضب.'),
            ('Frost Wisp', 'طيف الصقيع', 'wisp', L(), 'A cold breath that learned to fight.', 'نفَس بارد تعلّم القتال.'),
         ], boss=('Rimehorn', 'قرن الصقيع', 'frost_spirit', L(),
                  'The blizzard has a leader.', 'للعاصفة الثلجية قائد.')),
    dict(id='crypt', name='Hollow Crypt', ar='السرداب الأجوف',
         blurb='Candles that never melt. Bones that never rest.',
         blurb_ar='شموع لا تذوب، وعظام لا تهدأ.',
         sky=('#221c38', '#54466a'), ground='#4a4450', accent='#7affb0', props='graves', foes=[
            ('Grave Wisp', 'طيف القبور', 'wisp', L(hue=-80), 'You can see right through it.', 'يمكنك أن ترى من خلاله.'),
            ('Bone Knight', 'فارس العظام', 'skeleton_knight', L(), 'Loyal past death.', 'وفيّ حتى بعد الموت.'),
            ('Grave Reaper', 'حاصد القبور', 'grave_reaper', L(), 'His lantern shows the way down.', 'فانوسه يدلّك على الطريق… إلى الأسفل.'),
            ('Cursed Grimoire', 'الكتاب الملعون', 'grimoire', L(), 'Every page is a curse.', 'كل صفحة فيه لعنة.'),
            ('Barghest', 'الكلب الأسود', 'wolf', L(val=0.55, tint='#5a3a6a', amt=0.3), 'Black dog, bad omen.', 'كلب أسود… نذير شؤم.'),
         ], boss=('The Soul Reaper', 'حاصد الأرواح', 'soul_reaper', L(),
                  'He traded his heart for forever.', 'باع قلبه مقابل الخلود.')),
    dict(id='forge', name='Clockwork Forge', ar='المصهر الآلي',
         blurb='Gears grind, hammers fall, and the machines have learned to hate.',
         blurb_ar='تروس تطحن، مطارق تهوي، والآلات تعلّمت الكراهية.',
         sky=('#3a2a24', '#a0603a'), ground='#4a3a34', accent='#ffa03a', props='forge', foes=[
            ('Rust Boar', 'خنزير الصدأ', 'boar', L(sat=0.5, tint='#a05a3a', amt=0.4), 'It squeaks when it charges.', 'يصرّ حين يهجم.'),
            ('Goblin Raider', 'الغوبلن المغير', 'goblin', L(), 'Short, sneaky, and armed.', 'قصير، ماكر، ومسلّح.'),
            ('Iron Golem', 'عملاق الحديد', 'stone_golem', L(sat=0.2, val=1.1, tint='#8a9ab0', amt=0.35), 'Built to work. Chose to fight.', 'صُنع ليعمل… واختار القتال.'),
            ('Ember Salamander', 'سمندل الجمر', 'salamander', L(), 'It swims through fire.', 'يسبح عبر النار.'),
            ('Soot Gremlin', 'عفريت السُّخام', 'gremlin', L(val=0.7, tint='#ff8a3a', amt=0.25), 'It lives in the chimneys.', 'يعيش في المداخن.'),
         ], boss=('The Forge Beast', 'وحش المصهر', 'magma_golem', L(),
                  'Its heart is the furnace.', 'قلبه هو الفرن.')),
    dict(id='caldera', name='Cinder Caldera', ar='فوهة الرماد',
         blurb='The ground is hot, the air is hotter, the foes are hottest.',
         blurb_ar='الأرض حارّة، والهواء أحرّ، والأعداء أحرّ من الجميع.',
         sky=('#7a2418', '#f08a3a'), ground='#4a2a24', accent='#ff8a2a', props='volcano', foes=[
            ('Fire Imp', 'عفريت النار', 'imp', L(), 'Giggles while it burns.', 'يضحك وهو يحترق.'),
            ('Magma Toad', 'علجوم الحمم', 'swamp_toad', L(hue=-80, sat=1.3, val=0.95), 'Do not touch. Punch.', 'لا تلمسه… الكمه.'),
            ('Fire Elemental', 'روح النار', 'fire_elemental', L(), 'A bonfire with a temper.', 'نار مخيّم بمزاج سيّئ.'),
            ('Hellhound', 'كلب الجحيم', 'frost_wolf', L(hue=170, sat=1.4, val=0.9), 'Its howl is a furnace.', 'عواؤه فرن مشتعل.'),
            ('Red Demon', 'الشيطان الأحمر', 'red_demon', L(), 'It came up with the lava.', 'صعد مع الحمم.'),
         ], boss=('Pyrrax', 'بيراكس', 'lava_dragon', L(),
                  'The volcano’s oldest child.', 'أكبر أبناء البركان.')),
    dict(id='temple', name='Drowned Temple', ar='المعبد الغارق',
         blurb='Columns under the waves. Prayers turned to bubbles.',
         blurb_ar='أعمدة تحت الأمواج، وصلوات صارت فقاعات.',
         sky=('#164462', '#46a0b0'), ground='#2a5a5a', accent='#5af0ff', props='columns', foes=[
            ('Abyss Shark', 'قرش الهاوية', 'abyss_shark', L(), 'All teeth, no mercy.', 'كلّه أسنان، ولا رحمة.'),
            ('Moon Jelly', 'قنديل القمر', 'jellyfish', L(), 'Pretty. Do not hug.', 'جميل… لا تعانقه.'),
            ('Tide Crab', 'سلطعون المدّ', 'crab', L(hue=180, sat=0.8), 'Its claws open clams and shins.', 'كلّاباته تفتح المحار… والسيقان.'),
            ('Reef Frog', 'ضفدع الشِّعاب', 'frog', L(hue=100, sat=1.1), 'It croaks in bubbles.', 'ينقّ فقاعات.'),
            ('Abyss Eye', 'عين الهاوية', 'beholder', L(hue=-100, sat=0.9), 'It saw the temple sink.', 'رأت المعبد وهو يغرق.'),
         ], boss=('The Deep One', 'ساكن الأعماق', 'kraken_eye', L(),
                  'The sea’s own appetite.', 'شهيّة البحر نفسه.')),
    dict(id='roost', name='Dragon’s Roost', ar='عشّ التنانين',
         blurb='Scorched cliffs and bones of the brave. The eggs are hatching.',
         blurb_ar='منحدرات محروقة وعظام الشجعان. والبيض بدأ يفقس.',
         sky=('#5a1a2a', '#e0703a'), ground='#4a3030', accent='#ffcf3f', props='roost', foes=[
            ('Ember Whelp', 'تنين صغير', 'baby_dragon', L(), 'Small wings, big attitude.', 'أجنحة صغيرة وغرور كبير.'),
            ('Lava Beast', 'وحش الحمم', 'lava_beast', L(), 'It sleeps in the crater. Not now.', 'ينام في الفوهة… ليس الآن.'),
            ('Ash Bat', 'خفاش الرماد', 'night_bat', L(sat=0.2, val=0.85), 'It nests in the smoke.', 'يعشّش في الدخان.'),
            ('Blaze Boar', 'خنزير اللهيب', 'boar', L(hue=-10, sat=1.4, val=0.8, tint='#ff8a2a', amt=0.3), 'Its tusks glow red.', 'أنيابه تتوهّج بالأحمر.'),
            ('Cinder Salamander', 'سمندل الرماد', 'salamander', L(sat=0.4, val=0.8), 'It hatched in the ashes.', 'فقس في الرماد.'),
         ], boss=('The Elder Wyrm', 'التنين العجوز', 'lava_dragon', L(hue=110, sat=0.9),
                  'It has eaten heroes with better gear than yours.', 'التهم أبطالًا عُدّتهم أفضل من عُدّتك.')),
    dict(id='citadel', name='Stormcrown Citadel', ar='قلعة تاج العاصفة',
         blurb='Lightning on every spire. The storm keeps a guard.',
         blurb_ar='برق على كل برج. والعاصفة لها حرّاس.',
         sky=('#262c4c', '#6a7aa0'), ground='#3a3e50', accent='#ffe060', props='spires', foes=[
            ('Spark Dragonfly', 'يعسوب الشرر', 'dragonfly', L(hue=-170, val=1.15), 'It zips between lightning bolts.', 'يتنقّل بين الصواعق.'),
            ('Thunder Wolf', 'ذئب الرعد', 'frost_wolf', L(hue=30, val=1.05), 'Its bark rolls for miles.', 'نباحه يتدحرج أميالًا.'),
            ('Volt Elemental', 'روح البرق', 'fire_elemental', L(hue=180, val=1.15), 'Static in a bad mood.', 'كهرباء ساكنة بمزاج سيّئ.'),
            ('Storm Hornet', 'دبّور العاصفة', 'hornet', L(hue=180), 'Its sting is a lightning bolt.', 'لسعته صاعقة.'),
            ('Storm Eye', 'عين العاصفة', 'beholder', L(hue=-50), 'The eye of the storm, literally.', 'عين العاصفة… حرفيًا.'),
         ], boss=('The Iron Mammoth', 'الماموث الحديدي', 'moss_mammoth', L(sat=0.25, val=1.05, tint='#8a9ab0', amt=0.3),
                  'It has never left its post.', 'لم يترك موقعه قطّ.')),
    dict(id='court', name='Nightmare Court', ar='بلاط الكوابيس',
         blurb='A palace built from bad dreams. The guests never leave.',
         blurb_ar='قصر مبنيّ من الأحلام السيئة. ضيوفه لا يغادرون أبدًا.',
         sky=('#1a0e24', '#5a2a5a'), ground='#2a1a30', accent='#ff4a8a', props='court', foes=[
            ('Nightmare Steed', 'جواد الكوابيس', 'nightmare_horse', L(), 'It gallops through bad dreams.', 'يركض عبر الأحلام السيئة.'),
            ('Hex Grimoire', 'كتاب اللعنات', 'grimoire', L(hue=60), 'It reads you.', 'هو من يقرؤك.'),
            ('Dreamcap', 'فطر الأحلام', 'mushroom', L(hue=-40, val=0.8), 'One sniff and you never wake.', 'شمّة واحدة ولن تستيقظ أبدًا.'),
            ('Hex Imp', 'عفريت اللعنات', 'imp', L(hue=-60, sat=1.1), 'Every giggle is a curse.', 'كل ضحكة منه لعنة.'),
            ('Dread Scorpion', 'عقرب الرعب', 'void_scorpion', L(), 'Its sting lasts all night.', 'لسعته تدوم طوال الليل.'),
         ], boss=('The Nightmare King', 'ملك الكوابيس', 'blood_demon', L(),
                  'It feasts on every hero who sleeps.', 'يتغذّى على كل بطل ينام.')),
    dict(id='void', name='Starfall Void', ar='فراغ النجوم المتساقطة',
         blurb='Past the last star. Gravity is a suggestion here.',
         blurb_ar='ما بعد آخر نجمة. الجاذبية هنا مجرد اقتراح.',
         sky=('#100a26', '#46287a'), ground='#2a1a4a', accent='#ff5af0', props='void', foes=[
            ('Void Slime', 'هلام الفراغ', 'slime', L(hue=150), 'A hole in the world, bouncing.', 'ثقب في العالم… يقفز.'),
            ('Void Widow', 'أرملة الفراغ', 'widow_spider', L(), 'It weaves between stars.', 'تنسج بين النجوم.'),
            ('Star Snail', 'حلزون النجوم', 'snail', L(hue=-60, val=1.1), 'It carries a galaxy on its back.', 'يحمل مجرّة على ظهره.'),
            ('Void Blob', 'كتلة الفراغ', 'cyclops_blob', L(hue=90), 'It watched the first dawn.', 'شهدت الفجر الأول.'),
            ('Void Bat', 'خفاش الفراغ', 'shadow_bat', L(), 'Your shadow, but meaner.', 'ظلّك… لكن أشرس.'),
         ], boss=('The Void Eye', 'عين الفراغ', 'beholder', L(hue=30, val=0.95, sat=1.15),
                  'The end of the map. The end of the road.', 'نهاية الخريطة… ونهاية الطريق.')),
]

# Hero level at day 0 of each world, tuned by tool/art/tune (see test/chapters_test.dart).
START_LEVELS = [3, 3, 4, 5, 8, 10, 12, 15, 17, 21, 25, 28, 31, 35, 41]

# Gear icons: kind id → (source picture, look). Ids match lib/modes/rpg/gear.dart.
GEAR = {
    'sword': ('sword', L()),
    'bow': ('sword', L(hue=-150)),
    'axe': ('axe', L()),
    'staff': ('axe', L(hue=-150, sat=0.9)),
    'plate': ('shield', L()),
    'robe': ('shield', L(sat=0.1, val=1.1)),
    'helm': ('helm', L()),
    'hood': ('helm', L(tint='#e0b040', amt=0.45)),
    'greaves': ('boots', L()),
    'sandals': ('boots', L(hue=-140, sat=1.2, band=(90, 190))),
    'sapphire': ('ring', L()),
    'ruby': ('ring', L(hue=150, sat=1.1, band=(170, 270))),
    'star': ('amulet', L()),
    'fang': ('amulet', L(hue=180, sat=1.1, band=(170, 270))),
}
