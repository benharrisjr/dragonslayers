class_name MountainShrine
extends Node3D

## A dungeon's shrine on the mountain: one on each terrace, the well's at the bottom and the lake's
## just under the summit, beside the road up (Chunk._place_shrines). A stone obelisk with a crystal
## on top in the dungeon's own colour, dark until that dungeon's guardian has been beaten -- then the
## crystal lights and a beam of light stands over it, seen from all over the map.
##
## It keeps no state of its own. "Beaten" is the dungeon's big chest having been unlocked, which
## every peer is told about and a saved world remembers, so the shrines agree everywhere for free.

## Each dungeon's colour, by id.
const COLORS := {
	&"well": Color(0.45, 0.62, 0.95),
	&"fields": Color(0.55, 0.88, 0.35),
	&"desert": Color(1.0, 0.72, 0.3),
	&"plains": Color(0.92, 0.48, 0.32),
	&"forest": Color(0.2, 0.75, 0.42),
	&"temple_low": Color(0.72, 0.45, 0.95),
	&"temple_high": Color(0.88, 0.94, 1.0),
	&"lake": Color(0.3, 0.88, 0.88),
}
const STONE := Color(0.56, 0.54, 0.5)
## How tall the beam over a lit shrine stands, and how long it takes to light.
const BEAM_HEIGHT := 14.0
const LIGHT_UP := 1.6
## How often it looks at its dungeon, in seconds.
const CHECK_EVERY := 0.5
## Footprint and height of its collider.
const FOOTPRINT := 1.3
const HEIGHT := 3.2

var dungeon_id: StringName = &""
## 0 dark, 1 lit; eased between the two.
var glow: float = 0.0
var lit: bool = false

var _crystal: MeshInstance3D
var _label: Label3D
var _crystal_material: StandardMaterial3D
var _band_material: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_material: ShaderMaterial
var _checked := false
var _until_check := 0.0
var _time := 0.0


static func color_for(id: StringName) -> Color:
	return COLORS.get(id, Color(0.9, 0.9, 0.9))


func setup(id: StringName) -> void:
	dungeon_id = id
	name = "Shrine_%s" % id
	var accent := color_for(id)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.95

	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(FOOTPRINT, 0.35, FOOTPRINT)
	plinth_mesh.material = stone
	plinth.mesh = plinth_mesh
	plinth.position.y = 0.175
	add_child(plinth)

	## A four-sided obelisk, tapering, turned square to the plinth.
	var obelisk := MeshInstance3D.new()
	var obelisk_mesh := CylinderMesh.new()
	obelisk_mesh.radial_segments = 4
	obelisk_mesh.rings = 1
	obelisk_mesh.bottom_radius = 0.55
	obelisk_mesh.top_radius = 0.32
	obelisk_mesh.height = 2.2
	obelisk_mesh.material = stone
	obelisk.mesh = obelisk_mesh
	obelisk.position.y = 0.35 + 1.1
	obelisk.rotation.y = PI * 0.25
	add_child(obelisk)

	## A band of the dungeon's colour round it, dull until lit.
	_band_material = StandardMaterial3D.new()
	_band_material.albedo_color = accent.darkened(0.55)
	_band_material.emission_enabled = true
	_band_material.emission = accent
	_band_material.emission_energy_multiplier = 0.0
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.radial_segments = 4
	band_mesh.rings = 1
	band_mesh.bottom_radius = 0.5
	band_mesh.top_radius = 0.48
	band_mesh.height = 0.16
	band_mesh.material = _band_material
	band.mesh = band_mesh
	band.position.y = 0.35 + 0.55
	band.rotation.y = PI * 0.25
	add_child(band)

	## The crystal: an eight-sided gem floating over the top.
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.albedo_color = accent.darkened(0.6)
	_crystal_material.roughness = 0.2
	_crystal_material.metallic = 0.2
	_crystal_material.emission_enabled = true
	_crystal_material.emission = accent
	_crystal_material.emission_energy_multiplier = 0.0
	_crystal = MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radial_segments = 4
	gem.rings = 2
	gem.radius = 0.32
	gem.height = 0.9
	gem.material = _crystal_material
	_crystal.mesh = gem
	_crystal.position.y = HEIGHT - 0.2
	add_child(_crystal)

	## The beam: a tall, faint column of the dungeon's colour, there only once it is lit.
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = _beam_shader()
	_beam_material.set_shader_parameter("tint", Color(accent, 0.0))
	_beam = MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.radial_segments = 8
	column.rings = 1
	column.top_radius = 0.1
	column.bottom_radius = 0.2
	column.height = BEAM_HEIGHT
	column.cap_top = false
	column.cap_bottom = false
	column.material = _beam_material
	_beam.mesh = column
	_beam.position.y = HEIGHT + BEAM_HEIGHT * 0.5
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)

	## The dungeon's name on the obelisk's front, filled in once the dungeons are built.
	var label := Label3D.new()
	_label = label
	label.font_size = 40
	label.outline_size = 8
	label.pixel_size = 0.006
	label.modulate = Color(0.95, 0.92, 0.85)
	label.outline_modulate = Color(0.15, 0.13, 0.12)
	label.width = 380.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector3(0.0, 0.95, 0.45)
	label.double_sided = false
	add_child(label)

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Combatant.LAYER_SCENERY
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	## Rooted below the ground, like the props, so nothing is pushed down through it.
	box.size = Vector3(FOOTPRINT, HEIGHT + 1.0, FOOTPRINT)
	shape.shape = box
	shape.position.y = (HEIGHT - 1.0) * 0.5
	body.add_child(shape)
	add_child(body)


func _process(delta: float) -> void:
	_time += delta
	_until_check -= delta
	if _until_check <= 0.0:
		_until_check = CHECK_EVERY
		var now := is_beaten()
		if not _checked:
			## Already beaten when the world loaded: lit from the start, no fade.
			_checked = true
			glow = 1.0 if now else 0.0
		lit = now
	glow = move_toward(glow, 1.0 if lit else 0.0, delta / LIGHT_UP)
	_show(glow)


## Whether this shrine's dungeon has had its guardian beaten.
func is_beaten() -> bool:
	if not is_inside_tree():
		return false
	var dungeon := Dungeon.by_id(get_tree(), dungeon_id)
	if dungeon != null and _label.text == "":
		_label.text = dungeon.display_name
	return dungeon != null and dungeon.big_chest != null and not dungeon.big_chest.locked


func _show(amount: float) -> void:
	var accent := color_for(dungeon_id)
	_crystal_material.emission_energy_multiplier = amount * 1.4
	_crystal_material.albedo_color = accent.darkened(0.6).lerp(accent, amount)
	_band_material.emission_energy_multiplier = amount * 1.5
	_beam.visible = amount > 0.01
	_beam_material.set_shader_parameter("tint", Color(accent, 0.3 * amount))
	## A lit crystal turns slowly and bobs; a dark one sits still.
	_crystal.rotation.y = _time * 0.8 * amount
	_crystal.position.y = HEIGHT - 0.2 + sin(_time * 1.6) * 0.08 * amount


## The beam's look: added light, brightest at the crystal and gone by its top, and faded out as
## the camera comes close so it never washes over the view of someone standing beside it. A shader
## per shrine rather than a shared static one: nothing static may hold a rendering resource past
## shutdown.
static func _beam_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
varying float camera_distance;
void vertex() {
	camera_distance = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
	float rise = UV.y;
	float near = smoothstep(8.0, 26.0, camera_distance);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * rise * rise * near;
}
"""
	return shader
