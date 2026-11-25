class_name Hookshot
extends Node3D

## A hookshot in flight: a cone on the end of a line.
##
## It flies a set distance from the player who fired it. If it strikes something that does not
## move -- a wall, a tree, a rock, a chest -- it bites, and the player is pulled to it. If it
## strikes something that does -- a monster, another player -- that is pulled to the player
## instead. If it strikes loot lying on the ground -- coins, hearts, gear -- it reels that in.
## If it strikes nothing it comes back.
##
## One of these exists on every peer, launched from identical parameters, so the line looks the
## same everywhere. Only the copy on the machine that owns the player tests for collisions; what
## it finds reaches the others as calls on the player (latch, catch, retract).

enum State { OUT, LATCHED, CAUGHT, RETURNING }

const RANGE := 14.0
const SPEED := 42.0
const RETURN_SPEED := 52.0
## How fast a latched player travels, and how fast a caught body is dragged.
const PULL_SPEED := 24.0
## Close enough to the anchor to let go.
const ARRIVE_DISTANCE := 1.5
## A pull that has not arrived by now is not going to.
const MAX_PULL_TIME := 1.6
const COLOR := Color(0.95, 0.6, 0.25)

var owner_player: PlayerCharacter
var state: State = State.OUT
## World position of the hook's point.
var head: Vector3
var direction: Vector3 = Vector3.FORWARD
var caught: Combatant
## Seconds spent pulling, either way round.
var pull_time: float = 0.0

var _travelled: float = 0.0
var _head_mesh: Node3D
var _line: MeshInstance3D


func launch(player: PlayerCharacter, origin: Vector3, aim: Vector3) -> void:
	owner_player = player
	head = origin
	direction = aim.normalized() if aim.length_squared() > 0.001 else Vector3.FORWARD
	## Driven by hand every frame, so there is nothing for physics interpolation to smooth.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_visual()
	_update_visual()


## The player is being reeled in towards the hook.
func is_reeling_owner() -> bool:
	return state == State.LATCHED


func latch(point: Vector3) -> void:
	head = point
	state = State.LATCHED
	pull_time = 0.0


func catch(body: Combatant) -> void:
	caught = body
	state = State.CAUGHT if body != null else State.RETURNING
	pull_time = 0.0


func retract() -> void:
	state = State.RETURNING
	caught = null


func _physics_process(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		queue_free()
		return
	var mine := owner_player.is_local_player()
	match state:
		State.OUT:
			var step := SPEED * delta
			if mine and _strike(step):
				return
			head += direction * step
			_travelled += step
			if _travelled >= RANGE:
				if mine:
					owner_player.hook_release()
				else:
					state = State.RETURNING
		State.LATCHED:
			## The owner's controller does the travelling and decides when to let go.
			pull_time += delta
		State.CAUGHT:
			pull_time += delta
			if caught != null and is_instance_valid(caught):
				head = caught.hit_centre()
			if mine:
				var gone := caught == null or not is_instance_valid(caught) or caught.is_dead
				if gone or pull_time > MAX_PULL_TIME \
						or head.distance_to(owner_player.hit_centre()) < ARRIVE_DISTANCE + 0.8:
					owner_player.hook_release()
		State.RETURNING:
			var home := owner_player.hit_centre()
			head = head.move_toward(home, RETURN_SPEED * delta)
			if head.distance_to(home) < 0.6:
				owner_player.hook_finished(self)
				queue_free()


## Owner only: sweeps the next stretch of flight and reports whatever it runs into.
func _strike(step: float) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	## Loot lying in the hook's path: it bites that and reels it in. Checked along the stretch
	## in a few points, since at 42 m/s one frame's flight is longer than a pickup is wide.
	for sample in 3:
		var point := head + direction * step * (sample + 1) / 3.0
		var found := Pickup.near(get_tree(), point)
		if not found.is_empty():
			head = found[0].global_position
			owner_player.hook_struck_pickup(found[0])
			return true
	var query := PhysicsRayQueryParameters3D.create(head, head + direction * step)
	query.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_COMBATANT \
			| Combatant.LAYER_SCENERY
	query.exclude = [owner_player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	head = hit["position"]
	var body := hit["collider"] as Combatant
	## The dragon is not going anywhere: against it the hook behaves as it does against a wall.
	if body != null and not body.is_dead and not (body is Dragon):
		owner_player.hook_struck_body(body)
	else:
		owner_player.hook_struck_world(head)
	return true


func _process(_delta: float) -> void:
	_update_visual()


func _build_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 0.6

	## The cone's tip is +Y in mesh space; the holder turns that to face along the flight.
	_head_mesh = Node3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.22
	cone.height = 0.55
	cone.radial_segments = 8
	var cone_instance := MeshInstance3D.new()
	cone_instance.mesh = cone
	cone_instance.material_override = material
	cone_instance.rotation_degrees.x = -90.0
	_head_mesh.add_child(cone_instance)
	add_child(_head_mesh)

	var rope := BoxMesh.new()
	rope.size = Vector3(0.07, 0.07, 1.0)
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = Color(0.3, 0.27, 0.25)
	_line = MeshInstance3D.new()
	_line.mesh = rope
	_line.material_override = rope_material
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


## Puts the cone at the hook's point and stretches the line from the player's body to it.
func _update_visual() -> void:
	if _head_mesh == null or owner_player == null or not is_instance_valid(owner_player):
		return
	var hand := owner_player.get_global_transform_interpolated().origin \
			+ Vector3.UP * (owner_player.hit_height * 0.55)
	var span := head - hand
	var length := span.length()
	var along := span / length if length > 0.01 else direction
	## looking_at needs an up vector that is not parallel to the line.
	var up := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(along, up)
	_head_mesh.global_transform = Transform3D(basis, head)
	_line.visible = length > 0.05
	## Stretched along its own length (the mesh is one metre long on Z).
	_line.global_transform = Transform3D(
			basis * Basis.from_scale(Vector3(1.0, 1.0, maxf(length, 0.01))), hand + span * 0.5)
