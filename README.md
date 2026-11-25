# Dragonslayers

A 3D action / platformer / lite-RPG for four players, online and on one couch, built in
Godot 4.6 on KayKit and Kenney art.

Up to four heroes cross a 16-chunk world that is randomly assembled every run -- from the
beach, across the ground and the highlands -- finding gear on the way, and climb the mountain
to kill the dragon. Each hero fights with their own weapon; everything else they can do comes
from the gear they find. Nearly every attack in the game — theirs and yours — knocks back, and the terrain is
built out of ledges. Getting shoved off one is not a bug.

## Running

Godot 4.6 is required. This machine has it at `~/Applications/Godot.app`:

```sh
GODOT=~/Applications/Godot.app/Contents/MacOS/Godot

$GODOT --path . --headless --import    # first time only, or after adding assets
$GODOT --path .                        # play
```

The game opens on the splash and main menu (Play, Options, Achievements, Save Slots, Links,
Credits, Quit). **Play** opens the lobby: pick **Local game**, **Host online game** or **Join
online game**. Local and hosted games then pick a **world** (see Saved worlds below), and
everyone on this machine claims a seat and picks a hero. Hosts get a waiting room with a
**Start the hunt** button; joining takes an address, which can be typed or entered on the
on-screen number pad with a gamepad.

Command line shortcuts, mostly for testing:

```sh
$GODOT --path . -- --solo --slots=2 --seed=4242     # straight into a 2-player split screen
$GODOT --path . -- --solo --slots=2 --heroes=mage,archer   # ...as chosen heroes (default: knight, barbarian, thief, mage)
$GODOT --path . -- --solo --season=winter            # force a season (spring, summer, fall, winter)
$GODOT --path . -- --solo --time=0.75 --freeze-time  # time of day (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight)
$GODOT --path . -- --solo --give=lantern             # start with items
$GODOT --path . -- --solo --world=new               # play in a new saved world (--world=N loads world N)
$GODOT --path . -- --host --slots=1                 # host and start immediately
$GODOT --path . -- --join=192.168.1.20              # join a host
```

## Controls

Everything, menus included, works on a gamepad alone, on keyboard and mouse alone, or any mix.

**Seats are claimed in the lobby, not assigned, and each seat picks its own hero.** On the
"Choose your heroes" screen each person presses `A` on their gamepad or `Space` on the keyboard
to take the next player slot. Their card then shows a hero in 3D, idling, waving, cheering or
doing push-ups and sit-ups while they decide (`scripts/ui/hero_preview.gd`). Up and down (D-pad,
left stick, or `W` / `S` and the arrows) step through the five heroes; `A` / `Space` locks the
pick in and the hero cheers. `B` / `Esc` backs out one layer at a time: unlock the pick, then
give up the seat, then leave the screen. Two players may pick the same hero. Once everyone
seated is ready, `Start` / `Enter` (or the Start button) begins. So a solo player can use a pad,
two people can share a keyboard and a pad, and four pads is four players. `scripts/player/player_bindings.gd`
turns those claims into each player's input actions at runtime.

| | Keyboard and mouse | Gamepad |
|---|---|---|
| Move | `WASD` / arrows | left stick |
| Attack with your hero's weapon | left mouse or `J` | `X` |
| Charged attack | hold the attack, let go when the ring at your feet flashes | hold `X`, let go |
| Shield, held (Knight only) | `Q` (or `K`) | `Y` |
| Equipped usable (hookshot, lantern, power glove, bug net or fan) | `E` (or `L`) | `B` |
| Jump (needs the feather) | `Space` | `A` |
| Dash (needs the boots), held | hold `Shift` | hold `RT` |
| Gear panel | `I` | `Select` |
| Gear wheel (quick-pick a usable) | hold `R`, `Q` / `E` to choose, let go of `R` | hold `LT`, point the right stick, let it go |
| Target | click an enemy, or `Tab` / `Backspace` to cycle | `RB` / `LB` cycle |
| Interact (chests, the shop) | `F` | d-pad up |
| Turn camera | drag with **right mouse**, or `Z` / `C` | right stick (also tilts) |
| Map | `M` | -- |
| Mute / unmute microphone (online) | `V` | -- |
| Pause / options | `Esc` | `Start` |

The gear panel belongs to one player and opens in their own pane. It has two sections: usable
equipment (hookshot, lantern, power glove, bug net, fan), of which one is equipped on the third button, and static
equipment (boots, feather, mirror), which simply works. Stick left and right picks an item, any action
button equips a usable, and Select / `I` closes the panel. Only that player stops moving while
it is open. The three icons in the top right of each pane show the hero's weapon, the shield
(empty for anyone but the Knight) and the equipped usable, each with its button; they are drawn in code (`scripts/ui/item_icon.gd`).

The gear wheel is the quick way to swap usables without the panel. Hold `LT` and push the right
stick: a ring comes up with one fixed slice per usable (the hookshot is always at the top) and
the stick points at one. Let the stick spring back and, 100 ms after it is back in its dead
zone, the slice it was pointing at as it was let go is equipped and the ring closes. There is no
confirm button. Letting go of `LT` first equips too. Without `LT` the right stick turns the
camera as usual, and the left stick walks the whole time. On a keyboard, hold `R`, step round
the ring with `Q` / `E`, and let go of `R` to equip. A slice for something not found yet is
greyed; landing on it changes nothing
(`scripts/ui/gear_wheel.gd`).

In menus the gamepad drives the template's pointing hand: d-pad moves it between buttons, `A`
presses, `B` backs out, and the left stick moves a free cursor. During play that cursor is
switched off so the stick only moves the character. The pause menu does not stop the world
(it cannot, online) -- it stops the local players reading their controls.

Gameplay controls are not yet rebindable from Options > Keybindings; that screen covers the
menu actions. Select used to be the template's Report Bug button on a gamepad; it is the gear
panel now, and `F7` still opens the report form.

Dragging with the right mouse button captures the pointer and turns the camera freely — the right
button does nothing else. Horizontally it does exactly what Z and C do, and vertically it tilts within a bounded range of whatever framing is
active, so a drag never undoes the boss pull-back and never drops the view so low that the ledge
you are about to be knocked off stops being visible.

