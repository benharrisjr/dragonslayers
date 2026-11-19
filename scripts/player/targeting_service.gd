class_name TargetingService
extends Node3D

## One player's chosen target, and the reticle that marks it.
##
## Two ways in, converging on the same state: the keyboard player clicks a monster, everyone
## else cycles with a bumper. Attacks and abilities aim at whatever this holds, and fall back
## to the player's facing when it holds nothing, so a target is an aid rather than a
## requirement -- nobody should have to click before they can swing.
##
## The reticle is drawn on a per-player render layer so that four reticles in one shared
## World3D do not all show up in all four split-screen panes.

signal target_changed(target: Combatant)

## Layers 11-14 (bits 10-13) are reserved for per-player markers; PlayerCamera masks out the
## three that are not its own.
const FIRST_MARKER_LAYER := 10
const MAX_PICK_DISTANCE := 40.0

var owner_player: Combatant
var slot: int = 0

var _target: Combatant
var _reticle: MeshInstance3D
var _spin: float = 0.0


func setup(player: Combatant, player_slot: int, color: Color) -> void:
	owner_player = player
	slot = player_slot
	_build_reticle(color)


func target() -> Combatant:
	if _target != null and (not is_instance_valid(_target) or _target.is_dead):
		set_target(null)
	return _target


func set_target(value: Combatant) -> void:
	if _target == value:
		return
	_target = value
	target_changed.emit(_target)


## Bumper targeting: walks the in-range hostiles in distance order, so repeated presses step
## outwards rather than flicking between the two nearest.
func cycle(direction: int) -> void:
	var candidates := _sorted_candidates()
	if candidates.is_empty():
		set_target(null)
		return
	var index := candidates.find(_target)
	if index < 0:
		set_target(candidates[0])
		return
	set_target(candidates[wrapi(index + direction, 0, candidates.size())])


## Click targeting: a ray from that player's own camera, so it works in any split-screen pane.
func pick_at(camera: Camera3D, screen_position: Vector2) -> bool:
	if camera == null:
		return false
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * MAX_PICK_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.exclude = [owner_player.get_rid()] if owner_player != null else []
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	## A click that lands on nothing hostile leaves the target alone: the left button is also
	## the sword, and swinging at a targeted monster must not let go of it.
	if hit.is_empty():
		return false
	var combatant := hit["collider"] as Combatant
	if combatant != null and owner_player != null and owner_player.is_hostile_to(combatant):
		set_target(combatant)
		return true
	return false


## Used when a player swings with nothing selected: the thing they most likely meant.
func nearest_in_front(max_distance: float) -> Combatant:
	if owner_player == null:
		return null
	var facing := owner_player.facing()
	var best: Combatant = null
	var best_score := -1.0
	for candidate in _sorted_candidates():
		var offset := candidate.global_position - owner_player.global_position
		offset.y = 0.0
		var distance := offset.length()
		## Measured to the target's surface, matching CombatResolver. Comparing against its
		## origin instead means a large target standing well inside a swing's actual reach is
		## never auto-picked, so the swing goes wherever the player happened to be facing --
		## which on the dragon is the difference between hitting it and never touching it.
		if distance > max_distance + candidate.hit_radius or distance < 0.001:
			continue
		var score := facing.dot(offset / distance)
		if score > best_score:
			best_score = score
			best = candidate
	return best if best_score > 0.2 else null


func _process(delta: float) -> void:
	var current := target()
	if _reticle == null:
		return
	_reticle.visible = current != null
	if current == null:
		return
	_spin += delta * 2.2
	_reticle.global_position = current.get_global_transform_interpolated().origin \
			+ Vector3.UP * 2.4
	_reticle.rotation.y = _spin


func _sorted_candidates() -> Array[Combatant]:
	var out: Array[Combatant] = []
	if owner_player == null:
		return out
	for node in get_tree().get_nodes_in_group("monsters"):
		var candidate := node as Combatant
		if candidate != null and owner_player.is_hostile_to(candidate) \
				and candidate.global_position.distance_to(owner_player.global_position) <= MAX_PICK_DISTANCE:
			out.append(candidate)
	var origin := owner_player.global_position
	out.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		return a.global_position.distance_squared_to(origin) \
				< b.global_position.distance_squared_to(origin))
	return out


func _build_reticle(color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.34
	mesh.outer_radius = 0.5
	mesh.rings = 3  ## Deliberately coarse: a faceted ring matches the low-poly art.
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	mesh.material = material

	_reticle = MeshInstance3D.new()
	_reticle.name = "Reticle"
	_reticle.mesh = mesh
	_reticle.rotation_degrees.x = 90.0
	_reticle.top_level = true
	## Placed every drawn frame from the target's interpolated position.
	_reticle.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_reticle.layers = 1 << (FIRST_MARKER_LAYER + slot)
	_reticle.visible = false
	add_child(_reticle)
