class_name Boomerang
extends Node3D

## A thrown boomerang: out in a straight line, then back to whoever threw it.
##
## It flies on every peer from the same origin and aim, like a thrown rock; only the host's copy
## decides what it hit. Anything it passes through -- monster, the dragon, another player, but
## never the thrower -- takes one point, a small shove and a stun, once per throw. It turns back
## early if it meets a wall or a tree, and on the way it cuts long grass and scatters leaves.
## Anything lying loose that it passes over (see Pickup) comes back with it.
## One in the air at a time: the button does nothing until it is caught.

const RANGE := 13.0
const SPEED := 17.0
const RETURN_SPEED := 19.0
## How far from a body's surface it still connects.
const HIT_RADIUS := 0.6
const DAMAGE := 1
const STUN := 1.2
const KNOCKBACK := 3.0
## Caught once it is this close to the thrower.
const CATCH_DISTANCE := 1.0
## Flown at chest height, so it meets bodies rather than skimming the ground.
const HEIGHT := 1.0
## If it has not made it home by now it gives up (a thrower who ran off a cliff, say).
const MAX_LIFE := 6.0
const SPIN := 22.0

var thrower: PlayerCharacter

var _direction: Vector3 = Vector3.FORWARD
var _returning: bool = false
var _travelled: float = 0.0
var _life: float = 0.0
var _struck: Dictionary = {}
var _model: Node3D
var _done: bool = false


func throw(player: PlayerCharacter, origin: Vector3, aim: Vector3) -> void:
	thrower = player
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var flat := Vector3(aim.x, 0.0, aim.z)
	_direction = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	global_position = origin + Vector3.UP * HEIGHT
	_model = ItemDB.build_model(ItemDB.BOOMERANG)
	_model.scale = Vector3.ONE * 2.2
	add_child(_model)
	reset_physics_interpolation()


func is_returning() -> bool:
	return _returning


func _physics_process(delta: float) -> void:
	if _done:
		return
	_life += delta
	if _model != null:
		_model.rotation.y += SPIN * delta
	if thrower == null or not is_instance_valid(thrower) or thrower.is_dead or _life > MAX_LIFE:
		_finish()
		return
	if not _returning:
		var step := _direction * SPEED * delta
		if _blocked(step):
			_returning = true
		else:
			global_position += step
			_travelled += step.length()
			if _travelled >= RANGE:
				_returning = true
	else:
		var home := thrower.global_position + Vector3.UP * HEIGHT
		var to_home := home - global_position
		if to_home.length() <= CATCH_DISTANCE:
			_finish()
			return
		global_position += to_home.normalized() * minf(RETURN_SPEED * delta, to_home.length())
	_strike()
	var ground := global_position - Vector3.UP * HEIGHT
	GrassField.cut_all(get_tree(), ground, 0.9)
	LeafField.kick_all(get_tree(), ground, 1.1, _direction if not _returning else -_direction, 3.0)


func _blocked(step: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position,
			global_position + step + step.normalized() * 0.3)
	query.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_SCENERY
	return not space.intersect_ray(query).is_empty()


## Host: whatever it passes through takes the hit, once per throw.
func _strike() -> void:
	if not NetworkManager.is_host():
		return
	for node in get_tree().get_nodes_in_group("combatants"):
		var body := node as Combatant
		if body == null or not thrower.can_hit(body) or _struck.has(body.get_instance_id()):
			continue
		if body.hit_centre().distance_to(global_position) > HIT_RADIUS + body.hit_radius \
				+ body.hit_height * 0.35:
			continue
		_struck[body.get_instance_id()] = true
		body.take_damage(DAMAGE, global_position, KNOCKBACK, 0.15)
		body.stun(STUN)
	## Loot it passes over -- coins, hearts, gear -- rides back on it to the thrower. It flies
	## at chest height, so the reach is measured down to the ground beneath it.
	for pickup in Pickup.near(get_tree(), global_position - Vector3.UP * (HEIGHT * 0.6),
			Pickup.SNATCH_RADIUS + 0.2):
		pickup.start_carry(thrower, &"boomerang")


func _finish() -> void:
	_done = true
	if thrower != null and is_instance_valid(thrower):
		thrower.boomerang_caught(self)
	queue_free()
