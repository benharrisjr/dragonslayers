class_name Culling
extends RefCounted

## Distance rules for everything the world scatters around.
##
## The map is 256 m across and a pane can see most of it from the mountain, so without these
## every tree, rock and skeleton on it is submitted every frame, four times over in a four-way
## split. Measured before writing any of this: the frame was 50 ms with 48 ms of it in process
## and only 1.5 ms in physics, so the animation each distant skeleton was running mattered more
## than the triangles it drew.

## Beyond this a prop stops being drawn. Big things get proportionally more, so a windmill does
## not pop out at the same distance as a rock.
const PROP_BASE_RANGE := 85.0
const PROP_RANGE_PER_METRE := 28.0
## Faded rather than switched, over enough distance that the transition is not a visible line
## sweeping across the ground as the camera moves.
const FADE_MARGIN := 14.0

## Monsters keep thinking and animating this close to any player. Comfortably beyond aggro
## range (14-18 m), so nothing ever freezes while it could still be relevant to somebody.
const MONSTER_ACTIVE_RANGE := 60.0
## Past this they are not drawn at all. Skinned characters are markedly more expensive than
## static scenery -- each one costs a bone upload and a second pass into the shadow map, per
## split-screen pane -- so this is much tighter than the draw distance given to props.
const MONSTER_VISIBLE_RANGE := 78.0
## Past this they are still drawn but stop casting shadows. A shadow from a skeleton 50 m away
## on a 512 m map is a few pixels, and dropping it halves what that character costs to render.
const MONSTER_SHADOW_RANGE := 34.0
## Seconds between distance checks. They are cheap, but there is no reason to do them every
## frame for something that is 200 m away.
const CHECK_INTERVAL := 0.35


## Applies a draw distance to every mesh under `node`, fading out rather than popping.
static func apply_prop_range(node: Node, radius: float) -> void:
	var distance := PROP_BASE_RANGE + radius * PROP_RANGE_PER_METRE
	for mesh in meshes_under(node):
		mesh.visibility_range_end = distance
		mesh.visibility_range_end_margin = FADE_MARGIN
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		## Small scenery casting shadows across a 256 m map costs more than it adds; the
		## terrain's own cliffs are what give the scene its depth.
		if radius < 1.0:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func meshes_under(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(meshes_under(child))
	return out


## Distance from `point` to the nearest living player, or INF when nobody is alive.
static func distance_to_nearest_player(point: Vector3) -> float:
	var best := INF
	for body in PlayerRegistry.living_bodies():
		best = minf(best, point.distance_to((body as Node3D).global_position))
	return best