Clicking an enemy both targets it and swings, so click-targeting never costs you a turn; a
click that lands on nothing leaves the current target alone.
There is only one mouse, so gamepad players cycle targets with the bumpers instead — and any
attack with no target selected aims at whatever is roughly in front of you.

## How a match works

- **Health** is whole points, two to a heart. A hero has 6 (three hearts), every skeleton has 2,
  and every attack a hero makes -- weapon, thrown rock, boomerang -- does 1, as does every
  skeleton's. An odd number shows as a half heart cut down the middle: the bar empties from the
  right. The dragon has 120 and its attacks cost a heart or half a heart. Max hearts are
  upgradeable.
- **Armour** has three levels. Everyone starts at 0 (full damage); each armour upgrade raises it
  one level, for good: level 1 takes half damage, level 2 a quarter. Health stays whole points,
  so the armour keeps the remainder -- at level 1 every second point of damage lands, at level 2
  every fourth. Upgrades are in the large chests and the bug shop (8 bugs); a shield still blocks
  first. The level shows under the hearts and on the hero: a shader dyes their clothes blue at
  level 1 and red at level 2 (`scripts/characters/cloth_tint.gdshader`). The KayKit heroes are
  painted from flat palette swatches, so the shader dyes strongly coloured cloth outright, gives
  grey metal and white linen a lighter wash, and leaves the orange-brown of skin, hair, leather
  and wood alone. The weapons in hand are not dyed.
- **Heroes hurt each other.** A swing, an arrow, a bolt, a rock or a boomerang lands on another
  player exactly as it would on a skeleton: one point and a shove (a raised shield still blocks
  it). Auto-aim and target cycling still only pick enemies, so a swing aims at the skeleton
  rather than the friend beside it. The lantern's fire still leaves the party alone.
- **Heroes** differ only in their weapon, which they start with and keep through death
  (`autoloads/archetype_db.gd`, attacks in `autoloads/ability_db.gd`). Hearts, speed and
  everything else are the same:

  Every attack does one point; they differ in reach, speed and shove. Holding the attack button
  after a swing charges a stronger move: a ring in the hero's colour grows at their feet, flashes
  with a chime when it is full (0.85 s), and letting go unleashes it. A hero walks at half pace
  while charging, the charge glow is seen by everyone, and a hit that gets through knocks the
  charge out of you.

  | Hero | Weapon | Attack | Charged attack |
  |---|---|---|---|
  | Knight | sword and shield | A wide, quick slash. The only hero who can block. | Spin attack: everything within 4.2 m, all the way round. |
  | Barbarian | two-handed axe | A slow, narrower chop with a big shove. | Whirlwind: a wider spin (5 m) that throws harder. |
  | Thief | dagger | A short, narrow stab, fast enough to land three for the sword's two. | Knife flurry: ten knives flung out all round, 12 m. |
  | Mage | staff | A glowing bolt of magic, 22 m. | Arcane ring: a ring of magic bursting out to 6.5 m, throwing back all it catches. |
  | Archer | bow | An arrow, faster and longer (28 m) than the bolt, with a longer draw. | Arrow storm: twelve arrows loosed all round, 18 m. |

- **Gear** is everything else, and a player can do exactly what they are carrying lets them do
  (`scripts/items/item_db.gd`):

  | Item | How it is used | What it does |
  |---|---|---|
  | Shield | own button, held | Knight only. Blocks hits from the front: no damage, a third of the shove. Kept. |
  | Hookshot | usable | Fires a hook 14 m. It pulls you to anything that does not move (walls, trees, rocks, chests, the dragon) and pulls anything that does (monsters, other players) to you. |
  | Lantern | usable | Drops a patch of fire that burns monsters and flammable scenery -- trees, grass, fences, crates -- and leaves the party alone. Lights the ground round whoever carries it at night and underground. |
  | Power Glove | usable | Lifts the rock in front of you; press again (or attack) to throw it. A thrown rock shatters where it lands, and whatever it lands on -- monster or fellow player, but not the thrower -- takes a point and is thrown back. |
  | Boomerang | usable | Flies 13 m out and comes back to hand, turning early at a wall or tree. Everything it passes through (monsters, the dragon, other players -- never the thrower) takes one point and a small shove and is stunned for 1.2 s; a stunned player cannot move or act. It cuts long grass and scatters leaves on the way. One in the air at a time. In the chests and the shop (4 bugs). |
  | Bug Net | usable | Swing it at the bugs flying about to catch them. |
  | Fan | usable | A gust that shoves back everyone in front of you, friend or foe, without hurting them. |
  | Feather | static | Lets you jump. Without it the jump button does nothing. |
  | Raft | static | Walk onto the river and you ride it on a raft; the current carries you downstream (over the waterfalls, too). In the chests and the shop (5 bugs). |
  | Bombs | usable | Standing still, sets a bomb down at your feet; on the move, throws it like a rock. It sits where it lands and goes off after 2.2 s in an orange ball of fire reaching 3.2 m: two points and a hard shove to everyone inside, whoever lit it included. One out at a time; never runs out. Blows open the cracked wall in the plains. In the Old Well's big chest and the shop (6 bugs). |
  | Flippers | static | Swim in the lake and the sea instead of sinking: you float at the surface, swim at 70% speed, and swim straight out onto the shallows. Jump dives -- down for a moment, then back up -- which is how the lake's portal is reached. The river's current is still too strong. In Root Hollow's big chest. |
  | Boots | static | Hold dash to wind up into a sprint nearly twice walking pace; steer it with the stick (it turns wide) and let go to stop. |
  | Mirror | static | Online, your voice reaches anyone else holding a mirror at full volume, however far apart you are. Shop only. |

  The usables share one button, so which to keep ready is a choice made in the gear panel.
  A monster the hookshot bites is stunned for 0.3 s: it cannot move or swing, and a swing it
  was winding up is lost.
- **Money is gems** (`Gem`): green worth 1, red 2, blue 5, purple 10 and a clear, glinting diamond
  25, each its own shape. A monster's or a chest's purse is paid in the largest that fit.
