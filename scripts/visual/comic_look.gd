class_name ComicLook
extends Node

## Comic cel shading (comic.gdshaderinc) over everything in the world. `--no-comic` turns it off:
## then nothing here runs and no material is touched.

const SHADER := "res://scripts/visual/comic_cell.gdshader"

static var enabled := false

## The one at work, which keeps the converted materials (nothing static holds any).
static var _current: ComicLook
var _converted := {}
var _shaders := {}


static func start(main: Node) -> void:
	enabled = true
	_current = ComicLook.new()
	_current.name = "ComicLook"
	main.add_child(_current)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	enabled = false
	if _current == self:
		_current = null


func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D or node is CSGPrimitive3D:
		## Once whatever made it has finished giving it its materials.
		_consider.call_deferred(node.get_instance_id())


func _consider(id: int) -> void:
	var node := instance_from_id(id) as Node
	if node == null or not node.is_inside_tree():
		return
	if node is MeshInstance3D:
		apply(node as MeshInstance3D)
	elif node.get("material") is Material:
		node.set("material", convert_material(node.get("material")))


## Puts the comic version of each of a mesh's ordinary materials on it.
static func apply(mesh: MeshInstance3D) -> void:
	if not enabled or mesh.mesh == null:
		return
	if mesh.material_override != null:
		mesh.material_override = convert_material(mesh.material_override)
		return
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		var comic := convert_material(material)
		if comic != material:
			mesh.set_surface_override_material(surface, comic)


## The comic version of a material, or the material itself where it is not one to convert: glows
## (unshaded, but not the dragon, which is unshaded and textured), see-through things and anything with a shader of its own (see shader_for).
static func convert_material(material: Material) -> Material:
	var standard := material as BaseMaterial3D
	if not enabled or _current == null or standard == null \
			or standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or (standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and standard.albedo_texture == null):
		return material
	if _current._converted.has(standard):
		return _current._converted[standard]
	var comic := ShaderMaterial.new()
	comic.shader = load(SHADER)
	if standard.albedo_texture != null:
		comic.set_shader_parameter("albedo_texture", standard.albedo_texture)
	comic.set_shader_parameter("albedo_color", standard.albedo_color)
	comic.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
	comic.set_shader_parameter("uv_scale", Vector2(standard.uv1_scale.x, standard.uv1_scale.y))
	comic.set_shader_parameter("uv_offset", Vector2(standard.uv1_offset.x, standard.uv1_offset.y))
	if standard.emission_enabled and standard.emission_texture == null:
		comic.set_shader_parameter("emission_color", standard.emission * standard.emission_energy_multiplier)
	_current._converted[standard] = comic
	return comic


## The comic version of a shader of the game's own -- the same shader, lit by comic.gdshaderinc.
static func shader_for(shader: Shader) -> Shader:
	if not enabled or _current == null:
		return shader
	if not _current._shaders.has(shader):
		var comic := Shader.new()
		comic.code = shader.code.replace("diffuse_burley", "diffuse_lambert") \
				+ "\n#include \"res://scripts/visual/comic.gdshaderinc\"\n"
		_current._shaders[shader] = comic
	return _current._shaders[shader]
