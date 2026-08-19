class_name Pickup
extends Node3D

## A coin or heart lying on the ground waiting to be walked into.
##
## Only the host decides a pickup was collected, then tells everyone to remove it. Letting each
## client claim locally would pay a four-player party four times for one coin.

enum Kind { GOLD, HEART }

const COLLECT_RADIUS := 1.6
const BOB_HEIGHT := 0.18
const LIFETIME := 90.0

var kind: Kind = Kind.GOLD
var amount: int = 1

var _base_height: float = 0.0
var _time: float = 0.0
var _collected: bool = false


func setup(pickup_kind: Kind, value: int, position: Vector3) -> void:
	kind = pickup_kind
	amount = value
	global_position = position
	_base_height = position.y
	_build_visual()


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	position.y = _base_height + sin(_time * 3.0) * BOB_HEIGHT + BOB_HEIGHT
	rotation.y += delta * 1.8

	if _time > LIFETIME:
		queue_free()
		return
	if not NetworkManager.is_host():
		return
	for body in PlayerRegistry.living_bodies():
		if body.global_position.distance_to(global_position) <= COLLECT_RADIUS:
			_collect(body)
			return


func _collect(player: Node) -> void:
	_collected = true
	if NetworkManager.is_networked():
		_net_collected.rpc(player.get_path())
	else:
		_net_collected(player.get_path())


@rpc("authority", "call_local", "reliable")
func _net_collected(player_path: NodePath) -> void:
	var player := get_node_or_null(player_path) as PlayerCharacter
	if player != null:
		match kind:
			Kind.GOLD:
				## Gold is a party pool, so it does not matter who physically ran over the coin.
				player.add_gold(amount)
			Kind.HEART:
				player.heal(amount)
	queue_free()


func _build_visual() -> void:
	var mesh: Mesh
	var color: Color
	if kind == Kind.GOLD:
		var coin := CylinderMesh.new()
		coin.top_radius = 0.3
		coin.bottom_radius = 0.3
		coin.height = 0.08
		coin.radial_segments = 8  ## Faceted on purpose, to sit alongside the low-poly kits.
		mesh = coin
		color = Color(1.0, 0.82, 0.25)
	else:
		var heart := SphereMesh.new()
		heart.radius = 0.28
		heart.height = 0.56
		heart.radial_segments = 8
		heart.rings = 4
		mesh = heart
		color = Color(0.95, 0.25, 0.35)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.9
	mesh.material = material

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.rotation_degrees.x = 90.0 if kind == Kind.GOLD else 0.0
	add_child(instance)
