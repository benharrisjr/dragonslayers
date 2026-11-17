extends Control

## The studio logo: "VGMRX" assembled from pixel blocks that fly in from the
## screen edges, hold, then spiral away before the main menu fades in. Any key,
## click or pad button skips it.

const LOGO_TEXT := "VGMRX"
const BLOCK_SIZE := 4
# The block animation was tuned to this font's letter shapes.
const LOGO_FONT: Font = preload("res://art/kenney_kenney-fonts 2/Fonts/Kenney Pixel.ttf")
const HOLD_DURATION := 1.0
const COLLAPSE_DURATION := 0.9

var _done := false


func _ready() -> void:
	add_to_group(PadCursor.BLOCK_GROUP)  # no pad cursor, hand or buttons over the logo
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Load the menu on a thread while the logo plays, so the swap doesn't hitch.
	ResourceLoader.load_threaded_request(ProjectConfig.MAIN_MENU_SCENE)
	await get_tree().process_frame
	await _build_and_animate()


func _input(event: InputEvent) -> void:
	var pressed := (event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton or event is InputEventScreenTouch) and event.is_pressed()
	if pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		_go_to_menu()


func _build_and_animate() -> void:
	var screen_size := get_viewport_rect().size

	# Render text to a SubViewport to discover which pixel blocks are part of the logo
	var vp := SubViewport.new()
	vp.size = Vector2i(int(screen_size.x), int(screen_size.y))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var label := Label.new()
	label.text = LOGO_TEXT
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Scale by raw viewport factor so the sampled letter shape is identical on all platforms.
	var vp_scale := minf(screen_size.x / FontSizes.BASE_WIDTH, screen_size.y / FontSizes.BASE_HEIGHT)
	var splash_size := int(round(FontSizes.SPLASH * clampf(vp_scale, FontSizes.MIN_SCALE, FontSizes.MAX_SCALE)))
	label.add_theme_font_override("font", LOGO_FONT)
	label.add_theme_font_size_override("font_size", splash_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	vp.add_child(label)

	# Wait enough frames for the viewport to render
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		# No renderer (headless runs): nothing to sample, go straight on.
		_go_to_menu()
		return

	# Collect final positions for all blocks that overlap logo pixels
	var final_positions: Array[Vector2] = []
	var cols := int(screen_size.x) / BLOCK_SIZE
	var row_count := int(screen_size.y) / BLOCK_SIZE

	# Sample 4 interior points per block (at 25% and 75% of each axis).
	# Using max-alpha across all 4 removes the asymmetry that arises when the
	# block grid doesn't align evenly with the antialiased letter edges.
	var q1 := BLOCK_SIZE / 4
	var q3 := BLOCK_SIZE * 3 / 4
	for row in range(row_count):
		for col in range(cols):
			var bx := col * BLOCK_SIZE
			var by := row * BLOCK_SIZE
			var max_a := 0.0
			for dy: int in [q1, q3]:
				for dx: int in [q1, q3]:
					var px: int = bx + dx
					var py: int = by + dy
					if px < img.get_width() and py < img.get_height():
						max_a = maxf(max_a, img.get_pixel(px, py).a)
			if max_a > 0.5:
				final_positions.append(Vector2(bx, by))

	if final_positions.is_empty():
		# Fallback: skip straight to the menu if sampling failed
		_go_to_menu()
		return

	# Create pixel canvas
	var canvas := SplashPixelCanvas.new()
	add_child(canvas)

	for final_pos in final_positions:
		canvas.blocks.append({
			"start":    _random_edge_pos(screen_size),
			"final":    final_pos,
			"delay":    randf() * canvas.STAGGER,
			"duration": canvas.BASE_DURATION * (0.7 + randf() * 0.6),
			"size":     BLOCK_SIZE,
		})

	canvas.start()
	await canvas.done
	if _done:
		return

	await get_tree().create_timer(HOLD_DURATION).timeout
	if _done:
		return
	canvas.collapse(screen_size * 0.5, COLLAPSE_DURATION)
	await canvas.collapsed
	_go_to_menu()


func _random_edge_pos(screen_size: Vector2) -> Vector2:
	var edge := randi() % 4
	match edge:
		0: # top
			return Vector2(randf() * screen_size.x, -BLOCK_SIZE - randf() * 80.0)
		1: # right
			return Vector2(screen_size.x + randf() * 80.0, randf() * screen_size.y)
		2: # bottom
			return Vector2(randf() * screen_size.x, screen_size.y + randf() * 80.0)
		_: # left
			return Vector2(-BLOCK_SIZE - randf() * 80.0, randf() * screen_size.y)
	return Vector2.ZERO


func _go_to_menu() -> void:
	if _done:
		return
	_done = true
	SceneManager.change_scene(ProjectConfig.MAIN_MENU_SCENE)
