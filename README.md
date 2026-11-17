# Dragonslayers

A 3D action / platformer / lite-RPG for four players, online and on one couch, built in
Godot 4.6 on KayKit and Kenney art.

Up to four heroes cross a 16-chunk world that is randomly assembled every run -- from the
beach, across the ground and the highlands -- finding gear on the way, and climb the mountain
to kill the dragon. There are no classes: what you can do is what you carry. Nearly every attack in the game — theirs and yours — knocks back, and the terrain is
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
online game**, then everyone on this machine claims a seat. Hosts get a waiting room with a
**Start the hunt** button; joining takes an address, which can be typed or entered on the
on-screen number pad with a gamepad.

Command line shortcuts, mostly for testing:

```sh
$GODOT --path . -- --solo --slots=2 --seed=4242     # straight into a 2-player split screen
$GODOT --path . -- --host --slots=1                 # host and start immediately
$GODOT --path . -- --join=192.168.1.20              # join a host
```

## Controls

Everything, menus included, works on a gamepad alone, on keyboard and mouse alone, or any mix.

**Seats are claimed in the lobby, not assigned.** On the "Who is playing?" screen each person
presses `A` on their gamepad or `Space` on the keyboard to take the next player slot (`B` /
`Esc` gives it back, `Start` / `Enter` begins). So a solo player can use a pad, two people can
share a keyboard and a pad, and four pads is four players. `scripts/player/player_bindings.gd`
turns those claims into each player's input actions at runtime.

| | Keyboard and mouse | Gamepad |
|---|---|---|
| Move | `WASD` / arrows | left stick |
| Hotkey 1 / 2 / 3 | left mouse or `J` / `K` / `L` | `X` / `Y` / `B` |
| Jump (needs the feather) | `Space` | `A` |
| Dash (needs the boots) | `Shift` | `RT` |
| Gear panel | `I` | `Select` |
| Target | click an enemy, or `Tab` / `Backspace` to cycle | `RB` / `LB` cycle |
| Interact (chests) | `F` | d-pad up |
| Turn camera | `Q` / `E`, or hold **right mouse** and drag | right stick (also tilts) |
| Pause / options | `Esc` | `Start` |

The gear panel belongs to one player and opens in their own pane: stick left and right picks
an item, pressing a hotkey button puts it on that button, and the same button closes the
panel. Only that player stops moving while it is open.

In menus the gamepad drives the template's pointing hand: d-pad moves it between buttons, `A`
presses, `B` backs out, and the left stick moves a free cursor. During play that cursor is
switched off so the stick only moves the character. The pause menu does not stop the world
(it cannot, online) -- it stops the local players reading their controls.

Gameplay controls are not yet rebindable from Options > Keybindings; that screen covers the
menu actions. Select used to be the template's Report Bug button on a gamepad; it is the gear
panel now, and `F7` still opens the report form.

Holding right mouse captures the pointer and turns the camera freely — horizontally it does
exactly what Q and E do, and vertically it tilts within a bounded range of whatever framing is
active, so a drag never undoes the boss pull-back and never drops the view so low that the ledge
you are about to be knocked off stops being visible.

Clicking an enemy both targets it and swings, so click-targeting never costs you a turn.
There is only one mouse, so gamepad players cycle targets with the bumpers instead — and any
attack with no target selected aims at whatever is roughly in front of you.

## How a match works

- **Health** is three hearts of four points each, so quarter-hearts are real and chip damage
  exists. Max hearts are upgradeable.
- **Gear** is everything. There are no classes -- the four heroes are looks -- and a player can
  do exactly what they are carrying lets them do (`scripts/items/item_db.gd`):

  | Item | How it is used | What it does |
  |---|---|---|
  | Sword | hotkey | A melee swing. Everyone starts with one and keeps it. |
  | Shield | hotkey, held | Blocks hits from the front: no damage, a third of the shove. Kept. |
  | Hookshot | hotkey | Fires a hook 14 m. It pulls you to anything that does not move (walls, trees, rocks, chests, the dragon) and pulls anything that does (monsters, other players) to you. |
  | Lantern | hotkey | Drops a patch of fire that burns monsters and flammable scenery -- trees, grass, fences, crates -- and leaves the party alone. |
  | Feather | passive | Lets you jump. Without it the jump button does nothing. |
  | Boots | passive | Lets you dash. |

  There are three hotkeys and four items that want one, so what to keep ready is a choice.
- **Finding gear.** The first chest in every chunk is the large one and holds one item. The
  town's always holds a feather; the rest take turns, so a map has a few of each. A player who
  already has an item walks past a second one and leaves it for a friend.
- **Dying** is a setback, not an elimination: you come back after a few seconds on half
  health. But everything except your sword and shield is left on the ground where you fell,
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

Sixteen 128 m chunks in a 4×4 grid, 512 m across, stepping down from the mountain:

| Tier | Which chunks | Ground height | Biomes |
|---|---|---|---|
| Summit | the mountain, always on an edge of the map | platform at 23.4 m | mountain |
| Highlands | the chunks touching the mountain | 12.6 m | temple, forest, plains, fields |
| Ground | everything beyond those | 5.4 m | town, plains, fields, forest, desert, lake, temple |
| Sea | two to four of the furthest chunks, in one connected stretch of coast | sand at 0.9 m, water line at 0.45 m | beach |

**Everything essential can be walked to.** A player without the feather cannot jump, so a
single 0.9 m step is a wall to them, and the generator is built around that:

