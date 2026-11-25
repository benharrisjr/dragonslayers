class_name HeroPreview
extends SubViewportContainer

## A hero standing on a character-select card, passing the time.
##
## Each card renders its own little world: one character, a camera, a key light. The hero
## drifts between a handful of idle pastimes -- standing about, push-ups, sit-ups, a wave, a
## cheer -- so four cards side by side never move in step. Confirming a pick cheers on the spot.

## What a hero gets up to while waiting. Weighted towards standing: someone choosing should be
## able to see the hero, not the top of their head mid push-up.
const PASTIMES: Array[String] = [
	"general/Idle_A", "general/Idle_A", "general/Idle_B", "general/Idle_B",
	"sim/Cheering", "sim/Push_Ups", "sim/Sit_Ups", "sim/Waving",
]
const CHEER := "sim/Cheering"
## How long one pastime lasts before the next, at random within this range.
const PASTIME_TIME := Vector2(3.2, 6.0)

var hero_id: StringName = &""

var _viewport: SubViewport
var _stage: Node3D
var _visual: CharacterVisual
var _clip: String = ""
var _clip_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init(side: Vector2 = Vector2(260, 250)) -> void:
	custom_minimum_size = side
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.fov = 30.0
	## Set as a transform rather than with look_at, which needs the node in the tree already.
	var eye := Vector3(0.0, 1.0, 3.9)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.82, 0.0) - eye), eye)
	_viewport.add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -150.0, 0.0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.7, 0.8, 1.0)
	_viewport.add_child(fill)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.7
	environment.adjustment_enabled = true
	environment.adjustment_saturation = GameWorld.SATURATION
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	## A soft dark disc to stand on, so a hero lying down for sit-ups is on something.
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 0.9
	floor_mesh.bottom_radius = 0.9
	floor_mesh.height = 0.02
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.0, 0.0, 0.0, 0.35)
	floor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material = floor_material
	var disc := MeshInstance3D.new()
	disc.mesh = floor_mesh
	_viewport.add_child(disc)

	_stage = Node3D.new()
	## Turned a little towards the light, so the face and the weapon both read.
	_stage.rotation_degrees.y = 18.0
	_viewport.add_child(_stage)


## Puts `id` on the card, starting on a random pastime. Showing the hero already there does
## nothing, so a refresh does not restart the animation.
func show_hero(id: StringName) -> void:
	if id == hero_id and _visual != null:
		return
	hero_id = id
	if _visual != null:
		_visual.queue_free()
		_visual = null
	var archetype := ArchetypeDB.get_archetype(id)
	if archetype == null:
		return
	_visual = CharacterVisual.new()
	_stage.add_child(_visual)
	_visual.build(archetype.model_path, archetype.weapon_paths)
	_clip = ""
	_next_pastime()


## A cheer, then back to passing the time.
func cheer() -> void:
	_set_clip(CHEER)
	_clip_left = 2.6


func current_clip() -> String:
	return _clip


func _process(delta: float) -> void:
	if _visual == null or not is_visible_in_tree():
		return
	_clip_left -= delta
	if _clip_left <= 0.0:
		_next_pastime()


func _next_pastime() -> void:
	var next := _clip
	while next == _clip:
		next = PASTIMES[_rng.randi_range(0, PASTIMES.size() - 1)]
	_set_clip(next)
	_clip_left = _rng.randf_range(PASTIME_TIME.x, PASTIME_TIME.y)


func _set_clip(clip: String) -> void:
	_clip = clip
	if _visual != null:
		_visual.set_loop(clip)
