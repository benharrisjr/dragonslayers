class_name MagicRing
extends Node3D

## The mage's charged spell, as everyone sees it: a ring of magic that bursts outwards from the
## mage to the spell's full reach and fades, with a fainter one trailing it. Picture only -- the
## host resolves what it catches (a NOVA through AbilityRunner) when the wind-up ends, which is
## when the ring is set off here.

const EXPAND := 0.35
const FADE := 0.45

var _radius: float = 6.5
var _age: float = 0.0
var _delay: float = 0.0
var _rings: Array[MeshInstance3D] = []
var _material: StandardMaterial3D


func burst(caster: Node3D, radius: float, colour: Color, delay: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	global_position = caster.global_position + Vector3.UP * 0.6
	_radius = radius
	_delay = delay
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = colour
	_material.emission_enabled = true
	_material.emission = colour
	for index in 2:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 8
		torus.material = _material
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		add_child(ring)
		_rings.append(ring)


func _process(delta: float) -> void:
	_age += delta
	var t := _age - _delay
	if t < 0.0:
		return
	if t > EXPAND + FADE:
		queue_free()
		return
	for index in _rings.size():
		var ring := _rings[index]
		## The second ring trails the first, a little smaller.
		var grow := clampf((t - index * 0.08) / EXPAND, 0.0, 1.0)
		ring.visible = grow > 0.0
		var size := lerpf(0.4, _radius * (1.0 - index * 0.25), 1.0 - pow(1.0 - grow, 3.0))
		ring.scale = Vector3(size, 1.0 + 2.0 * (1.0 - grow), size)
	_material.albedo_color.a = clampf(1.0 - (t - EXPAND) / FADE, 0.0, 1.0)
