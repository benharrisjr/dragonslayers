class_name ItemIcon
extends Control

## A drawn icon for one piece of gear.
##
## The art kits have 3D models but no flat pictures of a feather, a hookshot or a lantern, so
## these are drawn here from a few polygons each -- which also keeps them sharp at whatever size
## a split-screen pane ends up being. Shapes are laid out on a 0..1 square and scaled to fit.

const OUTLINE := Color(0.05, 0.06, 0.08)

## The item to draw; &"" draws nothing (an empty slot).
var item_id: StringName = &"":
	set(value):
		item_id = value
		queue_redraw()

## Greys the icon out: an item not found yet, or one that is cooling down.
var dimmed: bool = false:
	set(value):
		dimmed = value
		queue_redraw()


func _init(id: StringName = &"", side: float = 40.0) -> void:
	item_id = id
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if item_id == &"":
		return
	var main := ItemDB.color(item_id)
	match item_id:
		ItemDB.BOMB:
			## A round black bomb with a cap and a lit fuse.
			_shape(_circle(Vector2(0.46, 0.6), 0.32), Color(0.16, 0.16, 0.2))
			_shape([Vector2(0.52, 0.22), Vector2(0.68, 0.24), Vector2(0.66, 0.36), Vector2(0.5, 0.34)],
					Color(0.6, 0.56, 0.5))
			_shape([Vector2(0.62, 0.22), Vector2(0.74, 0.08), Vector2(0.78, 0.11), Vector2(0.66, 0.25)],
					Color(0.85, 0.75, 0.55), false)
			_shape(_circle(Vector2(0.78, 0.09), 0.07), main, false)
			_shape(_circle(Vector2(0.36, 0.5), 0.07), Color(0.45, 0.45, 0.55), false)
		ItemDB.FLIPPERS:
			## Two flippers side by side, toes up: a heel strap and a broad, notched paddle.
			for left in [0.1, 0.52]:
				_shape([Vector2(left + 0.08, 0.92), Vector2(left + 0.3, 0.92), Vector2(left + 0.36, 0.3),
						Vector2(left + 0.38, 0.08), Vector2(left + 0.19, 0.16), Vector2(left, 0.08),
						Vector2(left + 0.02, 0.3)], main)
				_shape([Vector2(left + 0.08, 0.7), Vector2(left + 0.3, 0.7), Vector2(left + 0.3, 0.8),
						Vector2(left + 0.08, 0.8)], main.darkened(0.4), false)
		ItemDB.RAFT:
			## Four logs side by side, lashed with two cords.
			for index in 4:
				var left := 0.14 + index * 0.18
				_shape([Vector2(left, 0.12), Vector2(left + 0.16, 0.12), Vector2(left + 0.16, 0.88),
						Vector2(left, 0.88)], main if index % 2 == 0 else main.darkened(0.15))
			for cord in [0.28, 0.72]:
				_shape([Vector2(0.1, cord - 0.03), Vector2(0.9, cord - 0.03), Vector2(0.9, cord + 0.03),
						Vector2(0.1, cord + 0.03)], Color(0.85, 0.78, 0.55), false)
		ItemDB.ARMOR:
			## A breastplate with shoulder guards.
			_shape([Vector2(0.22, 0.2), Vector2(0.78, 0.2), Vector2(0.72, 0.6), Vector2(0.62, 0.88),
					Vector2(0.38, 0.88), Vector2(0.28, 0.6)], main)
			_shape([Vector2(0.08, 0.18), Vector2(0.3, 0.12), Vector2(0.32, 0.34), Vector2(0.12, 0.4)],
					Color(0.78, 0.8, 0.86))
			_shape([Vector2(0.92, 0.18), Vector2(0.7, 0.12), Vector2(0.68, 0.34), Vector2(0.88, 0.4)],
					Color(0.78, 0.8, 0.86))
			_shape([Vector2(0.47, 0.26), Vector2(0.53, 0.26), Vector2(0.53, 0.8), Vector2(0.47, 0.8)],
					main.lightened(0.35), false)
		ItemDB.BOOMERANG:
			## A bent stick, the elbow at the top left.
			_shape([Vector2(0.14, 0.2), Vector2(0.3, 0.1), Vector2(0.9, 0.62), Vector2(0.8, 0.74),
					Vector2(0.32, 0.36)], main)
			_shape([Vector2(0.14, 0.2), Vector2(0.32, 0.36), Vector2(0.3, 0.9), Vector2(0.16, 0.86)],
					main.darkened(0.15))
		ItemDB.AXE:
			## Long haft corner to corner, a broad blade at the top.
			_shape([Vector2(0.14, 0.92), Vector2(0.08, 0.86), Vector2(0.66, 0.28), Vector2(0.72, 0.34)],
					Color(0.5, 0.33, 0.2))
			_shape([Vector2(0.5, 0.2), Vector2(0.66, 0.04), Vector2(0.96, 0.34), Vector2(0.8, 0.5),
					Vector2(0.7, 0.4), Vector2(0.6, 0.3)], main)
		ItemDB.DAGGER:
			_shape([Vector2(0.84, 0.1), Vector2(0.9, 0.16), Vector2(0.5, 0.6), Vector2(0.4, 0.5)], main)
			_shape([Vector2(0.3, 0.5), Vector2(0.38, 0.44), Vector2(0.56, 0.62), Vector2(0.5, 0.7)],
					Color(0.85, 0.7, 0.3))
			_shape([Vector2(0.36, 0.6), Vector2(0.42, 0.66), Vector2(0.22, 0.86), Vector2(0.16, 0.8)],
					Color(0.35, 0.25, 0.2))
		ItemDB.STAFF:
			_shape([Vector2(0.12, 0.94), Vector2(0.06, 0.88), Vector2(0.62, 0.32), Vector2(0.68, 0.38)],
					Color(0.5, 0.36, 0.24))
			_shape([Vector2(0.78, 0.06), Vector2(0.94, 0.22), Vector2(0.78, 0.38), Vector2(0.62, 0.22)],
					main)
			_shape([Vector2(0.78, 0.14), Vector2(0.86, 0.22), Vector2(0.78, 0.3), Vector2(0.7, 0.22)],
					Color(0.92, 0.9, 1.0), false)
		ItemDB.BOW:
			## The limb as a fat crescent, the string as a thin bar across it.
			var limb: Array = []
			for step in 9:
				var angle := lerpf(-1.25, 1.25, step / 8.0)
				limb.append(Vector2(0.18, 0.5) + Vector2(cos(angle), sin(angle)) * 0.44)
			for step in 9:
				var angle := lerpf(1.25, -1.25, step / 8.0)
				limb.append(Vector2(0.18, 0.5) + Vector2(cos(angle), sin(angle)) * 0.34)
			_shape(limb, main)
			_shape([Vector2(0.3, 0.08), Vector2(0.34, 0.08), Vector2(0.34, 0.92), Vector2(0.3, 0.92)],
					Color(0.92, 0.9, 0.82), false)
		ItemDB.SWORD:
			_shape([Vector2(0.78, 0.08), Vector2(0.9, 0.2), Vector2(0.42, 0.68), Vector2(0.3, 0.56)], main)
			_shape([Vector2(0.2, 0.5), Vector2(0.3, 0.42), Vector2(0.56, 0.7), Vector2(0.48, 0.8)],
					Color(0.85, 0.7, 0.3))
			_shape([Vector2(0.24, 0.66), Vector2(0.34, 0.76), Vector2(0.16, 0.92), Vector2(0.08, 0.84)],
					Color(0.5, 0.33, 0.2))
		ItemDB.SHIELD:
			_shape([Vector2(0.14, 0.12), Vector2(0.86, 0.12), Vector2(0.86, 0.5), Vector2(0.5, 0.92),
					Vector2(0.14, 0.5)], main)
			_shape([Vector2(0.44, 0.2), Vector2(0.56, 0.2), Vector2(0.56, 0.74), Vector2(0.5, 0.8),
					Vector2(0.44, 0.74)], Color(0.92, 0.94, 1.0), false)
			_shape([Vector2(0.24, 0.36), Vector2(0.76, 0.36), Vector2(0.76, 0.48), Vector2(0.24, 0.48)],
					Color(0.92, 0.94, 1.0), false)
		ItemDB.HOOKSHOT:
			_shape([Vector2(0.1, 0.82), Vector2(0.18, 0.9), Vector2(0.56, 0.52), Vector2(0.48, 0.44)],
					Color(0.4, 0.36, 0.33))
			_shape([Vector2(0.9, 0.1), Vector2(0.72, 0.56), Vector2(0.44, 0.28)], main)
			_shape([Vector2(0.04, 0.78), Vector2(0.22, 0.96), Vector2(0.12, 1.0), Vector2(0.0, 0.88)],
					Color(0.55, 0.4, 0.25))
		ItemDB.LANTERN:
			_shape([Vector2(0.4, 0.04), Vector2(0.6, 0.04), Vector2(0.6, 0.16), Vector2(0.4, 0.16)],
					Color(0.35, 0.33, 0.32))
			_shape([Vector2(0.24, 0.16), Vector2(0.76, 0.16), Vector2(0.7, 0.3), Vector2(0.3, 0.3)],
					Color(0.35, 0.33, 0.32))
			_shape([Vector2(0.28, 0.3), Vector2(0.72, 0.3), Vector2(0.72, 0.8), Vector2(0.28, 0.8)],
					Color(1.0, 0.93, 0.6))
			_shape([Vector2(0.5, 0.38), Vector2(0.62, 0.58), Vector2(0.56, 0.72), Vector2(0.44, 0.72),
					Vector2(0.38, 0.58)], Color(1.0, 0.5, 0.15), false)
			_shape([Vector2(0.2, 0.8), Vector2(0.8, 0.8), Vector2(0.8, 0.94), Vector2(0.2, 0.94)],
					Color(0.35, 0.33, 0.32))
		ItemDB.FEATHER:
			_shape([Vector2(0.84, 0.08), Vector2(0.9, 0.34), Vector2(0.62, 0.72), Vector2(0.3, 0.8),
					Vector2(0.34, 0.5), Vector2(0.58, 0.2)], main)
			_shape([Vector2(0.8, 0.14), Vector2(0.84, 0.18), Vector2(0.14, 0.94), Vector2(0.08, 0.9)],
					Color(0.5, 0.45, 0.4), false)
		ItemDB.BOOTS:
			_shape([Vector2(0.28, 0.08), Vector2(0.58, 0.08), Vector2(0.58, 0.56), Vector2(0.9, 0.68),
					Vector2(0.9, 0.84), Vector2(0.28, 0.84)], main)
			_shape([Vector2(0.24, 0.84), Vector2(0.94, 0.84), Vector2(0.94, 0.94), Vector2(0.24, 0.94)],
					Color(0.3, 0.2, 0.14))
			_shape([Vector2(0.28, 0.08), Vector2(0.58, 0.08), Vector2(0.58, 0.2), Vector2(0.28, 0.2)],
					Color(0.95, 0.9, 0.75), false)
		ItemDB.GLOVE:
			_shape([Vector2(0.24, 0.3), Vector2(0.3, 0.1), Vector2(0.42, 0.1), Vector2(0.44, 0.24),
					Vector2(0.48, 0.06), Vector2(0.6, 0.06), Vector2(0.6, 0.24), Vector2(0.66, 0.12),
					Vector2(0.76, 0.14), Vector2(0.74, 0.44), Vector2(0.9, 0.36), Vector2(0.94, 0.48),
					Vector2(0.72, 0.7), Vector2(0.28, 0.7)], main)
			_shape([Vector2(0.24, 0.7), Vector2(0.76, 0.7), Vector2(0.76, 0.92), Vector2(0.24, 0.92)],
					Color(0.95, 0.85, 0.4))
		ItemDB.NET:
			_shape([Vector2(0.08, 0.86), Vector2(0.14, 0.92), Vector2(0.5, 0.56), Vector2(0.44, 0.5)],
					Color(0.5, 0.36, 0.22))
			_shape([Vector2(0.48, 0.14), Vector2(0.7, 0.06), Vector2(0.9, 0.16), Vector2(0.94, 0.4),
					Vector2(0.82, 0.6), Vector2(0.6, 0.62), Vector2(0.44, 0.46), Vector2(0.4, 0.28)],
					main)
			_shape([Vector2(0.54, 0.22), Vector2(0.7, 0.16), Vector2(0.82, 0.24), Vector2(0.84, 0.4),
					Vector2(0.76, 0.5), Vector2(0.62, 0.5), Vector2(0.52, 0.4)],
					Color(0.9, 0.97, 0.9), false)
		ItemDB.FAN:
			_shape([Vector2(0.5, 0.9), Vector2(0.04, 0.4), Vector2(0.2, 0.2), Vector2(0.5, 0.1),
					Vector2(0.8, 0.2), Vector2(0.96, 0.4)], main)
			for rib in [Vector2(0.14, 0.34), Vector2(0.34, 0.16), Vector2(0.66, 0.16), Vector2(0.86, 0.34)]:
				draw_line(Vector2(0.5, 0.9) * size, rib * size, OUTLINE, maxf(1.0, size.x * 0.03))
			_shape([Vector2(0.44, 0.84), Vector2(0.56, 0.84), Vector2(0.56, 0.96), Vector2(0.44, 0.96)],
					Color(0.4, 0.3, 0.25))
		ItemDB.HEART:
			_shape([Vector2(0.5, 0.9), Vector2(0.1, 0.48), Vector2(0.08, 0.28), Vector2(0.2, 0.14),
					Vector2(0.36, 0.14), Vector2(0.5, 0.28), Vector2(0.64, 0.14), Vector2(0.8, 0.14),
					Vector2(0.92, 0.28), Vector2(0.9, 0.48)], main)
			_shape([Vector2(0.2, 0.26), Vector2(0.3, 0.2), Vector2(0.36, 0.28), Vector2(0.26, 0.36)],
					Color(1.0, 0.8, 0.82), false)
		ItemDB.MIRROR:
			_shape([Vector2(0.44, 0.62), Vector2(0.56, 0.62), Vector2(0.56, 0.96), Vector2(0.44, 0.96)],
					Color(0.85, 0.7, 0.3))
			_shape([Vector2(0.5, 0.04), Vector2(0.72, 0.1), Vector2(0.84, 0.28), Vector2(0.84, 0.44),
					Vector2(0.72, 0.62), Vector2(0.5, 0.68), Vector2(0.28, 0.62), Vector2(0.16, 0.44),
					Vector2(0.16, 0.28), Vector2(0.28, 0.1)], Color(0.85, 0.7, 0.3))
			_shape([Vector2(0.5, 0.14), Vector2(0.66, 0.18), Vector2(0.74, 0.3), Vector2(0.74, 0.42),
					Vector2(0.66, 0.54), Vector2(0.5, 0.58), Vector2(0.34, 0.54), Vector2(0.26, 0.42),
					Vector2(0.26, 0.3), Vector2(0.34, 0.18)], main, false)
			_shape([Vector2(0.36, 0.3), Vector2(0.48, 0.2), Vector2(0.52, 0.24), Vector2(0.4, 0.34)],
					Color.WHITE, false)


## Points round a circle, in 0..1 icon space.
static func _circle(centre: Vector2, radius: float, sides: int = 14) -> Array:
	var points := []
	for index in sides:
		var angle := TAU * index / sides
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


## One filled polygon in 0..1 icon space, with a dark outline unless it is a detail on top.
func _shape(points: Array, color: Color, outlined: bool = true) -> void:
	var scaled := PackedVector2Array()
	for point: Vector2 in points:
		scaled.append(point * size)
	var fill := color
	var edge := OUTLINE
	if dimmed:
		var grey := fill.v * 0.45
		fill = Color(grey, grey, grey * 1.1, 0.7)
		edge.a = 0.5
	draw_colored_polygon(scaled, fill)
	if outlined:
		scaled.append(scaled[0])
		draw_polyline(scaled, edge, maxf(1.5, size.x * 0.05), true)
