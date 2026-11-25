class_name ThrownRock
extends Node3D

## A rock in the air, thrown by a power glove, and the pieces it breaks into -- or a crate, which
## anyone can throw, and which breaks open where it lands.
##
## Like a projectile, one of these flies on every peer from the same origin and velocity, so it
## looks the same everywhere. Each copy shatters where it lands on its own machine; only the
## host's copy hurts anything. Whatever it lands on or beside -- monster, dragon or another
## player -- takes the hit and is thrown back. The one who threw it is spared.

const DAMAGE := 1
const KNOCKBACK := 17.0
const KNOCKBACK_LIFT := 0.45
## How far from the point of impact a body is still caught, beyond its own width.
const SPLASH := 2.2
const MAX_LIFE := 8.0

var thrower: PlayerCharacter
var velocity: Vector3 = Vector3.ZERO

var _rock: Node3D
var _age: float = 0.0
var _spin: Vector3 = Vector3.ZERO
var _done: bool = false


## `rock` is the model that was being carried; it is adopted as it is, size and all.
func launch(player: PlayerCharacter, rock: Node3D, origin: Vector3, initial: Vector3) -> void:
	thrower = player
	velocity = initial
	_rock = rock
	## Set by hand because the effects root hangs under a Control, which passes nothing down.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	global_position = origin
	add_child(rock)
	rock.position = Vector3.ZERO
	_spin = Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0))
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)) * delta
	var step := velocity * delta
	var hit := _sweep(step)
	if not hit.is_empty():
		_shatter(hit["position"])
		return
	global_position += step
	if _rock != null:
		_rock.rotation += _spin * delta
	if _age > MAX_LIFE or global_position.y < Combatant.KILL_HEIGHT:
		queue_free()


func _sweep(step: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null or step.length_squared() < 0.000001:
		return {}
	## A little past the step, so the rock breaks on a wall's face rather than inside it.
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + step + step.normalized() * 0.5)
	query.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_SCENERY \
			| Combatant.LAYER_COMBATANT
	if thrower != null and is_instance_valid(thrower):
		query.exclude = [thrower.get_rid()]
	return space.intersect_ray(query)


func _shatter(at: Vector3) -> void:
	_done = true
	GameSfx.play_at(&"rock_shatter", at)
	_spawn_shards(at)
	GrassField.cut_all(get_tree(), at, SPLASH)
	LeafField.kick_all(get_tree(), at, SPLASH + 0.5, Vector3.ZERO, 6.0)
	if NetworkManager.is_host():
		for node in get_tree().get_nodes_in_group("combatants"):
			var body := node as Combatant
			if body == null or body == thrower or body.is_dead:
				continue
			if body.hit_centre().distance_to(at) <= SPLASH + body.hit_radius + body.hit_height * 0.5:
				body.take_damage(DAMAGE, at, KNOCKBACK, KNOCKBACK_LIFT)
		DungeonEntrance.struck(get_tree(), at, SPLASH)
		## A thrown crate breaks open where it lands.
		if _rock != null and _rock.has_meta("crate"):
			var area := LootArea.at_point(get_tree(), at)
			if area != null:
				area.spawn_crate_loot(at + Vector3.UP * 0.5)
	queue_free()


## The pieces are the rock itself, many times over and much smaller: mesh particles drawn from
## the rock's own mesh, so sandstone breaks into sandstone and granite into granite.
func _spawn_shards(at: Vector3) -> void:
	if _rock == null:
		return
	var meshes := Culling.meshes_under(_rock)
	if meshes.is_empty() or meshes[0].mesh == null:
		return
	var shards := RockShards.new()
	GameWorld.effects_root(get_tree()).add_child(shards)
	shards.burst(meshes[0], at + Vector3.UP * 0.3,
			meshes[0].global_transform.basis.get_scale().x)
