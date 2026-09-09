# Dragonslayers

A 3D action / platformer / lite-RPG for four players, online and on one couch, built in
Godot 4.6 on KayKit and Kenney art.

Four archetypes (Knight, Shaman, Archer, Wizard) fight through a 16-chunk world that is
randomly assembled every run, earn gold and abilities, and climb the mountain to kill the
dragon. Nearly every attack in the game — theirs and yours — knocks back, and the terrain is
built out of ledges. Getting shoved off one is not a bug.

## Running

Godot 4.6 is required. This machine has it at `~/Downloads/Godot.app`:

```sh
GODOT=~/Downloads/Godot.app/Contents/MacOS/Godot

$GODOT --path . --headless --import    # first time only, or after adding assets
$GODOT --path .                        # play
```

From the menu: **Play solo / local co-op** for one machine, **Host online game** then Space
once everyone has joined, or type an address and **Join**.

Command line shortcuts, mostly for testing:

```sh
$GODOT --path . -- --solo --slots=2 --seed=4242     # straight into a 2-player split screen
$GODOT --path . -- --host --slots=1                 # host and start immediately
$GODOT --path . -- --join=192.168.1.20              # join a host
```

## Controls

Slot 1 is keyboard and mouse. Slots 2-4 are gamepads, one per player, in the order the OS
reports them.

| | Keyboard (slot 1) | Gamepad (slots 2-4) |
|---|---|---|
| Move | `WASD` / arrows | left stick |
| Jump | `Space` | `A` |
| Attack | left mouse | `X` |
| Abilities | `1` `2` `3` `4` | `Y`, `B`, triggers |
| Target | click an enemy, or `Tab` to cycle | bumpers cycle |
| Interact (chests) | `F` | d-pad up |
| Turn camera | `Q` / `E`, or hold **right mouse** and drag | right stick |

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
- **Magic** is a 0-100 meter that abilities spend and that refills after three seconds without
  casting. Weapon attacks are free, so a drained player is never helpless.
- **Gold** is a party pool, spent at the town shop. Loot drops at a monster's last footing
  rather than wherever its corpse landed, so shoving something off a cliff never costs you the
  reward for the kill.
- **Dying** is a setback, not an elimination: you come back after a few seconds on half health.
- **Falling off the world** costs a heart and puts you back on the last solid ground you stood
  on.
- **Reach** is measured surface to surface. Every combatant carries a `hit_radius` and
  `hit_height`, and attacks aim at mid-body, because a body's origin sits at its feet — without
  that, a 5.6 m dragon is a point on the floor inside its own collision capsule that nothing
  can reach, and flat projectiles sail over everything.

## The map

Sixteen 128 m chunks in a 4×4 grid — 512 m across, drawn every run from exactly the requested distribution:
Town ×1, Temple ×3, Desert ×1, Lake ×1, Forest ×1, Mountain ×1, Plains ×4, Fields ×4. The
mountain is always on an edge and the town always at least two chunks from it, so there is a
journey between the shop and the dragon.

The mountain climbs 54 m to its summit. The whole grid is ringed by fourteen terraces of
unclimbable cliff rising 100 m over 170 m of ground, growing taller as they go out so the ring
reads as foothills climbing into peaks rather than one slab.
It stops the party walking out of the world, but mostly it fills the horizon: without it you
stand at the rim of an outer chunk and watch the map end in mid-air with sky underneath. Pits
are sealed at the bottom by black caps, built as a separate mesh from the terrain so they are
scenery rather than collision — a floor you could land on would undo the whole point of a pit.

Terrain is a per-chunk heightmap of 0.9 m plateaus with vertical cliffs between them — one
step is a comfortable jump, two is not. It is generated as vertex-coloured geometry rather
than built from the Kenney block meshes, because those only exist in grass and snow and all
share one colour atlas; eight biomes would have needed eight repainted atlases.

**Nothing about the map is ever sent over the network.** The host broadcasts one integer seed
and every machine generates identical terrain, identical monsters with identical node names,
and identical chests. That is also why there is no `MultiplayerSpawner`: matching node paths
on every peer mean combat RPCs address the same object everywhere.

## Multiplayer

The world is host-authoritative — monsters, chests, loot and all damage are decided by the
host — while player movement is owned by whichever machine is driving it. That trade buys
responsive movement at the cost of cheat resistance, which is the right way round for a game
you play with friends. The host can still shove a player, because knockback arrives as an
explicit impulse the owner always applies, never as a position correction.

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

`models/dragon.3ds` cannot be imported by Godot, and Blender is not needed:
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
$GODOT --path . --headless res://scenes/tests.tscn   # 252 logic checks
$GODOT --path . --headless -- --playtest --slots=2   # drives a real match end to end
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
opens, and that falling off the world costs a heart and respawns you. It also fires **all four
archetypes' basic attacks at a live target on verified clear ground**, because only a real shot
in a real world proves a projectile survives the flight.

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
autoloads/     GameState, NetworkManager, PlayerRegistry, RigAnimations, and the data DBs
data/          AbilityData / ArchetypeData / MonsterData / BiomeData resource classes
scripts/
  characters/  runtime KayKit model + animation assembly
  combat/      Combatant, CombatResolver, AbilityRunner, Projectile
  player/      controller, input, targeting, camera
  enemies/     monster AI, dragon
  world/       generator, chunk mesher, chunks, biomes, chests, pickups
  ui/          split screen, HUD, hearts, menu
tools/         convert_dragon.py
art/           the supplied KayKit and Kenney kits (fbx/obj folders are .gdignore'd)
```

## Next

- **M2** the remaining biome content: temple interiors, per-biome monster variety, rare spawns.
- **M3** progression: town shop, potions, heart containers, the ability-drop system.
- **M4** the dragon fight: fire breath, claw swipe, tail sweep, wing flap, and a summit you can
  be knocked off and have to climb back up.
- **M5** audio, particles, damage numbers, match flow.

Known gaps: the town uses market stalls and a windmill rather than real houses (the fantasy
town kit is modular walls and roofs, so buildings need an assembler), and there is no defeat
condition — a wiped party respawns and can try the dragon again indefinitely.
