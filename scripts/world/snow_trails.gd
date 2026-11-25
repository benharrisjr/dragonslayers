class_name SnowTrails
extends Node

## Winter's tracks: where things have walked through the snow.
##
## One greyscale texture covers the whole map, half a metre to the pixel. Anything walking on
## the ground near a player on this machine presses a soft round print into it every few tens of
## centimetres; the terrain shader darkens the snow there and tilts its normal at the edges, so
## a track reads as a groove. Prints fill back in slowly, so an old trail fades rather than the
## map ending the match covered in them.
##
## Fire melts it: a second channel of the same texture marks snow melted down to the wet ground
## beneath, which comes back far more slowly than a footprint fills in.
##
## Like the grass, this is not sent anywhere: every machine draws the tracks of the bodies it
## can see, which are the same bodies, and every machine sees the same fires.

const PIXELS := 1024
## Metres the texture covers, from the map's corner at the origin.
const SPAN := WorldGenerator.GRID * WorldGenerator.CHUNK_SIZE
## A body leaves a print each time it has moved this far.
const STRIDE := 0.35
## How wide a print is beyond a body's own width, in metres.
const PRINT_MARGIN := 0.1
## How long a full-depth print takes to fill back in, and melted snow to come back, in seconds.
const REFILL_TIME := 60.0
const MELT_TIME := 180.0
const GROUP := &"snow_trails"
## How far past a fire's own edge the snow melts.
const MELT_MARGIN := 0.8
const REFILL_TICK := 0.5
## How often the texture is sent to the graphics card, at most.
const UPLOAD_INTERVAL := 0.08
## Bodies further than this from every player on this machine leave no prints.
const PRINT_DISTANCE := 70.0

var texture: ImageTexture

## Two bytes a pixel: how trodden (R) and how melted (G).
var _data := PackedByteArray()
## Pixels with snow pressed into them, so refilling does not walk all million of them.
var _trodden: Dictionary = {}
## Where each body last left a print, by instance id.
var _last_print: Dictionary = {}
var _dirty: bool = false
var _since_upload: float = 0.0
var _since_refill: float = 0.0


func _init() -> void:
	name = "SnowTrails"
	add_to_group(GROUP)
	_data.resize(PIXELS * PIXELS * 2)
	texture = ImageTexture.create_from_image(_image())


## Points the shared terrain material at this texture.
func attach(material: ShaderMaterial) -> void:
	material.set_shader_parameter("snow", true)
	material.set_shader_parameter("trails", texture)
	material.set_shader_parameter("trail_rect", Vector4(0.0, 0.0, SPAN, SPAN))


## How deep the snow is trodden at a world position, 0 (fresh) to 1.
func depth_at(at: Vector3) -> float:
	var pixel := _pixel_of(at)
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= PIXELS or pixel.y >= PIXELS:
		return 0.0
	return _data[(pixel.y * PIXELS + pixel.x) * 2] / 255.0


## How far the snow at a world position has melted, 0 (snow) to 1 (bare ground).
func melt_at(at: Vector3) -> float:
	var pixel := _pixel_of(at)
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= PIXELS or pixel.y >= PIXELS:
		return 0.0
	return _data[(pixel.y * PIXELS + pixel.x) * 2 + 1] / 255.0


## Melts the snow in a circle `radius` metres across, down to the ground.
func melt(at: Vector3, radius: float) -> void:
	_press(at, radius, 1)


## Melts snow round a fire in every snow field in the match (there is only ever one).
static func melt_all(tree: SceneTree, at: Vector3, radius: float) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		(node as SnowTrails).melt(at, radius + MELT_MARGIN)


## Presses a print `radius` metres across into the snow at `at`.
func stamp(at: Vector3, radius: float) -> void:
	_press(at, radius, 0)


func _press(at: Vector3, radius: float, channel: int) -> void:
	var centre := Vector2(at.x, at.z) / SPAN * PIXELS
	var reach := radius / SPAN * PIXELS
	var low := Vector2i((centre - Vector2.ONE * (reach + 1.0)).floor())
	var high := Vector2i((centre + Vector2.ONE * (reach + 1.0)).ceil())
	for y in range(maxi(low.y, 0), mini(high.y, PIXELS - 1) + 1):
		for x in range(maxi(low.x, 0), mini(high.x, PIXELS - 1) + 1):
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			## Soft-edged: full depth in the middle, feathered over the last pixel.
			var depth := clampf(reach + 0.5 - distance, 0.0, 1.0)
			if depth <= 0.0:
				continue
			var at_index := (y * PIXELS + x) * 2 + channel
			var value := int(depth * 255.0)
			if value > _data[at_index]:
				_data[at_index] = value
				_trodden[at_index] = true
				_dirty = true


func _physics_process(delta: float) -> void:
	_print_bodies()
	_since_refill += delta
	if _since_refill >= REFILL_TICK:
		_refill(_since_refill)
		_since_refill = 0.0
	_since_upload += delta
	if _dirty and _since_upload >= UPLOAD_INTERVAL:
		texture.update(_image())
		_dirty = false
		_since_upload = 0.0


func _print_bodies() -> void:
	var watchers: Array[Vector3] = []
	for pid in PlayerRegistry.local_pids():
		var body := PlayerRegistry.body_of(pid) as Node3D
		if body != null:
			watchers.append(body.global_position)
	if watchers.is_empty():
		return
	for node in get_tree().get_nodes_in_group("combatants"):
		var body := node as Combatant
		if body == null or body.is_dead or not body.is_on_floor():
			continue
		var at := body.global_position
		var near := false
		for watcher in watchers:
			if watcher.distance_squared_to(at) < PRINT_DISTANCE * PRINT_DISTANCE:
				near = true
				break
		if not near:
			continue
		var key := body.get_instance_id()
		var last: Vector3 = _last_print.get(key, Vector3.INF)
		if last != Vector3.INF and last.distance_to(at) < STRIDE:
			continue
		_last_print[key] = at
		stamp(at, body.hit_radius + PRINT_MARGIN)


func _refill(elapsed: float) -> void:
	if _trodden.is_empty():
		return
	var steps: Array[int] = [maxi(1, int(255.0 * elapsed / REFILL_TIME)),
			maxi(1, int(255.0 * elapsed / MELT_TIME))]
	var filled: Array = []
	for at_index: int in _trodden:
		var value := maxi(_data[at_index] - steps[at_index % 2], 0)
		_data[at_index] = value
		if value == 0:
			filled.append(at_index)
	for at_index in filled:
		_trodden.erase(at_index)
	_dirty = true


func _pixel_of(at: Vector3) -> Vector2i:
	return Vector2i((Vector2(at.x, at.z) / SPAN * PIXELS).floor())


func _image() -> Image:
	return Image.create_from_data(PIXELS, PIXELS, false, Image.FORMAT_RG8, _data)
