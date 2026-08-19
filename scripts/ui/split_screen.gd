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

var panes: Array[SubViewportContainer] = []
var cameras: Array[PlayerCamera] = []
var huds: Array[PlayerHUD] = []

var _pids: Array[int] = []


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
		viewport.msaa_3d = Viewport.MSAA_2X
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


## Click-to-target. There is one mouse for up to four seats, so the click belongs to whichever
## pane the cursor is actually in -- which also makes it work unchanged in single-player.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	for index in panes.size():
		var pane := panes[index]
		if not Rect2(pane.position, pane.size).has_point(click.position):
			continue
		var player := PlayerRegistry.body_of(_pids[index]) as PlayerCharacter
		if player == null:
			continue
		player.targeting.pick_at(cameras[index].viewport_camera(), click.position - pane.position)
		return


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	panes.clear()
	cameras.clear()
	huds.clear()
