class_name Projectile
extends Node3D

## An arrow, bolt or fireball in flight.
##
## Runs on every peer so everyone sees the same shot, but only the host's copy checks for hits
## -- the others are pure decoration. Hit detection is a distance test rather than a physics
## body because these are small, fast and numerous, and a sphere check against the handful of
## live combatants is both cheaper and easier to reason about than tunnelling-prone collision.

## Generous enough that a fast arrow never slips past a skeleton between frames. Combined with
## the target's own hit_radius, so this is the arrow's fatness rather than the target's size.
const HIT_RADIUS := 0.9
const MAX_LIFETIME := 3.0

var ability: AbilityData
var shooter: Combatant

var _velocity: Vector3
var _travelled: float = 0.0
var _life: float = 0.0
var _spent: bool = false


func launch(from: Combatant, data: AbilityData, origin: Vector3, aim: Vector3) -> void:
	shooter = from
	ability = data
	## Launched from the shooter's mid-body and aimed at the target's, so a flat shot travels
	## through the height everything is actually standing at. Firing from a fixed offset above
	## the shooter's feet used to send every arrow over the top of every target.
	var launch_height := from.hit_height * 0.5 if from != null else 0.9
	global_position = origin + Vector3.UP * launch_height
	var direction := aim.normalized() if aim.length_squared() > 0.001 else Vector3.FORWARD
	_velocity = direction * data.projectile_speed
	look_at(global_position + direction, Vector3.UP)
	_build_visual(data.vfx_color)


func _process(delta: float) -> void:
	if _spent:
		return
	var step := _velocity * delta
	global_position += step
	_travelled += step.length()
	_life += delta

	if _travelled > ability.range or _life > MAX_LIFETIME:
		_finish()
		return

	## Only the host decides anything landed. Clients would otherwise each award their own
	## damage and a four-player game would deal four times the intended hit.
	if not NetworkManager.is_host() or shooter == null or not is_instance_valid(shooter):
		return

	## Proximity first: catches grazing shots and targets whose collider is narrower than the
	## body it represents.
	for candidate in CombatResolver.radius_targets(get_tree(), shooter, global_position, HIT_RADIUS):
		_impact(candidate)
		return

	## Then sweep the segment actually travelled this frame, so a fast arrow cannot step past a
	## target between frames. Crucially this ray has to tell a target apart from a wall: it used
	## to treat any hit as terrain and quietly delete the projectile, which meant every arrow
	## and bolt died on the target's own collision capsule one frame before the proximity test
	## would have scored it -- the Archer and Wizard could not damage anything at all.
	var query := PhysicsRayQueryParameters3D.create(global_position - step, global_position)
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var struck := hit["collider"] as Combatant
	if struck != null and shooter.is_hostile_to(struck):
		## Land it where the ray actually met the body, so an explosion is centred on the impact
		## rather than wherever the projectile happened to be at end of frame.
		global_position = hit["position"]
		_impact(struck)
		return
	## Anything else is scenery: a missed shot dies on the terrain instead of sailing off the map.
	_finish()


func _impact(first: Combatant) -> void:
	if ability.radius > 0.0 and ability.shape == AbilityData.Shape.PROJECTILE:
		## Explosive shots (the Wizard's fireball) catch everything nearby, which is what makes
		## herding a pack towards a ledge worthwhile.
		for target in CombatResolver.radius_targets(get_tree(), shooter, global_position, ability.radius):
			target.take_damage(ability.damage, global_position, ability.knockback,
					ability.knockback_lift)
	else:
		first.take_damage(ability.damage, global_position, ability.knockback,
				ability.knockback_lift)
	_finish()


func _finish() -> void:
	_spent = true
	queue_free()


func _build_visual(color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 0.7)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
