class_name SlashTrail
extends Node3D

## The look of a sword swing: a bright crescent that sweeps left to right across the front of the swinger,
## trailing a fading tail and throwing off sparks from its leading edge.
##
## Picture only, like Gust -- the hit itself is resolved on the host by AbilityRunner. Built on
## every peer so everyone sees the swing. The crescent is drawn out to the attack's real reach and
## across its real arc, so what the player sees is what the hitbox covers.
##
## Run by hand with an ImmediateMesh rather than a particle node: one ribbon and a dozen sparks
## for a third of a second is nothing, and this way it looks the same on every renderer.

## How long the leading edge takes to cross the arc.
const SWEEP := 0.16
## How long the tail and sparks linger after the sweep finishes.
const FADE := 0.18
## How far behind the leading edge the tail reaches, as a fraction of the whole arc.
const TAIL := 0.55
const SEGMENTS := 24
## Chest height, where the blade travels.
const HEIGHT := 0.95
const INNER := 0.45
const SPARKS_PER_SECOND := 90.0
const SPARK_LIFE := 0.28

const COLOR_CORE := Color(1.0, 0.97, 0.85)
const COLOR_EDGE := Color(0.55, 0.8, 1.0)

static var _material: StandardMaterial3D
static var _spark_mesh: QuadMesh
static var _spark_material: StandardMaterial3D

var _ribbon := MeshInstance3D.new()
var _mesh := ImmediateMesh.new()
var _follow: Node3D
var _age: float = 0.0
var _reach: float = 3.0
var _half_arc: float = 1.1
var _spark_debt: float = 0.0
## Each: [MeshInstance3D, velocity, age].
var _sparks: Array[Array] = []


## `follow` keeps the crescent on the swinger if they move mid-swing. `delay` holds it back so
## the sweep lands with the animation's wind-up rather than on the button press.
func swing(follow: Node3D, aim: Vector3, reach: float, arc_degrees: float, delay: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_materials()
	_follow = follow
	_reach = reach
	_half_arc = deg_to_rad(arc_degrees)
	_age = -delay
	var flat := Vector3(aim.x, 0.0, aim.z)
	flat = flat.normalized() if flat.length_squared() > 0.001 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), follow.global_position)
	_ribbon.mesh = _mesh
	_ribbon.material_override = _material
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)


func _process(delta: float) -> void:
	_age += delta
	if _age >= SWEEP + FADE:
		queue_free()
		return
	if is_instance_valid(_follow):
		global_position = _follow.global_position
	_mesh.clear_surfaces()
	if _age < 0.0:
		return
	_draw_ribbon()
	_emit_sparks(delta)
	_move_sparks(delta)


## Angle across the arc for a 0..1 progress: starts on the swinger's left, ends on their right,
## to match the KayKit horizontal slice.
func _angle(progress: float) -> float:
	return lerpf(-_half_arc, _half_arc, progress)


## A point on the crescent in local space (forward is -Z, right is +X). The far edge dips a
## little so the sweep reads as a blade rather than a flat disc.
func _point(angle: float, radius: float) -> Vector3:
	return Vector3(sin(angle) * radius, HEIGHT - (radius - INNER) * 0.06, -cos(angle) * radius)


func _lead() -> float:
	## Fast out of the wind-up, easing as the blade finishes.
	return ease(clampf(_age / SWEEP, 0.0, 1.0), 0.45)


func _draw_ribbon() -> void:
	var lead := _lead()
	var tail := maxf(lead - TAIL, 0.0)
	## After the sweep the tail catches up with the head, so the crescent shrinks away.
	if _age > SWEEP:
		tail = lerpf(tail, lead, clampf((_age - SWEEP) / FADE, 0.0, 1.0))
	if lead - tail < 0.001:
		return
	var fade := 1.0 - clampf((_age - SWEEP) / FADE, 0.0, 1.0)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in SEGMENTS + 1:
		var along := float(index) / float(SEGMENTS)
		var angle := _angle(lerpf(tail, lead, along))
		## Brightest and widest at the leading edge, thinning to nothing at the tail.
		var strength := along * along * fade
		var inner := lerpf(_reach * 0.85, INNER, along)
		_mesh.surface_set_color(Color(COLOR_EDGE, strength * 0.5))
		_mesh.surface_add_vertex(_point(angle, inner))
		_mesh.surface_set_color(Color(COLOR_CORE.lerp(COLOR_EDGE, 1.0 - along), strength))
		_mesh.surface_add_vertex(_point(angle, _reach))
	_mesh.surface_end()


func _emit_sparks(delta: float) -> void:
	if _age > SWEEP:
		return
	_spark_debt += SPARKS_PER_SECOND * delta
	var angle := _angle(_lead())
	## Thrown along the direction the blade is travelling (towards the swinger's right) and out.
	var travel := Vector3(cos(angle), 0.0, sin(angle))
	var outward := Vector3(sin(angle), 0.0, -cos(angle))
	while _spark_debt >= 1.0:
		_spark_debt -= 1.0
		var spark := MeshInstance3D.new()
		spark.mesh = _spark_mesh
		spark.material_override = _spark_material
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.position = _point(angle, randf_range(INNER + 0.4, _reach))
		add_child(spark)
		var velocity := travel * randf_range(2.0, 5.0) + outward * randf_range(0.5, 2.5) \
				+ Vector3.UP * randf_range(-0.5, 1.5)
		_sparks.append([spark, velocity, 0.0])


func _move_sparks(delta: float) -> void:
	for index in range(_sparks.size() - 1, -1, -1):
		var entry := _sparks[index]
		var spark := entry[0] as MeshInstance3D
		var age := float(entry[2]) + delta
		if age >= SPARK_LIFE:
			spark.queue_free()
			_sparks.remove_at(index)
			continue
		entry[2] = age
		var velocity := (entry[1] as Vector3) * (1.0 - 3.0 * delta)
		entry[1] = velocity
		spark.position += velocity * delta
		spark.scale = Vector3.ONE * (1.0 - age / SPARK_LIFE)


static func _build_materials() -> void:
	if _material != null:
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.09, 0.09)
	_spark_material = StandardMaterial3D.new()
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_spark_material.albedo_color = COLOR_CORE
