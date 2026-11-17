class_name Combatant
extends CharacterBody3D

## Anything that can be hit: the four players, every monster, and the dragon.
##
## All damage in the game funnels through `take_damage`, and every call to it must supply a
## knockback impulse. That is not bookkeeping pedantry -- the map is built out of ledges and
## being shoved off one is a core verb, so an attack that forgot to say how hard it shoves
## would be a design bug, and making the parameter mandatory means it cannot be forgotten.
##
## Damage is always resolved on the host and then broadcast. Clients never decide that they
## were hit, which is what keeps four machines agreeing on who is alive.

signal health_changed(current: int, maximum: int)
signal died
signal damaged(amount: int, from_position: Vector3)
signal healed(amount: int)

enum Faction { PLAYER, MONSTER }

## Terrain, props and anything else you can stand on. Static.
const LAYER_WORLD := 1
## Trees, rocks and the other props. Bodies collide with them exactly as with terrain, but they
## are on a layer of their own so the camera can ignore them: a tree trunk crossing the line
## between camera and player used to snap the view inward and back, a lurch every few steps.
const LAYER_SCENERY := 4
## Players, monsters and the dragon. Separated from the world layer so that standing on another
## character cannot make it a moving platform -- see setup_body().
const LAYER_COMBATANT := 2

## Nothing in this game legitimately travels faster than this. The hardest knockback in the game
## is the dragon's tail sweep at 34 m/s, so anything past 120 is a bug, and an unclamped bug of
## that kind launches a player into orbit and ends their run with no way back.
const MAX_SPEED := 120.0

## Below this height a body has left the world. Set well under the lowest terrain so a deep pit
## still reads as a pit rather than as an instant respawn.
const KILL_HEIGHT := -25.0

## Health is counted in heart *points*: three hearts of four points each. Storing points
## rather than hearts is what lets the HUD draw honest quarter-hearts and lets a chip-damage
## attack exist at all.
const POINTS_PER_HEART := 4

## Which side this body is on. A property rather than a plain field because the group it belongs
## to has to follow it: bodies are built by add_child()ing them and *then* configuring them, so
## _ready() files them under the default faction and any later assignment used to leave them in
## the wrong group forever. That silently made every player a "monster", which meant no monster
## attack could ever find a player to hit.
@export var faction: Faction = Faction.MONSTER:
	set(value):
		faction = value
		_refresh_faction_groups()

@export var max_health: int = 12
## Scales incoming knockback. A Knight shrugs off a shove that throws a Wizard off a cliff.
@export var knockback_resistance: float = 1.0

## How big this body is for the purposes of being hit. A combatant's origin sits at its feet,
## so without these every attack would be aimed at the floor under the target and every hit
## test would treat a 5.6 m dragon as a point -- which is exactly what it used to do, making
## the dragon unhittable from outside its own collision capsule and projectiles unable to
## connect with anything at all.
@export var hit_radius: float = 0.5
@export var hit_height: float = 1.7

var health: int = 12
var is_dead: bool = false

## While this is above zero the body is being thrown and ignores its own movement input.
## Without it, a player could simply walk out of a knockback and the ledges would stop mattering.
var knockback_time: float = 0.0

## A hookshot drag in progress: where to, how fast, and how much longer to keep trying.
var _pull_point: Vector3 = Vector3.ZERO
var _pull_speed: float = 0.0
var _pull_left: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)


## Shared physics setup for every character body in the game. Kept here rather than at each
## call site because the layer split is what stops a body that walks into another body from
## inheriting its motion: move_and_slide treats a collider you are resting on as a moving
## platform, and two characters overlapping then feed each other velocity every frame until one
## of them is thrown out of the world.
static func setup_body(body: CharacterBody3D, radius: float, height: float) -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	body.add_child(shape)
	## Capsules rather than boxes: characters step up 0.9 m plateaus constantly, and a box
	## catches on every one of them.
	body.floor_max_angle = deg_to_rad(50.0)
	body.floor_snap_length = 0.6
	body.collision_layer = LAYER_COMBATANT
	body.collision_mask = LAYER_WORLD | LAYER_COMBATANT | LAYER_SCENERY
	## Only the static world may act as ground that carries you. It never moves, so in practice
	## this disables platform velocity inheritance entirely.
	body.platform_floor_layers = LAYER_WORLD
	body.platform_wall_layers = LAYER_WORLD


## Applied by every body each physics step, after its own movement logic has had its say.
func clamp_speed() -> void:
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED


func _ready() -> void:
	health = max_health
	add_to_group("combatants")
	_refresh_faction_groups()


## Keeps group membership in step with `faction`. Safe to call before the node is in the tree.
func _refresh_faction_groups() -> void:
	if not is_inside_tree():
		return
	var mine := "players" if faction == Faction.PLAYER else "monsters"
	var theirs := "monsters" if faction == Faction.PLAYER else "players"
	if is_in_group(theirs):
		remove_from_group(theirs)
	if not is_in_group(mine):
		add_to_group(mine)


## The way this body is looking. Every character model faces +Z and every controller turns its
## body with `rotation.y = atan2(x, z)`, so +Z is forward -- not Godot's usual -Z.
func facing() -> Vector3:
	return global_transform.basis.z


## True when the call in progress came from the host, or was made locally. The host decides
## damage, healing and pulls for every body, including players owned by other machines, so
## these RPCs cannot be "authority" mode: a client's player has that client as its authority,
## and Godot would drop the host's call on the floor.
func _sent_by_host() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


## The point attacks aim at and measure to: mid-body, not underfoot.
func hit_centre() -> Vector3:
	return global_position + Vector3.UP * (hit_height * 0.5)