- **Crates** stand about in rows of one to three in every chunk but the mountain. Anyone can pick
  one up with the interact button -- no glove needed -- and throw it; thrown, or hit with a blade,
  an arrow, a bolt or a bomb, it breaks open: sometimes nothing, sometimes a heart, most often a
  gem or a few (`LootArea.spawn_crate_loot`). They are not saved: a new session has them all back.
  `--goto=crate` stands you beside one, `--goto=gems` lays out one of every gem in front of it.
- **Bugs and the shop.** Bugs fly about every chunk but the mountain (most in fields and
  forest) and come back a while after being caught. They are each player's own, and are kept
  through death. The stall in the middle of town (`F` / d-pad up beside it) trades them for
  gear: the bug net is free, a heart container or a mirror is 3 bugs, and the rest cost 4 to 6
  (`ItemDB.SHOP_STOCK`). Left / right chooses, jump or any attack button buys, interact leaves.
- **Heart containers** add one heart for good (up to eight) and fill the bar. They are in the
  shop and in some large chests.
- **Voice chat** (`scripts/audio/voice_chat.gd`) runs in online matches. Each machine's
  microphone speaks for its first player, from where that player stands: full volume within
  8 m of the nearest player on the listening machine, fading to nothing at 40 m, and not
  transmitted at all to machines out of earshot. Two players who each hold a **mirror** hear
  each other at full volume anywhere. `V` mutes the microphone; a note appears over whoever is
  talking. The first run asks the OS for microphone permission.
- **Sound effects** fall off with distance: full volume within 6 m of the nearest player on
  this machine, fading to silence at 38 m. They are placeholders synthesised at start-up (`scripts/audio/game_sfx.gd`):
  each is a short recipe of swept tones and filtered noise. To replace one, register a real
  recording under the same id with `SoundManager.register_sfx` after `GameSfx.register()`.
- **Finding gear.** The first chest in every chunk is the large one and holds one item. The
  town's always holds a feather; the rest take turns through all eight finds, so a map has one
  or two of each. A player who
  already has an item walks past a second one and leaves it for a friend.
