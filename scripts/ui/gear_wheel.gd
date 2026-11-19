class_name GearWheel
extends Control

## One player's quick-pick wheel for usable equipment.
##
## Holding the left trigger and pushing the right stick brings it up in that player's own pane.
## Every usable has a fixed slice -- the hookshot is always at the top -- so a choice becomes a
## flick that the thumb remembers. The stick points at a slice; letting it spring back equips
## what it pointed at as it was let go, a tenth of a second after it comes to rest. There is no
## confirm button. Without the trigger the right stick is the camera, as ever, and the left
## stick walks throughout.
##
## This is only the picture. The player reads the stick and the buttons itself, in its physics
## step with the rest of its controls, and says here what to show.

const GOLD := Color(1.0, 0.9, 0.6)
## Where the ring's inner edge is, as a share of its radius.
const INNER := 0.46
## The gap left between neighbouring slices, in radians.
const GAP := 0.035

var player: PlayerCharacter

var _icons: Dictionary = {}
var _name: Label
var _state: Label
var _detail: Label
var _hint: Label


## Which of `count` slices a direction on the screen (y down) points at. Slice 0 is centred
## straight up and the rest follow clockwise.
static func slice_at(direction: Vector2, count: int) -> int:
	if count <= 0:
		return -1
	return posmod(roundi((direction.angle() + PI * 0.5) / (TAU / count)), count)


## The screen direction of the middle of a slice.
static func slice_direction(index: int, count: int) -> Vector2:
	return Vector2.from_angle(-PI * 0.5 + index * TAU / maxi(count, 1))


func setup(target_player: PlayerCharacter) -> void:
	player = target_player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for id in ItemDB.USABLE:
		var icon := ItemIcon.new(id, 44.0)
		add_child(icon)
		_icons[id] = icon
	_name = _label(15, Color.WHITE)
	_state = _label(12, GOLD)
	_detail = _label(15, Color(0.9, 0.93, 0.9))
	_hint = _label(12, Color(0.65, 0.7, 0.7))
	player.wheel_toggled.connect(_on_toggled)
	player.wheel_changed.connect(_refresh)
	player.gear_changed.connect(_refresh)
	SaveManager.keybinds_changed.connect(_refresh)
	resized.connect(_refresh)
	_refresh()


func radius() -> float:
	return clampf(minf(size.x, size.y) * 0.27, 84.0, 170.0)


func _on_toggled(open: bool) -> void:
	visible = open
	_refresh()


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _refresh() -> void:
	if player == null or _name == null:
		return
	var centre := size * 0.5
	var ring := radius()
	var count := ItemDB.USABLE.size()
	var icon_side := clampf(ring * 0.3, 30.0, 48.0)
	for index in count:
		var id: StringName = ItemDB.USABLE[index]
		var icon: ItemIcon = _icons[id]
		icon.dimmed = not player.has_item(id)
		icon.custom_minimum_size = Vector2(icon_side, icon_side)
		icon.size = Vector2(icon_side, icon_side)
		icon.position = centre + slice_direction(index, count) * ring * (1.0 + INNER) * 0.5 \
				- icon.size * 0.5

	var id := player.wheel_choice
	var held := player.has_item(id)
	var slot := player.slot()
	_name.text = ItemDB.display_name(id) if id != &"" else ""
	_name.modulate = Color.WHITE if held else Color(1, 1, 1, 0.5)
	if not held:
		_state.text = "not found"
	elif player.equipped() == id:
		_state.text = "equipped"
	else:
		_state.text = ""
	_place(_name, centre + Vector2(0, -9), ring * INNER * 1.9)
	_place(_state, centre + Vector2(0, 10), ring * INNER * 1.9)

	if id == &"":
		_detail.text = ""
	elif held:
		_detail.text = ItemDB.description(id)
	else:
		_detail.text = "Not found yet. Look in the large chests, or ask at the bug shop."
	var on_pad := PlayerBindings.on_pad(slot)
	var button := PlayerBindings.hotkey_label(slot, ItemDB.SLOT_USABLE)
	if on_pad:
		_hint.text = "Point the right stick, let go to equip on %s" % button
	else:
		_hint.text = "Q / E: choose    let go of %s: equip on %s" % [
				PlayerBindings.wheel_label(slot), button]
	_place(_detail, centre + Vector2(0, ring + 22), size.x - 24.0)
	_place(_hint, centre + Vector2(0, ring + 46), size.x - 24.0)
	queue_redraw()


func _place(label: Label, middle: Vector2, width: float) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.size = Vector2(maxf(width, 10.0), 22.0)
	label.position = middle - label.size * 0.5


func _draw() -> void:
	if player == null:
		return
	var centre := size * 0.5
	var ring := radius()
	var count := ItemDB.USABLE.size()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.07, 0.42))
	draw_circle(centre, ring * INNER - 5.0, Color(0.06, 0.08, 0.11, 0.9))
	var half := PI / count - GAP
	for index in count:
		var id: StringName = ItemDB.USABLE[index]
		var middle := slice_direction(index, count).angle()
		var chosen := id == player.wheel_choice
		var held := player.has_item(id)
		var fill := Color(0.1, 0.12, 0.16, 0.92)
		if held and player.equipped() == id:
			fill = Color(0.17, 0.26, 0.15, 0.95)
		elif not held:
			fill = Color(0.07, 0.08, 0.1, 0.85)
		if chosen:
			fill = fill.lightened(0.14)
		## The chosen slice stands a little proud of the ring.
		var outer := ring * (1.07 if chosen else 1.0)
		var shape := _slice(centre, ring * INNER, outer, middle - half, middle + half)
		draw_colored_polygon(shape, fill)
		shape.append(shape[0])
		draw_polyline(shape, GOLD if chosen else Color(0.35, 0.38, 0.45), 3.0 if chosen else 1.0,
				true)
		if chosen:
			## A pointer from the hub, so the choice reads even at a glance.
			var along := Vector2.from_angle(middle)
			var side := along.orthogonal() * 7.0
			var base := centre + along * (ring * INNER - 12.0)
			draw_colored_polygon(PackedVector2Array([base + side, base - side,
					centre + along * (ring * INNER + 2.0)]), GOLD)


func _slice(centre: Vector2, inner: float, outer: float, from: float, to: float) \
		-> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 12
	for step in steps + 1:
		points.append(centre + Vector2.from_angle(lerpf(from, to, float(step) / steps)) * outer)
	for step in steps + 1:
		points.append(centre + Vector2.from_angle(lerpf(to, from, float(step) / steps)) * inner)
	return points