func is_hostile_to(other: Combatant) -> bool:
	return other != null and not other.is_dead and other.faction != faction


## Host-side entry point for every hit in the game.
func take_damage(amount: int, from_position: Vector3, knockback: float,
		knockback_lift: float) -> void:
	if is_dead or not NetworkManager.is_host():
		return
	var direction := global_position - from_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		## Hit from exactly overhead or from inside the body: shove it the way it faces, so a
		## zero-length vector can never swallow the knockback silently.
		direction = facing()
	direction = direction.normalized()
	## `call_local` handles the networked case; offline there is no peer to rpc through, so the
	## same function is invoked directly rather than special-casing the whole combat path.
	if NetworkManager.is_networked():
		_net_apply_hit.rpc(amount, from_position, direction, knockback, knockback_lift)
	else:
		_net_apply_hit(amount, from_position, direction, knockback, knockback_lift)


@rpc("any_peer", "call_local", "reliable")
func _net_apply_hit(amount: int, from_position: Vector3, direction: Vector3,
		knockback: float, knockback_lift: float) -> void:
	if is_dead or not _sent_by_host():
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	damaged.emit(amount, from_position)
	apply_knockback(direction, knockback, knockback_lift)
	if health == 0:
		is_dead = true
		died.emit()


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	if NetworkManager.is_networked():
		_net_heal.rpc(amount)
	else:
		_net_heal(amount)


@rpc("any_peer", "call_local", "reliable")
func _net_heal(amount: int) -> void:
	if not _sent_by_host():
		return
	var before := health
	health = mini(max_health, health + amount)
	if health != before:
		healed.emit(health - before)
		health_changed.emit(health, max_health)


## Applied on every peer so the throw looks the same everywhere, including on the machine that
## owns the body -- the owner obeys knockback it did not ask for, which is the one place the
## host overrides client-authoritative movement.
func apply_knockback(direction: Vector3, force: float, lift: float) -> void:
	if force <= 0.0:
		return
	var scaled := force * knockback_resistance
	velocity.x = direction.x * scaled
	velocity.z = direction.z * scaled
	velocity.y = maxf(velocity.y, scaled * lift)
	## Long enough to clear a ledge edge, short enough that it never feels like a stun lock.
	knockback_time = maxf(knockback_time, 0.28)


## Host-side: drags this body towards a point, as a hookshot does. It rides on the knockback
## machinery -- the body counts as thrown and ignores its own input until it arrives -- so a
## monster's AI and a remote player's controller both obey it without knowing what a hookshot is.
func pull_towards(point: Vector3, speed: float) -> void:
	if is_dead or not NetworkManager.is_host():
		return
	if NetworkManager.is_networked():
		_net_pull.rpc(point, speed)
	else:
		_net_pull(point, speed)


@rpc("any_peer", "call_local", "reliable")
func _net_pull(point: Vector3, speed: float) -> void:
	if is_dead or not _sent_by_host():
		return
	var distance := global_position.distance_to(point)
	if distance < 0.5 or speed <= 0.0:
		return
	_pull_point = point
	_pull_speed = speed
	## A little longer than the trip should take, so a body snagged on something is let go.
	_pull_left = distance / speed + 0.25


func set_max_health(value: int) -> void:
	max_health = maxi(POINTS_PER_HEART, value)
	health = mini(health, max_health)
	health_changed.emit(health, max_health)


func hearts() -> float:
	return float(health) / float(POINTS_PER_HEART)


func max_hearts() -> int:
	return int(ceil(float(max_health) / float(POINTS_PER_HEART)))


func _tick_knockback(delta: float) -> void:
	if knockback_time > 0.0:
		knockback_time = maxf(0.0, knockback_time - delta)
	_tick_pull(delta)


## A pull is a drag, not a shove: the velocity is rewritten every step until the body arrives.
## A single impulse would be eaten by ground friction within a metre. Run by every body that
## ticks its knockback, which is all of them, on whichever machine simulates it.
func _tick_pull(delta: float) -> void:
	if _pull_left <= 0.0:
		return
	_pull_left -= delta
	var offset := _pull_point - global_position
	offset.y = 0.0
	if offset.length() < 0.8 or _pull_left <= 0.0 or is_dead:
		_pull_left = 0.0
		velocity.x *= 0.2
		velocity.z *= 0.2
		return
	var along := offset.normalized()
	velocity.x = along.x * _pull_speed
	velocity.z = along.z * _pull_speed
	## Counts as being thrown, so the body's own AI or controller leaves the velocity alone.
	knockback_time = maxf(knockback_time, 0.1)


func gravity() -> float:
	return _gravity


## Projectiles are spawned on every peer from identical parameters rather than replicated as
## objects: their motion is plain ballistics, so each machine can run it and arrive at the same
## place, and only the host's copy is allowed to resolve a hit.
func fire_projectile(ability: AbilityData, origin: Vector3, aim: Vector3) -> void:
	if NetworkManager.is_networked():
		_net_spawn_projectile.rpc(String(ability.id), origin, aim)
	else:
		_net_spawn_projectile(String(ability.id), origin, aim)


@rpc("any_peer", "call_local", "reliable")
func _net_spawn_projectile(ability_id: String, origin: Vector3, aim: Vector3) -> void:
	if not _sent_by_host():
		return
	var ability := AbilityDB.get_ability(StringName(ability_id))
	if ability == null:
		return
	var projectile := Projectile.new()
	GameWorld.effects_root(get_tree()).add_child(projectile)
	projectile.launch(self, ability, origin, aim)
