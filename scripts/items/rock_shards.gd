class_name RockShards
extends Node3D

## What is left of a thrown rock for a second after it lands: a burst of mesh particles, each one
## the rock's own mesh at a fraction of its size, thrown outward, tumbling, and shrinking away.
##
## Run by hand rather than by a particle node -- a dozen-odd pieces for a second is nothing, and
## this way every piece is the real rock mesh with its real material, on every renderer.

const COUNT := 16
const LIFE := 1.2
const GRAVITY := 22.0

## The mesh every piece is drawn with.
var mesh: Mesh

var _age: float = 0.0
## Each: [MeshInstance3D, velocity, spin axis, spin speed, size].
var _pieces: Array[Array] = []


## `source` is the rock's mesh instance, still in the tree; `size` the scale it was drawn at.
func burst(source: MeshInstance3D, at: Vector3, size: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_position = at
	mesh = source.mesh
	for index in COUNT:
		var piece := MeshInstance3D.new()
		piece.mesh = mesh
		piece.material_override = source.material_override
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		## Outward in every direction, and always somewhat up: it has just hit the ground.
		var heading := randf() * TAU
		var out := Vector3(cos(heading), 0.0, sin(heading)) * randf_range(1.5, 7.0)
		out.y = randf_range(3.0, 10.0)
		var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		axis = axis.normalized() if axis.length_squared() > 0.01 else Vector3.UP
		var piece_size := size * randf_range(0.14, 0.34)
		piece.position = out * 0.04
		piece.basis = Basis(axis, randf() * TAU).scaled(Vector3.ONE * piece_size)
		_pieces.append([piece, out, axis, randf_range(4.0, 12.0), piece_size])


func piece_count() -> int:
	return _pieces.size()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	## Full size for the first half, then away to nothing.
	var fade := clampf((LIFE - _age) / (LIFE * 0.5), 0.0, 1.0)
	for entry in _pieces:
		var piece := entry[0] as MeshInstance3D
		var velocity := entry[1] as Vector3
		velocity.y -= GRAVITY * delta
		entry[1] = velocity
		var at := piece.position + velocity * delta
		piece.transform = Transform3D(
				Basis(entry[2] as Vector3, _age * float(entry[3]))
						.scaled(Vector3.ONE * float(entry[4]) * fade), at)
