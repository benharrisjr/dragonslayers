extends Node

signal scene_changed

var _current_scene: Node
# Node-typed so the SceneTree-root fallback (a Window) is assignable.
var _root: Node
var _canvas_layer: CanvasLayer
var _fade_rect: ColorRect
var _transitioning: bool = false


func _ready() -> void:
	call_deferred("_setup")


## Locate the host node we should parent loaded scenes under. Tries, in order:
## 1. an explicit child named "Control" (legacy main.tscn layout),
## 2. the highest-indexed Control child of the SceneTree root (the main scene,
##    since autoloads register before main and use plain Node by convention),
## 3. the SceneTree root itself as a last resort so add_child can't no-op.
func _resolve_root() -> void:
	var tree_root := get_tree().root
	var named := tree_root.get_node_or_null("Control")
	if named:
		_root = named
		return
	for i in range(tree_root.get_child_count() - 1, -1, -1):
		var c := tree_root.get_child(i)
		if c is Control:
			_root = c
			return
	_root = tree_root


func _setup() -> void:
	_resolve_root()
	if _root and _root.get_child_count() > 0:
		_current_scene = _root.get_child(0)

	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	get_tree().root.add_child(_canvas_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_canvas_layer.add_child(_fade_rect)


## True from a change_scene() call until its fade back in has finished.
func is_transitioning() -> bool:
	return _transitioning


func get_scene_root() -> Node:
	if _root == null:
		_resolve_root()
	return _root


## `fade = false` swaps instantly  for screens that
## share the persistent backdrop, so the switch reads as one continuous scene.
func change_scene(scene_path: String, fade: bool = true) -> void:
	if _transitioning:
		return
	_transitioning = true

	if fade and _fade_rect:
		var tween_out := create_tween()
		tween_out.tween_property(_fade_rect, "modulate:a", 1.0, 0.2)
		await tween_out.finished

	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null

	var packed := load(scene_path) as PackedScene
	if not packed:
		push_error("Failed to load scene: " + scene_path)
		_transitioning = false
		return

	_current_scene = packed.instantiate()
	if _root == null:
		_resolve_root()
	_root.add_child(_current_scene)
	scene_changed.emit()

	if fade and _fade_rect:
		var tween_in := create_tween()
		tween_in.tween_property(_fade_rect, "modulate:a", 0.0, 0.2)
		await tween_in.finished

	_transitioning = false
