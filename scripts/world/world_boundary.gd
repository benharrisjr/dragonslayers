class_name WorldBoundary
extends Node3D

## Invisible walls round the 4x4 chunk grid, so nobody walks -- or is knocked -- off the edge of
## the generated world.
##
## There used to be a ring of stepped cliffs here as well, filling the horizon. It cost a lot to
## draw for something only ever seen at the map's edge, so it is gone: the map now simply ends,
## and these walls are all that is left of it.

## How tall the walls stand: well over the summit, so even the dragon's knockback off the top
## of the mountain cannot throw anyone over them.
const HEIGHT := 120.0
## Where they start, below the sea bed, so there is no gap underneath at any edge chunk.
const FLOOR := -10.0
const THICKNESS := 4.0


func build() -> void:
	name = "WorldBoundary"
	var span := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var middle := span * 0.5
	var y := FLOOR + HEIGHT * 0.5
	## North, south, west, east: each a slab just outside the map edge, overlapping at the
	## corners so there is no seam to slip through.
	for wall: Array in [
			[Vector3(middle, y, -THICKNESS * 0.5), Vector3(span + THICKNESS * 2.0, HEIGHT, THICKNESS)],
			[Vector3(middle, y, span + THICKNESS * 0.5), Vector3(span + THICKNESS * 2.0, HEIGHT, THICKNESS)],
			[Vector3(-THICKNESS * 0.5, y, middle), Vector3(THICKNESS, HEIGHT, span + THICKNESS * 2.0)],
			[Vector3(span + THICKNESS * 0.5, y, middle), Vector3(THICKNESS, HEIGHT, span + THICKNESS * 2.0)]]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[1]
		shape.shape = box
		shape.position = wall[0]
		body.add_child(shape)


## The top of the walls, in world metres.
static func top() -> float:
	return FLOOR + HEIGHT
