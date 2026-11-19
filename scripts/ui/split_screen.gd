class_name SplitScreen
extends Control

## Lays out one pane per local player and wires each to its own camera and HUD.
##
## All panes share a single World3D -- they are SubViewports inheriting the main window's world,
## not separate scenes -- so four players walking around one 256 m map costs one simulation and
## four camera renders rather than four of everything.
##
## Only *local* players get a pane. Remote players exist in the world and are drawn by whichever
## pane can see them, which is the whole distinction between a peer and a split-screen slot.

const MIN_PANE_SIZE := Vector2(160, 120)
## The HUD was drawn for a 1280x720 canvas; the project canvas is 1920x1080, so each pane lays
## its 2D overlay out at 1/1.5 size and stretches it back up. 3D rendering is unaffected.
const HUD_SCALE := 1.5

var panes: Array[SubViewportContainer] = []
var cameras: Array[PlayerCamera] = []
var huds: Array[PlayerHUD] = []

var _pids: Array[int] = []
## Which pane, if any, is currently being dragged with the right mouse button. There is one
## mouse for up to four seats, so the drag belongs to whichever pane it started in and stays
## there until the button comes up -- otherwise sweeping the cursor across a split would hand
## the camera to somebody else's player mid-turn.
var _look_pane: int = -1


func build(pids: Array[int]) -> void:
	_clear()
	_pids = pids
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	for index in pids.size():
		var pid := pids[index]
		var player := PlayerRegistry.body_of(pid) as PlayerCharacter
		if player == null:
			continue

		var container := SubViewportContainer.new()
		container.name = "Pane_%d" % pid
		container.stretch = true
		container.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(container)

		var viewport := SubViewport.new()
		viewport.handle_input_locally = false
		## own_world_3d stays false so this viewport renders the window's shared World3D rather
		## than an empty one of its own.
		viewport.own_world_3d = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		## Each pane is its own viewport, so the project's MSAA setting does not reach it. 4x
		## smooths the terrain's cliff edges and the props' silhouettes; the low tier keeps 2x.
		## (FXAA and TAA are not available in the Compatibility renderer.)
		viewport.msaa_3d = Viewport.MSAA_2X if GraphicsQuality.is_low() else Viewport.MSAA_4X
		container.add_child(viewport)

		var camera := PlayerCamera.new()
		camera.name = "Camera"
		viewport.add_child(camera)
		camera.setup(player, PlayerRegistry.slot_of(pid))

		var hud := PlayerHUD.new()
		hud.name = "HUD"
		viewport.add_child(hud)
		hud.setup(player)

		panes.append(container)
		cameras.append(camera)
		huds.append(hud)

	## Deferred because this runs during world build, before the first layout pass has given
	## this control a rect -- laying out against a zero-size parent collapses every pane to its
	## minimum size in the corner of the window.
	_layout.call_deferred()
	get_viewport().size_changed.connect(_layout)


## 1 = full screen, 2 = stacked, 3-4 = quad with the fourth cell left empty for three players.
## Stacked rather than side-by-side for two, because a wide short pane shows more of the terrain
## ahead than a tall narrow one -- and seeing the ledge ahead of you is the point.
func _layout() -> void:
	## Measured from the viewport, not from `size`: this control's parent is a plain Node, which
	## gives it no rect of its own to anchor against.
	var full := get_viewport_rect().size
	set_deferred("size", full)
	var count := panes.size()
	if count == 0:
		return
	for index in count:
		var pane := panes[index]
		var rect: Rect2
		match count:
			1:
				rect = Rect2(Vector2.ZERO, full)
			2:
				rect = Rect2(Vector2(0, index * full.y * 0.5), Vector2(full.x, full.y * 0.5))
			_:
				var column := index % 2
				var row := index / 2
				rect = Rect2(Vector2(column * full.x * 0.5, row * full.y * 0.5), full * 0.5)
		pane.position = rect.position
		## With stretch enabled the container drives its SubViewport's size, so setting it here
		## as well is both redundant and a warning every time the window changes.
		pane.size = rect.size.max(MIN_PANE_SIZE)
		var viewport := pane.get_child(0) as SubViewport
		if viewport != null:
			viewport.size_2d_override = Vector2i(pane.size / HUD_SCALE)
			viewport.size_2d_override_stretch = true


## Click-to-target. There is one mouse for up to four seats, so the click belongs to whichever
## pane the cursor is actually in -- which also makes it work unchanged in single-player.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var index := _pane_at(click.position)
	if index < 0:
		return

	if click.button_index == MOUSE_BUTTON_LEFT:
		var player := PlayerRegistry.body_of(_pids[index]) as PlayerCharacter
		if player != null:
			player.targeting.pick_at(cameras[index].viewport_camera(),
					click.position - panes[index].position)
		return

	## Space + right-button drag turns the camera freely -- the mouse equivalent of holding Q or
	## E. Without Space the right button is the equipped usable, which the player reads as an
	## action. Started here rather than in _input so that Godot's own hit-testing decides which
	## pane the drag belongs to, in this control's coordinates, instead of rect maths against
	## raw screen positions that still carry the viewport's transform.
	if click.button_index == MOUSE_BUTTON_RIGHT and Input.is_physical_key_pressed(KEY_SPACE):
		begin_look(index)
		accept_event()


## The drag itself lives in _input because the pointer is captured for its duration: with the
## cursor hidden and locked there are no more GUI positions to route by, and capturing is what
## stops a long turn running out of screen and stalling half way round.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed:
		if is_looking():
			end_look()
			get_viewport().set_input_as_handled()
		return

	if not is_looking():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		cameras[_look_pane].apply_mouse_look(motion.relative)
		get_viewport().set_input_as_handled()


## Hands the pointer to one pane's camera until end_look(). There is one mouse for up to four
## seats, so the drag stays with the pane it started in -- otherwise sweeping the cursor across a
## split would hand the camera to somebody else's player mid-turn.
func begin_look(pane_index: int) -> void:
	if pane_index < 0 or pane_index >= cameras.size():
		return
	_look_pane = pane_index
	PlayerInput.mouse_looking = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func end_look() -> void:
	_look_pane = -1
	PlayerInput.mouse_looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_looking() -> bool:
	return _look_pane >= 0 and _look_pane < cameras.size()


## Whichever pane contains a point in this control's coordinates, or -1.
func _pane_at(position: Vector2) -> int:
	for index in panes.size():
		if Rect2(panes[index].position, panes[index].size).has_point(position):
			return index
	return -1


func _clear() -> void:
	## Never leave the pointer captured behind a rebuilt screen -- the player would be left with
	## no cursor and no way to get it back.
	if _look_pane >= 0:
		_look_pane = -1
		PlayerInput.mouse_looking = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child in get_children():
		child.queue_free()
	panes.clear()
	cameras.clear()
	huds.clear()