- Wherever a chunk meets lower ground it cuts a **ramp** down to it: four tiles wide, one
  level per tile (about 24 degrees).
- The **mountain** is terraces too tall to hop, with one ramp from its rim to the dragon's
  platform. Being thrown off the platform lands you on a terrace you walk down from.
- **Mesas** -- raised ground one or two steps up -- are optional. Any ground-level pocket that
  mesas would wall off is filled in, so they are places a jump or a hookshot earns, never
  barriers. Small chests may sit on them; the large gear chest never does.
- The **beach** slopes under the water rather than stepping, so the sea is waded into and out
  of. The lake is ankle-deep over level ground.
- **Pits** are rare and deliberate: two in a temple, one in a desert, none anywhere else.
- Scenery is roughly a third as dense as it was, and none of it stands on a chunk's rim, a
  ramp or a slope.

`scripts/tests.gd` checks the promise directly: with no jump at all, a flood fill from the
town reaches the dragon's platform, the sea and every chunk, across several seeds.

The whole grid is ringed by cliffs. The innermost wall stands directly against the edge
chunks and rises 24 m, clearing the highest of them, and thirteen terraces climb behind it to
about 100 m, so the ring reads as foothills rather than one slab. It stops the party walking
out of the world, but mostly it fills the horizon. Pits are sealed at the bottom by black
caps, built as a separate mesh from the terrain so they are scenery rather than collision.

Terrain is a per-chunk grid of 0.9 m levels (`scripts/world/terrain_data.gd`), where each tile
is flat, a ramp, or a shore tile whose corners rise to meet the ground above it. It is
generated as vertex-coloured geometry rather than built from the Kenney block meshes, because
those only exist in grass and snow and all share one colour atlas.

**Nothing about the map is ever sent over the network.** The host broadcasts one integer seed
and every machine generates identical terrain, identical monsters with identical node names,
and identical chests. That is also why there is no `MultiplayerSpawner`: matching node paths
on every peer mean combat RPCs address the same object everywhere. Things that appear later --
coins, hearts, dropped gear -- are spawned by the host with a serial number for a name, so
they match too.

## Multiplayer

The world is host-authoritative — monsters, chests, loot and all damage are decided by the
host — while player movement is owned by whichever machine is driving it. That trade buys
responsive movement at the cost of cheat resistance, which is the right way round for a game
you play with friends. The host can still shove a player, because knockback arrives as an
explicit impulse the owner always applies, never as a position correction. Hits, heals and
hookshot pulls are sent by the host to every machine, including the one that owns the player
being hit; gear changes hands the same way.

Not handled yet: a player who joins a match already in progress is not told what gear the
others hold, which chests are open, or what is lying on the ground.

A player is `(peer, local slot)`, so one machine can contribute up to four split-screen
players to an online game. Panes are SubViewports sharing one `World3D`: one simulation, four
camera renders. Transport lives behind `scripts/net/transport.gd` so a Steam peer can replace
ENet without touching game code.

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

`art/models/dragon.3ds` cannot be imported by Godot, and Blender is not needed:
`tools/convert_dragon.py` reads the 3DS chunks directly and writes `art/models/dragon.glb` —
reoriented Z-up to Y-up, scaled to 5.6 m tall with a 12.6 m wingspan, flat-shaded with the
source's two greens baked into vertex colours, and fitted with a generated 20-bone skin so the
wings, tail, neck and legs can move. Attack animations are authored on that rig in Godot
rather than baked by the script, so they can be tuned against live hitboxes.

```sh
python3 tools/convert_dragon.py    # only needed if dragon.3ds changes
```

Animation is not baked into the .glb: `DragonAnimator` holds the clips as keyframe tables and
evaluates them straight onto bone poses. With no authored clips to import there is nothing to
match track paths against, and an attack's damage has to land on the frame its animation looks
like it lands — a table of times in one file is where that gets tuned.

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
$GODOT --path . --headless res://scenes/tests.tscn   # 298 logic checks
$GODOT --path . --headless -- --playtest --slots=2   # drives a real match end to end
$GODOT --path . --headless -- --padcheck             # splash -> menu -> lobby -> match -> gear panel -> pause -> menu, on a simulated gamepad
$GODOT --path . -- --solo --capture=/tmp/map.png --capture-overview   # photograph the whole map from above
$GODOT --path . -- --solo --capture=/tmp/gear.png --capture-gear      # photograph the gear panel
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
scenes/        template screens: splash/, menu/ (main menu, options, credits), ui/ (widgets)
scripts/
  characters/  runtime KayKit model + animation assembly
  combat/      Combatant, CombatResolver, AbilityRunner, Projectile
  player/      controller, input, targeting, camera
  items/       ItemDB (the gear) and the hookshot
  enemies/     monster AI, dragon
  world/       generator, chunk mesher, chunks, biomes, chests, pickups
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

## Next

- **M2** the remaining biome content: temple interiors, per-biome monster variety, rare spawns.
- **M3** progression: town shop, potions, heart containers, more gear.
- **M4** the dragon fight: fire breath, claw swipe, tail sweep, wing flap, and a summit you can
  be knocked off and have to climb back up.
- **M5** audio, particles, damage numbers, match flow.

Known gaps: the town uses market stalls and a windmill rather than real houses (the fantasy
town kit is modular walls and roofs, so buildings need an assembler), and there is no defeat
condition — a wiped party respawns and can try the dragon again indefinitely.