- **Dying** is a setback, not an elimination: you come back after a few seconds on half
  health. But everything except your weapon (and the Knight's shield) is left on the ground where you fell,
  for whoever gets to it first -- and you cannot take it back yourself for a few seconds.
- **Gold** is a party pool. Loot drops at a monster's last footing rather than wherever its
  corpse landed, so shoving something off a cliff never costs you the reward for the kill.
- **Falling off the world** costs a heart and puts you back on the last solid ground you stood
  on.
- **Reach** is measured surface to surface. Every combatant carries a `hit_radius` and
  `hit_height`, and attacks aim at mid-body, because a body's origin sits at its feet — without
  that, a 5.6 m dragon is a point on the floor inside its own collision capsule that nothing
  can reach, and flat projectiles sail over everything.

## The map

**The river.** Every map has one, planned from the seed with the rest of the world
(`WorldGenerator._plan_river`, carved per chunk by `scripts/world/river_carver.gd`). It rises in
a pond high on the mountain's terraces and runs downhill, chunk to chunk -- never uphill, never
through the lake -- winding as it goes, until it reaches the sea on a beach. Part way down it
splits (`WorldGenerator._plan_branch`): a second arm leaves it in one chunk and runs downhill,
through any chunks between, into the lake, tumbling into it over a little fall where it meets
the water. Its bed is one level
below its banks and never rises downstream, so wherever the ground steps down -- each mountain
terrace, each cliff between tiers -- the river goes over a waterfall, with foam where it lands.
Near its source -- on the mountain and through the highlands -- it runs a metre deeper still
(`WorldGenerator.RIVER_SINK`), its water down between steeper banks, until its first fall below
them. A raft there passes under the plank bridges, and anyone riding one can hop off with jump. The bed's level stays the same, so bridges and
everything that walks by tiles are unchanged; only the bed, the water and a raft's footing are
drawn lower (`TerrainData.sinks`).

The water is deep. Without a raft, anyone who falls or is knocked in is swept back to where they
were last walking on safe footing, for half a heart; a skeleton that blunders in drowns. Safe
footing is remembered every tenth of a second, on the move as well as standing still, wherever
no pit, river or deep water lies on the tile underfoot or the eight round it -- so a respawn
lands a couple of metres back from the edge they went over, not on its lip and not back where
they started walking. Every chunk the river
crosses has a plank bridge on the straight stretch where it comes in (on the mountain, where it
leaves across the rim; where the arm splits off, one on the arm too) -- one per chunk, because the river cuts every chunk it runs through in
two, and that is what keeps every part of the map walkable before anyone finds a raft (checked
by the walk test across 18 seeds). Where it runs straight between level banks, a stretch may
also have a **land bridge**: a broad arch of rock left standing over it, its deck 3 m over the
banks so someone rafting can ride underneath. It rises from flat banks in an S-curve of its own,
three tiles long, level where it leaves the bank and where it meets the deck, so neither end has
an edge; turf on top, a stone kerb along the deck's sides with the ledges' invisible wall over it
(`RiverCarver._place_land_bridge`, `RiverBuilder.build_land_bridge`); about a third of the
river's chunks have one. The river crosses chunk borders near their corners, clear of
the ramps, and never beside a corner that faces the edge of the map, where it would cut off a
sliver of land -- nor right beside a corner the mountain spills round, where it would pen ground
in against the terraces; there it crosses further along. Water, waterfalls and bridges are built by `river_builder.gd`, with
`water.gdshader` (the surface, flowing downstream) and `waterfall.gdshader`. A raft's footing is
an invisible slab on the river at bank height, on a collision layer only a raft-carrier collides
with. `--goto=bridge|waterfall|bigfall|pond|river|sea|lake` stands you beside each, and
`--goto=landbridge[:N]` a little way back from the Nth land bridge;
`--capture-raft` puts you on the water with a raft. `--capture-overview --capture-annotate`
photographs the whole map straight down with the chunk borders ruled over it and every
dungeon's way in marked and named. `--goto=entrance:<id>` stands you in
front of a dungeon's way in and `--goto=dungeon:<id>` inside it; `--reveal-entrances` opens the
hidden ones as the match starts.

All the water -- river, sea and lake -- is one shader (`water.gdshader`, after binbun's CC0 "Water
with Caustics" on godotshaders.com): the bed shows through it, bent by the waves and lit by
caustics, it darkens with depth, and foam gathers on the waves and wherever it meets the shore.
Its four textures are tiling noise (`art/water/*.tres`). Added for this game: the river's waves
ride the current (a two-phase flow map from the flow in the surface's vertex colours) and boil
white under a waterfall, and still water too deep to stand in is shaded darker with a pale line
along the drop. It reads the screen and depth textures, so it costs a screen copy per pane.

**Comic shading.** Everything in the world is lit in three flat tones with a rim light
(`scripts/visual/comic.gdshaderinc`, after the CC0 "Comic Cell" shader on godotshaders.com), put on
materials by `ComicLook`. `--no-comic` turns it off.

**Day and night.** A day is 24 minutes (`DayNight`): the sun circles the world, 12 minutes above the
horizon and 12 below, with the moon opposite. Night is dim and blue, never black. The host keeps the
time, which is saved with the world. Dungeons are on a render layer of their own with their own light.

**Paths and torches.** `PathNetwork` wears paths over the whole map joining every slope between
chunks, the town and the mountain's road, drawn by the ground shader. Slopes between chunks are seven
tiles wide with the path up the middle; on the mountain's one-tile ramps it is a narrow trail. Torches stand along them and
burn from dusk to dawn; a pool of a dozen real lights follows the ones nearest the players.

**Seasons.** Every match is played in one of four seasons, rolled from the world seed (so every
machine online gets the same one without sending it). The overhead map's title names it.

| Season | Grassland (town, plains, fields, forest, lake) |
|---|---|
| Spring | Bright green, with drifts of flowers. |
| Summer | Duller green, with patches of knee-high grass. Gusts of wind roll across it, it parts and splays round anyone walking through it, and it is cut down to stubble by melee swings, fire and shattering rocks. |
| Fall | Orange ground, autumn trees, heaped leaf piles and loose leaves everywhere. Leaves flutter as anything passes and are kicked up by anyone walking through them -- they tumble and settle somewhere new, so a pile run through stays scattered. Swings and fan gusts throw them about, fire burns them (`leaf_field.gd`, `leaves.gdshader`). |
| Winter | Snow and snow-covered trees. Everything walking through it leaves a track, which fills back in over about a minute. |

The beach stays sand and the mountain stays rock all year; the desert and the temple ruins keep
their own ground until winter, when they are snowed on too. Colours and tree swaps are in
`scripts/world/season.gd`; the grass is `grass_field.gd` with `grass.gdshader` (after Toadile's MIT
"Grass with Screen-Space Displacement": crossed-quad tufts with the blades cut out in the shader,
noise-texture gusts, and shrinking away with distance; it bends from body positions handed in
each frame rather than the original's depth-buffer trick, which Godot 4 only allows on
see-through materials); the tracks are
`snow_trails.gd`, painted into a whole-map texture that `terrain.gdshader` reads. Nothing about
the grass or the snow is sent between machines: each grows the same grass from the seed and
sees the same swings and footsteps, so each cuts and tracks its own copy.

A hero left standing for 8 seconds without moving or pressing anything drops into push-ups or
sit-ups, swapping between them every so often (synced, so everyone sees it).

Sixteen 128 m chunks in a 4×4 grid, 512 m across, stepping down from the mountain:

| Tier | Which chunks | Ground height | Biomes |
|---|---|---|---|
| Summit | the mountain, always on an edge of the map | platform at 75 m | mountain |
| Highlands | the chunks touching the mountain | 21 m | temple, forest, plains, fields -- always a temple |
| Ground | everything beyond those | 9 m | town, plains, fields, forest, desert, lake, temple -- always a lake, a desert and a temple |
| Sea | two to four of the furthest chunks, in one connected stretch of coast | sand at 1.5 m, water line at 0.45 m | beach |

**Everything essential can be walked to.** A player without the feather cannot jump, so a
single 1.5 m step is a wall to them, and the generator is built around that:

- Wherever a chunk meets lower ground it cuts a **ramp** down to it: four tiles wide, one
  level per tile (about 37 degrees).
- The **mountain** is eight terraces, one for each dungeon, each 6 m -- too tall to hop -- and at
  least two tiles deep: an outer row to walk round on and an inner row the ramps run along. It is
  not boxed in by its chunk: away from the road its lower terraces spill 3-12 tiles over the
  border into the chunks beside it, in curves, with rounded corners and edges that wander
  (`WorldGenerator.mountain_level`). The shape is worked out in the mountain chunk's coordinates
  from the world seed, so every chunk it reaches builds the same terraces on its side of the
  border without knowing about the other; each chunk records the level across its borders lane
  by lane (`TerrainData.edge_levels`) to draw its walls against, and a mountain chunk drawn on
  its own closes its edge with cliff "skirts" that the next chunk's ground hides. The face the
  road climbs stays exactly the old square terraces across its middle. Ramps run along the terraces,
  not into them, each ending on a landing level with the terrace above. A road zigzags up the
  face towards the middle of the map, one ramp per terrace, and three more ramps per terrace are
  scattered round the rest (the tests check the summit can be walked to with the road left out
  altogether, and the playtest walks up it with the stick). The summit platform (44 m
  across) stands 54 m above the rim. Being thrown off it lands you on a terrace you walk down
  from. `--capture-overview=mountain` photographs it from above.
- Each terrace carries its dungeon's **shrine** (`MountainShrine`), the Old Well's at the bottom
  up to the Drowned Shrine's under the summit, in the dungeon table's order. They stand in a
  column against the terrace walls just beside the road. A shrine is a stone obelisk with the
  dungeon's name and a crystal in its colour, dark until that dungeon's guardian is beaten; then
  the crystal lights and a faint beam rises from it. It reads the big chest's padlock, which
  every player is sent and a saved world keeps, so it holds no state of its own.
  `--goto=shrine[:N]` stands you in front of the Nth.
- **Chunk edges are not straight.** Where a chunk meets a lower one, its ground spills over the
  border into the lower chunk in lobes 2-10 tiles deep (`WorldGenerator.tier_spill`), so the cliff
  between them runs in curves as the mountain's terraces do; the lower chunk carves the ramp up
  through them. Both chunks work the lobes out from noise taken over the whole map, so they agree
  along the border without knowing about each other.
- **Ground colours blend across borders** (`GroundPaint`). Ground that came from another chunk --
  the mountain's spill, a higher chunk's lobes -- is coloured as that chunk, so the colours change
  at the cliff it ends in. Between chunks at the same height they blend across a border that
  wanders. Tiles are no longer shaded one by one, which showed the grid up across every field.
- **Bluffs** (`WorldGenerator._raise_bluffs`): in plains, fields, forest, temple and desert
  chunks, two or three tall plateaus in a row, 4.5 m up, with a ramp up the first and a plank
  bridge across the gap to each of the next, open ground beneath. The far ones are reached only
  along the top; the reach flood crosses the bridges as spans. In a chunk with a dungeon's
  entrance they leave room for it. `--goto=bluff[:N]` stands you at the near end of the Nth
  bridge.
- **Mesas** -- raised ground one or two steps up -- are optional. Any ground-level pocket that
  mesas would wall off is filled in, so they are places a jump or a hookshot earns, never
  barriers. Small chests may sit on them; the large gear chest never does.
- The **beach** slopes under the water rather than stepping, so the shallows are waded into
  and out of -- and then the sea bed drops away in two steps into deep water, always at least
  two tiles of shallows out from the sand. The **lake** fills two chunks side by side, always
  with at least one dry chunk between it and the sea (`WorldGenerator._place_lake` moves it, and
  any one-of-a-kind biome in its way, there). Its shore wanders in a rounded rectangle across
  both, which work it out the same, so the water runs straight on over their border. Its water
  lies a level below the shore, with ankle-deep shallows that slope up to it, then deep water;
  three to five islands stand out in each half, each joined by a plank bridge to the shore or to
  an island that is (`WorldGenerator._raise_islands`). Deep water (`TerrainData.deep`) works
  like the river: going in is a splash, half a heart, and being put back where you were
  walking; skeletons drown in it; a raft does not float on it. Its bed darkens with each step
  and the water over it is shaded darker, with a pale line along the drop
  (`water.gdshader`'s depth map), so the edge can be seen before anyone walks off it.
- **Pits** are rare and deliberate: two in a temple, one in a desert, none anywhere else.
- Scenery is roughly a third as dense as it was, and none of it stands on a chunk's rim, a
  ramp or a slope.

`scripts/tests.gd` checks the promise directly: with no jump at all, a flood fill from the
town reaches the dragon's platform, the sea and every chunk, across several seeds.

The grid is walled in by invisible walls 120 m tall (`world_boundary.gd`), so nobody walks or is
knocked off the map; there is no scenery beyond the edge. Only the chunks near the players on
this machine are drawn -- the one each stands in and the eight round it -- plus the mountain,
which is always drawn so it stands on the horizon from anywhere (`GameWorld._update_drawn_chunks`).
Hidden chunks keep running; their skeletons stay drawn, since they can follow a player out.
Pits are sealed at the bottom by black
caps, built as a separate mesh from the terrain so they are scenery rather than collision.

Terrain is a per-chunk grid of 1.5 m levels (`scripts/world/terrain_data.gd`), where each tile
is flat, a ramp, or a shore tile whose corners rise to meet the ground above it. It is
generated as vertex-coloured geometry rather than built from the Kenney block meshes, because
those only exist in grass and snow and all share one colour atlas.

Cliffs are smoothed (`TerrainData.lattice` and `cell_shape`, `ChunkMesher.build`). For each level,
"is this tile at least that high" is blurred over the 3×3 tiles round each point (a quadratic
B-spline), and the cliff up to that level runs where the blur crosses one half, traced on a
0.5 m lattice:
- **Straight cliffs**, one-tile ridges and one-tile gaps stay exactly on their tile edges.
- **Corners** round off, outer and inner alike, with a radius of about 1.6 m.
- **Diagonal steps** become one sloping cliff, and one-tile notches and bumps gentle waves.

Ramps, shores, pits, the river and reserved tiles keep square edges, so the way onto a ramp
stays the width the generator made it. Only the drawn ground and its collider change: who can walk
where is still decided tile by tile, and `TerrainData.surface_at` gives the exact height for
anything placed on the ground.

`terrain.gdshader` textures everything procedurally, with no image files, tinted by each biome's
own colours:
- **Ground:** mottled.
- **Cliff walls:** rock strata.
- **Edges:** the ground hangs a ragged lip over each cliff top, the plateau's rim wears to dirt,
  rubble gathers at the foot, and ramps wear a path.

Its uniforms tune how strongly each effect shows.

Some cliff tops are **ledges** (`WorldGenerator._mark_ledges`): a kerb of stone along the edge,
its pieces joined into runs and smoothed into curves (`ChunkMesher.ledge_paths`),
with an invisible wall over it on its own collision layer (`Combatant.LAYER_LEDGE`). Players and
monsters can't walk, jump or be knocked off a ledge. Thrown rocks, bombs, arrows and the camera
pass straight over it.

How ledges are placed:
- They come in long runs picked out by noise.
- Roughly one tile in eight is left open as a gap to drop through.
- A ledge only stands where the foot of the cliff can already be walked to.
- High ground that can only be reached by jumping always keeps at least one open stretch to jump
  up at.
- They never go on beaches, the dragon's arena, pits, the river, deep water, ramps or ramp
  landings.

`--goto=ledge[:N[:below]]` stands you beside one.

**Nothing about the map is ever sent over the network.** The host broadcasts one integer seed
and every machine generates identical terrain, identical monsters with identical node names,
and identical chests. That is also why there is no `MultiplayerSpawner`: matching node paths
on every peer mean combat RPCs address the same object everywhere. Things that appear later --
coins, hearts, dropped gear -- are spawned by the host with a serial number for a name, so
they match too.

## Dungeons

Eight dungeons, each its own hand-built scene in `scenes/dungeons/` -- not generated -- with a
way in somewhere on the map. Every map has all eight: the layout always includes the biomes
they are in (forest, plains and fields in one tier or the other, a lake, a desert, and a temple
both on the ground and in the highlands).

| Dungeon | Way in | How it opens | Big chest |
|---|---|---|---|
| The Old Well | the well beside the shop in town | always open | Bombs |
| Root Hollow | a great tree in the fields | hit it -- a sword, an arrow, a bolt, a thrown rock or a bomb -- and a door opens in its trunk | Flippers |
| The Sunken Sandvault | a big rock in the desert, on a slab of sand | lift it with the power glove: a stairwell goes down to a door | Armour |
| Rubble Cave | a cracked wall set in a boulder in the plains | blow it open with a bomb | Heart container |
| Grove Burrow | a ring of tall trees in a forest, round a cave mouth | always open, through the one gap | Heart container |
| The Stone Crypt | a crypt in the ground-tier temple | always open | Armour |
| The Tower of Echoes | a shrine between two obelisks in the highlands temple | always open | Heart container |
| The Drowned Shrine | a glowing portal on the lake bed | swim out with flippers and dive to it | Heart container |

The well gives bombs and the tree gives flippers, and neither needs anything to get in, so
every dungeon can be reached: bombs open the plains, flippers the lake, and the glove (from the
chests or the shop) the desert. Going in or out is the interact button at the door ("Enter",
"Leave"); you come out a few steps in front of the way in. Each player goes through on their
own -- nobody is dragged along.

Inside: rooms and corridors with skeletons and small chests, and at the end a **Skeleton
Champion** (16 hits, a whole heart a blow, hard to shove) guarding the big chest, which stays
padlocked until it falls. Down there each player's camera trades the sky for darkness and fog
(`Dungeon.make_environment`); falls and revives stay inside, and gear dropped on death is left on
the dungeon's floor.

**Editing them.** Open `scenes/dungeons/<id>.tscn`. Floors and walls are `CSGBox3D` nodes under
`Geometry` (collision on), dressing is under `Decor`, and the markers are under `Spots`:
`MonsterSpot` (pick a `monster_id`; tick `boss` for the guardian -- one per dungeon), `ChestSpot`
(`large`, `gold`; tick `big` for the locked reward chest -- one per dungeon), plus `Entry` (where
you arrive) and `Exit` (a `DoorSpot`: the way out, facing into the room). The root's
`reward_item` is what the big chest holds. Markers show as capsules and boxes in the editor and
are swapped for real monsters and chests when the match starts, named in scene order -- so a
saved world remembers which chests are open. The scenes were first laid out by a one-off script;
from here they are edited by hand.

**Where they are.** All eight are built on every machine, off the east edge of the map (from
x = 1400 m, 320 m apart), further apart than anything is drawn or simulated.

**Saved.** Entrances found (`revealed_entrances`) and big chests unlocked (`unlocked_chests`)
go in the world save; guardians come back on every load, like the dragon, but an opened chest
stays open. Someone joining mid-match is caught up on both.

## Multiplayer

The world is host-authoritative — monsters, chests, loot and all damage are decided by the
host — while player movement is owned by whichever machine is driving it. That trade buys
responsive movement at the cost of cheat resistance, which is the right way round for a game
you play with friends. The host can still shove a player, because knockback arrives as an
explicit impulse the owner always applies, never as a position correction. Hits, heals and
hookshot pulls are sent by the host to every machine, including the one that owns the player
being hit; gear changes hands the same way.

A player who joins a match already in progress asks the host to catch them up once their world
is built (`GameWorld._request_catch_up`): which chests are open, the party's gold, and every
hero's gear. What is lying on the ground is not sent yet.

A player is `(peer, local slot)`, so one machine can contribute up to four split-screen
players to an online game. Panes are SubViewports sharing one `World3D`: one simulation, four
camera renders. Transport lives behind `scripts/net/transport.gd` so a Steam peer can replace
ENet without touching game code.

**Dropping in.** Mid-match, pressing Start on a controller nobody is playing on (or Enter, if
nobody is on the keyboard) seats another player on this machine, up to four: they get the first
hero nobody here is playing, appear beside player 1, and the screen splits again around them.
A hint at the bottom of the screen says so while a spare controller is plugged in. It works
offline, hosting and joining alike (`Main.drop_in`, `NetworkManager.add_local_player`).
`--capture-dropin` photographs it.

## The dragon fight

The dragon holds a flat 28 m platform carved into the mountain summit, with a two-step lip all
the way round and terraces falling away beyond it. It barely moves. Each of its four attacks
owns a different band of ground, so there is no safe distance — only a distance that is safe
right now:

| Attack | Band | What it does |
|---|---|---|
| Claw swipe | 0–10 m, front | Hardest single hit; rears up and rakes down |
| Wing flap | 0–11 m, all round | Answer to crowding it; shoves everyone out and up |
| Tail sweep | 0–14 m, **behind** | The big one. 34 m/s — enough to clear the platform |
| Fire breath | 7–26 m, narrow cone | Long tell, then leaves burning ground behind |

Getting behind it is a real tactic with a real downside, and the breath cannot be used point
blank. Every attack telegraphs for at least 0.4 s before it lands, and the damage fires on the
frame its animation crosses the `hit_at` time in `Dragon.ATTACKS` — so a tell always means what
it looks like. Below half health it enrages: everything speeds up and the breath lays more fire.

Knocked off the platform, you climb back. If *everyone* is off it for six seconds the fight
resets — the dragon heals to full and goes dormant, and you start again. Killing it wins the run.

The camera pulls back and flattens while you are on the platform, because a 5.6 m boss does not
fit a 14 m follow camera and a telegraph you cannot see is not a telegraph.

## The dragon model

The dragon is MattBas's model (`art/models/dragon_mattbas.glb`, from dragon.best/3d), licensed
CC BY-SA 4.0 -- the licence is beside it in `art/models/dragon_mattbas_LICENSE.txt` and the credit
is in the Credits screen. It is drawn 1.8x its authored size: about 5 m tall with 22 m of wing.

Its scales follow the season: pink in spring, green in summer, red in fall, and its own blue in
winter. The model is painted from a 16x16 palette, so `Dragon.season_image` turns just the blue
scale swatches to the season's hue and leaves the belly, mouth, eyes and horns alone.

It brings its own idle, walk, run and flying loops, which its AnimationPlayer plays. The attacks
are not in it, so they are posed on top: `DragonPoser` is a `SkeletonModifier3D` that runs after
the animation each frame and turns named bones by the rotations `DragonAnimator` samples from its
keyframe tables. Those tables are written in the skeleton's own space (head +Z, up +Y, left wing
+X) as "neck up", "wings down", "tail round to the left", whatever each bone's local axes are, and
an attack's damage lands on the frame its pose says it does (`Dragon.ATTACKS[...]["hit_at"]`).

`art/models/dragon.glb`, `dragon.3ds` and `tools/convert_dragon.py` are the old model and its
converter; nothing loads them any more.

### Flights

Between fights the dragon leaves its perch. About 35 s into a match, and every minute or so after
that while nobody is on the summit, it takes off and flies a loop round the map, about 15 m above
the ground and the treetops, and comes back. Every few seconds on the way it curls its neck down
and pours fire onto the ground ahead -- patches that hurt players and burn whatever they land
on -- with a roar heard from up to ~110 m away (sound effects normally fade out by 38 m). With
the camera looking down, what you mostly see of it is its shadow sweeping over you and the fire
coming down. It cannot be hurt in the air. Anyone climbing onto the summit while it is out calls
it straight home, and the fight begins when it lands.

Flights are not sent over the network as positions: the host says "take off with this seed"
(or "come home from here"), and every machine builds the same route (`DragonFlight`) -- waypoints
round the map, smoothed, with a height profile worked out by looking down at the ground every
2 m so it climbs before cliffs rather than through them. Fire is sent as the points it lands on.

Dragon fire -- from the air or in the fight -- and every other fire in the game burns long
grass, flowers and leaves where it lands, and melts the snow to wet ground, which comes back
over about three minutes.

## Picture

- **Resolution.** The game is laid out on a 1920x1080 canvas (`display/window/size/viewport_*`,
  stretch mode `canvas_items`, aspect `expand`). Each split-screen pane is a SubViewport sized in
  that canvas, so the 3D is drawn at 1920x1080 for one player (1920x540 each for two, 960x540
  each for four) and then scaled to the real window. A smaller window is supersampled; a 4K
  screen is upscaled from 1080p. A window that isn't 16:9 widens or heightens the canvas
  instead of letterboxing it.
- **Anti-aliasing.** 4x MSAA per pane (2x on the low graphics tier), set in
  `scripts/ui/split_screen.gd`. The Compatibility renderer has no FXAA or TAA.
- **Colour grade.** The world environment boosts saturation (1.3) and contrast (1.06) after
  tonemapping: `SATURATION` and `CONTRAST` in `scripts/world/game_world.gd`.

## Performance

The map is large and a four-way split renders all of it four times, so distance culling is not
optional. `scripts/world/culling.gd` holds the rules; `--perf` measures whether they work:

```sh
$GODOT --path . -- --solo --slots=4 --seed=4242 --perf
```

Measured on an M1 Pro, before and after (four panes, 143 monsters):

| | Before | After |
|---|---|---|
| Town, 1 pane | 20 fps | **120 fps** |
| Town, 4 panes | 17 fps | **75 fps** |
| Dragon fight, 4 panes | 28 fps, 121 ms spikes | **37 fps, no spikes** |

Three things mattered, and only the first was a guess worth making:

- **Distant monsters stop animating.** A skinned rig with 54 bone tracks costs the same whether
  it is on screen or 200 m behind the camera. Measuring first showed 48 ms of a 50 ms frame in
  process and 1.5 ms in physics, so this was the whole problem, not draw calls.
- **Skinned characters are culled and shadow-culled much closer than scenery.** Each one costs a
  bone upload and a second pass into the shadow map, per pane.
- **Effect shaders are pre-warmed at load.** The 121 ms spike was the first fire patch compiling
  its shader, landing on exactly the frame the dragon first breathes.

Per-frame allocation matters more than it looks: rebuilding a dictionary of twenty quaternions
to pose the dragon, or walking the player list from every coin on the ground, are the kind of
thing that shows up as a hitch rather than as a lower average.

## Testing

```sh
$GODOT --path . --headless res://scenes/tests.tscn   # 711 logic checks
$GODOT --path . --headless -- --playtest --slots=2   # drives a real match end to end
$GODOT --path . --headless -- --padcheck             # splash -> menu -> lobby -> match -> gear panel -> pause -> menu, on a simulated gamepad
$GODOT --path . -- --solo --capture=/tmp/map.png --capture-overview   # photograph the whole map from above
$GODOT --path . -- --solo --capture=/tmp/gear.png --capture-gear      # photograph the gear panel
$GODOT --path . -- --solo --goto=dragon --capture=/tmp/d.png --capture-dragon=claw@0.45   # hold a dragon pose
$GODOT --path . -- --solo --capture=/tmp/fly.png --capture-dragon=fly@24 --capture-delay=60 # mid-flight, breathing fire
$GODOT --path . -- --solo --slots=4 --capture=/tmp/armor.png --capture-armor=2         # heroes lined up at an armour level
$GODOT --path . -- --solo --slots=4 --capture=/tmp/charge.png --capture-charge=release # every charged attack at once
$GODOT --path . -- --solo --goto=ramp                # start at the foot of the mountain's ascent (also: dragon, or a biome id)
$GODOT --path . --headless res://tests/template_check.tscn   # template: saves, menus, achievements
$GODOT --path . --headless res://tests/steam_check.tscn      # template: achievements with Steam absent
```

`scripts/tests.gd` covers the things that fail silently: that all 139 animation clips actually
import as an `AnimationLibrary`, that every model and weapon path on every archetype exists,
that the 4×4 layout always produces the exact biome counts, that the same seed produces the
same terrain, the damage, knockback and heart-point maths, that faction and group membership cannot drift
apart (a body is added to the tree before it is configured, so a stale group silently made
every player a "monster" and left monster attacks with nobody to hit), that two characters
cannot carry each other's velocity, and the reach geometry — a swing
must reach a dragon from outside its own collision capsule, and a projectile test must happen
at chest height rather than at a target's feet.

`scripts/playtest.gd` covers the things a unit test cannot see: it builds the real world,
presses the real input actions, and checks the player lands on ground rather than through it,
that a swing damages and visibly displaces a skeleton, that killing it pays gold, that a chest
opens, and that falling off the world costs a heart and respawns you. It also plays the gear
for real: no jump until the feather is taken from the town's chest, a dash with the boots, the
hookshot pulling the player to a chest and a skeleton to the player, the lantern burning a
prop away, a death dropping everything but sword and shield -- and it **walks** the mountain's
ramp from the rim to the dragon's platform without jumping.

Worth running across several seeds — generated terrain is exactly where the awkward cases live:

```sh
for s in 4242 808 1337 91021 31337; do
  $GODOT --path . --headless -- --playtest --slots=2 --seed=$s | tail -1
done
```

The playtest runs windowed too (drop `--headless`), which is the only way to check the parts
that need a real window — pointer capture during a camera drag has nothing to capture otherwise.

For netcode, run two instances. `--netcheck=N` makes each side print a fingerprint of the
world it derived after N seconds, which is the real question when the map is generated from a
seed rather than transmitted — "did both machines end up with the same thing":

```sh
$GODOT --path . --headless -- --host --slots=1 --seed=4242 --netcheck=32 &
$GODOT --path . --headless -- --join=127.0.0.1 --slots=2 --netcheck=14

# HOST   seed=4242 peers=3 players=3 monsters=51 chests=11 dragon=yes terrain=2559739984
# CLIENT seed=4242 peers=3 players=3 monsters=51 chests=11 dragon=yes terrain=2559739984
```

Give the host the longer delay so it outlives the client doing the measuring. For playing by
hand, drop `--headless` and `--netcheck`.

Joining a match already in progress works: the host hands a newcomer the seed, the newcomer
builds the same world, and the roster broadcast that follows drops everyone's bodies into it.

## Layout

```
main.tscn      the main scene: splash, then the main menu (scripts/boot.gd skips both for CLI flags)
scenes/main.tscn   the game scene the menu's Play button loads (ProjectConfig.GAME_SCENE)
autoloads/     GameState, NetworkManager, PlayerRegistry, RigAnimations, and the data DBs,
               plus the template's SaveManager, SceneManager, SoundManager, PadCursor, ...
data/          AbilityData / ArchetypeData / MonsterData / BiomeData resource classes,
               plus the template's ProjectConfig, FeatureFlags, SaveData, achievements
scenes/        template screens: splash/, menu/ (main menu, options, credits), ui/ (widgets);
               dungeons/ holds the eight dungeon scenes
scripts/
  characters/  runtime KayKit model + animation assembly
  combat/      Combatant, CombatResolver, AbilityRunner, Projectile
  player/      controller, input, targeting, camera
  items/       ItemDB (the gear) and the hookshot
  enemies/     monster AI, dragon
  world/       generator, chunk mesher, chunks, biomes, chests, pickups
  dungeons/    Dungeon (a dungeon scene's root), the ways in, and the editor markers
  ui/          split screen, HUD, hearts, lobby, outcome screen
tools/         convert_dragon.py, plus template tooling (new_game.sh, asset audit, feedback worker)
addons/        GodotSteam (binaries in Git LFS)
build.sh, cron/, steam/, .github/   template build, nightly, Steam upload and release workflow
art/           the supplied KayKit and Kenney kits (fbx/obj folders are .gdignore'd)
```

## Template

The menus, options, saves, audio buses, scene transitions, gamepad cursor, achievements, Steam
wrapper and build scripts come from the go-to game template. What is still a placeholder:

- `data/project_config.gd`: `STEAM_APP_ID` is Valve's test app (480), and
  `FEEDBACK_GAME_KEY` is `CHANGE-ME`, which keeps the F7 bug reporter switched off.
- `steam/steam_ids.env` is blank; `export_presets.cfg` uses the bundle id
  `com.vgmrx.dragonslayers`.
- No music or title logo is set on `scenes/menu/main_menu.tscn`.

Per-game additions go where the template expects them: save fields in `data/save_data.gd`,
achievements in `data/achievements/achievements.tres`, release notes in `data/patch_notes.gd`
(bump `config/version` in `project.godot`), credits in `scenes/menu/credits_screen.gd`.

## Saved worlds

A local or hosted game is played in a **world**, picked in the lobby before the heroes: a saved
one, or **New world** (a fresh seed). The world page lists saved worlds newest first, with
their heroes, dragon kills and time played, and each has a Delete that asks twice. Joining
someone plays in the host's world, so it skips the page.

A world file (`data/world_save.gd`, `user://worlds/world_<id>.tres`) keeps the seed and the
**progress** made in it: opened chests (they stay open and empty), the party's gold, gear left
lying on the ground, how many times the dragon has died, and each hero's kit -- gear, hotkeys,
heart containers, armour and bugs. The heroes live in the world, one per hero: the seat cards
show what the world remembers of each ("Saved: 4 hearts · boots, hookshot"), and in a world no
two seats can pick the same hero. Everything else comes back fresh from the seed on every load:
skeletons, scenery, loose coins, and the dragon, which returns however often it has been slain.
Everyone starts each session in town. After a kill, the victory screen offers **Keep exploring**
instead of a new hunt.

The host owns the save and writes it (`GameWorld.save_progress`, via `WorldPersistence`) every
two minutes, when a chest opens, when the dragon dies, on quitting to the menu, and when the
game is closed. Clients never save; a joiner's hero is restored from the host's world.

## Next

- **M2** the remaining biome content: temple interiors, per-biome monster variety, rare spawns.
- **M3** progression: town shop, potions, heart containers, more gear.
- **M4** the dragon fight: fire breath, claw swipe, tail sweep, wing flap, and a summit you can
  be knocked off and have to climb back up.
- **M5** audio, particles, damage numbers, match flow.

Known gaps: the town uses market stalls and a windmill rather than real houses (the fantasy
town kit is modular walls and roofs, so buildings need an assembler), and there is no defeat
condition — a wiped party respawns and can try the dragon again indefinitely.
