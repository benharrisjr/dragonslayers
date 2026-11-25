class_name Bomb
extends Node3D

## A bomb: set down by someone standing still, or thrown like a rock by someone on the move. It
## comes to rest where it lands and goes off when its fuse has burnt down -- an orange ball of
## fire that knocks back and hurts everyone inside it, the one who lit it included.
##
## Like a thrown rock, one flies on every peer from the same origin and velocity and goes off on
## each machine; only the host's copy hurts anything or blows open a wall.

const DAMAGE := 2
const KNOCKBACK := 17.0
const KNOCKBACK_LIFT := 0.5
## The blast's reach, from the bomb to the edge of a body.
const RADIUS := 3.2
## Seconds from being lit to going off. It blinks faster over the last stretch.
const FUSE := 2.2
const RADIUS_BODY := 0.24
const BLAST_COLOR := Color(1.0, 0.55, 0.12)

var thrower: PlayerCharacter
var velocity: Vector3 = Vector3.ZERO
var resting: bool = false

var _model: Node3D
var _spark: Node3D
var _age: float = 0.0
var _done: bool = false


func launch(player: PlayerCharacter, origin: Vector3, initial: Vector3) -> void:
	thrower = player
	velocity = initial
	## Set by hand because the effects root hangs under a Control, which passes nothing down.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	_model = ItemDB.bomb_model(RADIUS_BODY)
	_model.position.y = RADIUS_BODY
	add_child(_model)
	_spark = _model.get_node_or_null("Spark") as Node3D
	global_position = origin
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	_blink()
	if _age >= FUSE:
		explode()
		return
	if resting:
		return
	velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)) * delta
	var step := velocity * delta
	var hit := _sweep(step)
	if hit.is_empty():
		global_position += step
		if global_position.y < Combatant.KILL_HEIGHT:
			queue_free()
		return
	var normal: Vector3 = hit["normal"]
	if normal.y > 0.6:
		## Ground: it stops where it lands.
		global_position = hit["position"]
		velocity = Vector3.ZERO
		resting = true
	else:
		## A wall or a body: it drops straight down from just short of it.
		global_position = (hit["position"] as Vector3) + normal * 0.3
		velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)


func _sweep(step: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	if space == null or step.length_squared() < 0.000001:
		return {}
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	query.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_SCENERY \
			| Combatant.LAYER_COMBATANT
	if thrower != null and is_instance_valid(thrower):
		query.exclude = [thrower.get_rid()]
	return space.intersect_ray(query)


## The fuse's spark flickers, faster as it burns down, and the shell glows on each beat.
func _blink() -> void:
	if _spark == null:
		return
	var left := FUSE - _age
	var rate := 3.0 if left > 1.0 else 9.0
	var on := fmod(_age * rate, 1.0) < 0.5
	_spark.scale = Vector3.ONE * (1.6 if on else 0.8)
	var shell := _model.get_node_or_null("Shell") as MeshInstance3D
	if shell != null and shell.material_override is StandardMaterial3D:
		(shell.material_override as StandardMaterial3D).emission = \
				BLAST_COLOR if on and left < 1.0 else Color(0.12, 0.12, 0.16)


## Goes off where it is. The host hurts and shoves everyone in reach, and blows open any cracked
## wall it is beside; every peer sees the fireball.
func explode() -> void:
	if _done:
		return
	_done = true
	var at := global_position + Vector3.UP * RADIUS_BODY
	GameSfx.play_at(&"bomb", at)
	_show_blast(at)
	GrassField.cut_all(get_tree(), at, RADIUS)
	LeafField.kick_all(get_tree(), at, RADIUS + 0.5, Vector3.ZERO, 9.0)
	if NetworkManager.is_host():
		for body in caught(get_tree(), at):
			body.take_damage(DAMAGE, at, KNOCKBACK, KNOCKBACK_LIFT)
		DungeonEntrance.blasted(get_tree(), at, RADIUS)
		DungeonEntrance.struck(get_tree(), at, RADIUS)
	queue_free()


## Everyone the blast at `at` reaches, players and monsters alike.
static func caught(tree: SceneTree, at: Vector3) -> Array[Combatant]:
	var found: Array[Combatant] = []
	for node in tree.get_nodes_in_group("combatants"):
		var body := node as Combatant
		if body == null or body.is_dead:
			continue
		if body.hit_centre().distance_to(at) <= RADIUS + body.hit_radius + body.hit_height * 0.25:
			found.append(body)
	return found


func _show_blast(at: Vector3) -> void:
	var root := GameWorld.effects_root(get_tree())
	if root == null:
		return
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	ball.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(BLAST_COLOR, 0.85)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * 0.3
	var light := OmniLight3D.new()
	light.light_color = BLAST_COLOR
	light.light_energy = 6.0
	light.omni_range = RADIUS * 3.0
	ball.add_child(light)
	var tween := ball.create_tween()
	tween.tween_property(ball, "scale", Vector3.ONE * RADIUS, 0.18) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(material, "albedo_color", Color(1.0, 0.8, 0.3, 0.0), 0.45) \
			.set_delay(0.08)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.4)
	tween.tween_callback(ball.queue_free)
