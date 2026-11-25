class_name DragonFlight
extends RefCounted

## A flight the dragon takes: off its perch, round the map, and back.
##
## Built from a seed on every machine, so everyone sees it fly the same way without its position
## being sent anywhere: the host only says "take off with this seed" (or "come home from here").
## The route is a loop through a handful of waypoints spread round the map, smoothed into a curve;
## the height along it is worked out once, up front, by looking down at the ground every couple of
## metres, so the dragon clears trees and cliffs and climbs before it reaches them rather than
## clipping through.

const SPEED := 16.0
## How high above the ground (or the treetops) it cruises.
const CLEARANCE := 15.0
## Steepest climb or dive, metres up per metre along.
const SLOPE := 0.55
## Distance over which it climbs off the perch, and descends back onto it.
const RAMP := 40.0
const STEP := 2.0
const WAYPOINTS := Vector2i(5, 7)
## How far in from the map's edge waypoints are kept.
const MARGIN := 60.0

var length: float = 0.0

var _samples := PackedVector3Array()


## A tour of the map from the perch and back to it.
static func tour(seed_value: int, perch: Vector3, space: PhysicsDirectSpaceState3D) -> DragonFlight:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var span := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
	var centre := WorldGenerator.map_centre()
	## Waypoints at angles round the middle of the map, in order, so the route is a loop rather
	## than a scribble; starting from the side the perch is on.
	var start_angle := atan2(perch.z - centre.z, perch.x - centre.x)
	var count := rng.randi_range(WAYPOINTS.x, WAYPOINTS.y)
	var points := PackedVector3Array([perch])
	for index in count:
		var angle := start_angle + TAU * (index + 0.5) / count + rng.randf_range(-0.25, 0.25)
		var reach := rng.randf_range(0.25, 0.42) * span
		var at := centre + Vector3(cos(angle), 0.0, sin(angle)) * reach
		at.x = clampf(at.x, MARGIN, span - MARGIN)
		at.z = clampf(at.z, MARGIN, span - MARGIN)
		points.append(at)
	points.append(perch)
	var flight := DragonFlight.new()
	flight._build(points, space, perch.y, perch.y)
	return flight


## Straight home from wherever it is now: called off a tour when someone climbs onto the perch.
static func home(from: Vector3, perch: Vector3, space: PhysicsDirectSpaceState3D) -> DragonFlight:
	var midway := (from + perch) * 0.5
	var flight := DragonFlight.new()
	flight._build(PackedVector3Array([from, midway, perch]), space, from.y, perch.y)
	return flight


func position_at(distance: float) -> Vector3:
	if _samples.is_empty():
		return Vector3.ZERO
	var at := clampf(distance, 0.0, length) / STEP
	var index := mini(int(at), _samples.size() - 1)
	var next := mini(index + 1, _samples.size() - 1)
	return _samples[index].lerp(_samples[next], at - index)


## Which way it is heading, level.
func heading_at(distance: float) -> Vector3:
	var ahead := position_at(distance + STEP * 2.0) - position_at(distance - STEP * 2.0)
	ahead.y = 0.0
	return ahead.normalized() if ahead.length_squared() > 0.0001 else Vector3.FORWARD


func duration() -> float:
	return length / SPEED


func is_finished(distance: float) -> bool:
	return distance >= length


## Whether `distance` is out on the cruise rather than climbing off or settling onto the perch.
func is_cruising(distance: float) -> bool:
	return distance > RAMP and distance < length - RAMP


func _build(points: PackedVector3Array, space: PhysicsDirectSpaceState3D, start_y: float,
		end_y: float) -> void:
	## A Catmull-Rom curve through the points, walked finely and then resampled every STEP metres
	## along its length, so speed along it is even.
	var dense := PackedVector3Array()
	for segment in points.size() - 1:
		var p0 := points[maxi(segment - 1, 0)]
		var p1 := points[segment]
		var p2 := points[segment + 1]
		var p3 := points[mini(segment + 2, points.size() - 1)]
		for step in 24:
			var t := float(step) / 24.0
			dense.append(_catmull(p0, p1, p2, p3, t))
	dense.append(points[-1])
	var flat := PackedVector3Array([Vector3(dense[0].x, 0.0, dense[0].z)])
	var carried := 0.0
	for index in range(1, dense.size()):
		var a := Vector3(dense[index - 1].x, 0.0, dense[index - 1].z)
		var b := Vector3(dense[index].x, 0.0, dense[index].z)
		var piece := a.distance_to(b)
		while carried + piece >= STEP:
			var t := (STEP - carried) / piece
			a = a.lerp(b, t)
			piece = a.distance_to(b)
			flat.append(a)
			carried = 0.0
		carried += piece
	flat.append(Vector3(dense[-1].x, 0.0, dense[-1].z))
	length = (flat.size() - 1) * STEP

	## Height: clear of whatever is below, ramped down to the perch at the ends...
	var heights := PackedFloat32Array()
	heights.resize(flat.size())
	for index in flat.size():
		var along := index * STEP
		var ramp := smoothstep(0.0, RAMP, along) * smoothstep(0.0, RAMP, length - along)
		var ground := _ground_at(flat[index], space, lerpf(start_y, end_y, along / maxf(length, 1.0)))
		heights[index] = ground + CLEARANCE * ramp
	heights[0] = start_y
	heights[-1] = end_y
	## ...then no steeper than SLOPE either way, so it rises before a cliff instead of at it.
	for index in range(1, heights.size()):
		heights[index] = maxf(heights[index], heights[index - 1] - SLOPE * STEP)
	for index in range(heights.size() - 2, -1, -1):
		heights[index] = maxf(heights[index], heights[index + 1] - SLOPE * STEP)
	## The ends are the perch itself (or wherever a flight home began), whatever the passes did.
	heights[0] = start_y
	heights[-1] = end_y
	_samples.resize(flat.size())
	for index in flat.size():
		_samples[index] = Vector3(flat[index].x, heights[index], flat[index].z)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## The top of whatever is under a point -- ground, cliff, tree -- by looking straight down.
static func _ground_at(at: Vector3, space: PhysicsDirectSpaceState3D, fallback: float) -> float:
	if space == null:
		return fallback
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.z),
			Vector3(at.x, -50.0, at.z))
	query.collision_mask = Combatant.LAYER_WORLD | Combatant.LAYER_SCENERY
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else fallback
