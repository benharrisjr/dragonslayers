class_name FirePatch
extends Node3D

## A patch of burning ground: left behind by the dragon's breath, or dropped from a lantern.
##
## The two differ only in what they burn. The dragon's fire burns the party. A lantern's burns
## monsters and flammable scenery -- trees, grass, anything wooden. It does not hurt the party,
## but any player other than the one who dropped it who stands in it catches light and runs
## about in a panic for a few seconds, which is exactly as useful and as funny as it sounds.
##
## What turns the breath from a dodgeable cone into an area-denial tool: the arena is only 28 m
## across, and a party that keeps rolling to the same safe spot eventually finds it on fire.
## Like projectiles, these run on every peer from identical parameters and only the host's copy
## deals damage.

## Long enough to force the party to move, short enough that the arena is never entirely denied.
const LIFETIME := 7.0
## Gap between ticks. Standing in fire should hurt repeatedly but not shred a 12-point player
## in the time it takes to walk out.
const TICK_INTERVAL := 0.8
const DAMAGE := 1
## A gentle upward shove, so being burned nudges you out rather than pinning you in place.
const KNOCKBACK := 4.0

## One mesh and one material for every patch that will ever burn. Each patch used to build its
## own and then rewrite the material's alpha and emission every frame -- with a dozen of them
## alight that is a dozen material uploads per frame, and the first one also stalled on compiling
## the shader mid-fight. Fading is done per-instance instead, which touches nothing shared.
static var _shared_mesh: CylinderMesh
static var _shared_material: StandardMaterial3D

var radius: float = 2.6
## Which side this fire hurts.
var burns_faction: Combatant.Faction = Combatant.Faction.PLAYER
## Whether it sets light to flammable props.
var burns_scenery: bool = false
## The player who dropped this fire, if it came from a lantern. Their own fire never lights them.
var owner_pid: int = 0

var _age: float = 0.0
var _tick: float = 0.0
var _mesh: MeshInstance3D


func ignite(at: Vector3, patch_radius: float,
		faction: Combatant.Faction = Combatant.Faction.PLAYER, scenery: bool = false,
		from_pid: int = 0) -> void:
	burns_faction = faction
	burns_scenery = scenery
	owner_pid = from_pid
	## A lantern's fire catches quickly: the first tick lands a moment after it is dropped
	## rather than most of a second later.
	if from_pid != 0:
		_tick = TICK_INTERVAL - 0.15
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_position = at
	radius = patch_radius
	_build_visual()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	## Fades as it burns out, so players can read how much time is left on a patch.
	if _mesh != null:
		var remaining := 1.0 - (_age / LIFETIME)
		## GeometryInstance3D.transparency is per-instance, so this costs nothing shared and
		## every patch can fade on its own schedule from the same material.
		_mesh.transparency = clampf(1.0 - remaining, 0.0, 0.85)
		var pulse := 0.85 + 0.15 * sin(_age * 6.0)
		_mesh.scale = Vector3(radius * pulse, 1.0, radius * pulse)

	if not NetworkManager.is_host():
		return
	_tick += delta
	if _tick < TICK_INTERVAL:
		return
	_tick = 0.0
	burn_once()


## One tick of burning, host side: everything of the right faction standing in the fire, and
## any flammable scenery it has reached.
func burn_once() -> void:
	var group := "players" if burns_faction == Combatant.Faction.PLAYER else "monsters"
	for node in get_tree().get_nodes_in_group(group):
		var body := node as Combatant
		if body == null or body.is_dead:
			continue
		var offset := body.global_position - global_position
		offset.y = 0.0
		## Vertical slack so a patch still burns someone standing on it, but not someone on the
		## terrace below after being knocked off the edge.
		if offset.length() <= radius + body.hit_radius \
				and absf(body.global_position.y - global_position.y) < 3.0:
			body.take_damage(DAMAGE, global_position, KNOCKBACK, 0.25)
	if owner_pid != 0:
		for node in get_tree().get_nodes_in_group("players"):
			var player := node as PlayerCharacter
			if player == null or player.is_dead or player.pid == owner_pid or player.is_alight():
				continue
			var gap := player.global_position - global_position
			gap.y = 0.0
			if gap.length() <= radius + player.hit_radius \
					and absf(player.global_position.y - global_position.y) < 3.0:
				player.set_alight(PlayerCharacter.ALIGHT_TIME)
	if burns_scenery:
		var chunk := Chunk.containing(get_tree(), global_position)
		if chunk != null:
			chunk.burn_near(global_position, radius)


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = shared_mesh()
	_mesh.material_override = shared_material()
	## The shared mesh is built at unit radius so one copy serves every patch size.
	_mesh.scale = Vector3(radius, 1.0, radius)
	_mesh.position.y = 0.08
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


static func shared_mesh() -> CylinderMesh:
	if _shared_mesh == null:
		_shared_mesh = CylinderMesh.new()
		_shared_mesh.top_radius = 1.0
		_shared_mesh.bottom_radius = 1.0
		_shared_mesh.height = 0.12
		_shared_mesh.radial_segments = 10  ## Faceted, to sit with the low-poly kits.
	return _shared_mesh


static func shared_material() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.albedo_color = Color(1.0, 0.45, 0.12, 0.7)
		_shared_material.emission_enabled = true
		_shared_material.emission = Color(1.0, 0.5, 0.15)
		_shared_material.emission_energy_multiplier = 2.0
		_shared_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _shared_material
