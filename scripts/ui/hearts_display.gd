class_name HeartsDisplay
extends Control

## The health row: N hearts, each worth two points.
##
## Drawn rather than assembled from textures so that a half heart is exactly half, and so an
## upgraded max-hearts count just changes a number instead of needing new art. An odd number of
## points is a heart cut down the middle: the last heart empties from the right.

const HEART_SIZE := 22.0
const HEART_GAP := 4.0
const EMPTY_COLOR := Color(0.16, 0.13, 0.16, 0.85)
const FULL_COLOR := Color(0.92, 0.24, 0.34)
const OUTLINE_COLOR := Color(0.08, 0.06, 0.08, 0.9)

var current: int = 6
var maximum: int = 6


func set_health(value: int, max_value: int) -> void:
	current = value
	maximum = max_value
	custom_minimum_size = Vector2(
		max_hearts() * (HEART_SIZE + HEART_GAP), HEART_SIZE + 2.0)
	queue_redraw()


func max_hearts() -> int:
	return int(ceil(float(maximum) / float(Combatant.POINTS_PER_HEART)))


func _draw() -> void:
	for index in max_hearts():
		var points_here := clampi(current - index * Combatant.POINTS_PER_HEART,
				0, Combatant.POINTS_PER_HEART)
		var fill := float(points_here) / float(Combatant.POINTS_PER_HEART)
		var origin := Vector2(index * (HEART_SIZE + HEART_GAP), 0.0)
		_draw_heart(origin, EMPTY_COLOR, 1.0)
		if fill > 0.0:
			_draw_heart(origin, FULL_COLOR, fill)


## Fills from the left, so a half heart is its left half and the row drains right to left.
func _draw_heart(origin: Vector2, color: Color, fill: float) -> void:
	var size := HEART_SIZE
	var shape := PackedVector2Array()
	var steps := 18
	for i in range(steps + 1):
		var t := float(i) / steps * TAU
		## Standard heart curve, scaled into the cell.
		var hx := 16.0 * pow(sin(t), 3.0)
		var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		shape.append(origin + Vector2(size * 0.5 + hx * size / 34.0,
				size * 0.5 - hy * size / 34.0))
	if fill >= 1.0:
		draw_colored_polygon(shape, color)
		draw_polyline(shape, OUTLINE_COLOR, 1.5)
		return

	## Clip to the filled fraction by intersecting the heart with a rect from the left. (Squashing
	## the outline's points against the cut instead leaves a polygon that will not triangulate,
	## and draws nothing at all.)
	var cut_x := origin.x + size * fill
	var keep := PackedVector2Array([origin + Vector2(-1.0, -1.0), Vector2(cut_x, origin.y - 1.0),
			Vector2(cut_x, origin.y + size + 1.0), origin + Vector2(-1.0, size + 1.0)])
	if fill > 0.0:
		for piece in Geometry2D.intersect_polygons(shape, keep):
			draw_colored_polygon(piece, color)
	draw_polyline(shape, OUTLINE_COLOR, 1.5)
