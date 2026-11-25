class_name DragonAnimator
extends RefCounted

## The dragon's attack poses, as keyframe tables.
##
## The model (MattBas's dragon, art/models/dragon_mattbas.glb) brings its own idle, walk, run and
## flying loops. Its attacks are added on top by DragonPoser from the tables here, and an attack's
## damage lands on the frame its pose says it does: `Dragon.ATTACKS` names a `hit_at` time that is
## read against these same numbers.
##
## Every rotation is written in the skeleton's own space -- the head points along +Z, up is +Y and
## the left wing reaches along +X -- and is added about the bone's own joint. So the tables read
## as intent: "neck up 30 degrees", "left wing down", "tail round to the left", whatever each bone's
## local axes happen to be.

## Bones by part, in the model's names. Several bones per part, so a bend is spread along the
## chain rather than kinking at one joint.
const NECK: Array[String] = ["Neck0", "Neck1", "Neck2", "Neck3"]
const HEAD := "Head"
const JAW := "Jaw"
const TAIL: Array[String] = ["Tail0", "Tail1", "Tail2", "Tail3", "Tail4"]
const BODY: Array[String] = ["UpperBack"]
const WING_L: Array[String] = ["LeftWingTop", "LeftWingBottom"]
const WING_R: Array[String] = ["RightWingTop", "RightWingBottom"]
const ARM_L := "LeftArmTop"
const ARM_R := "RightArmTop"

## Every bone any clip turns.
const DRIVEN_BONES: Array[String] = [
	"Neck0", "Neck1", "Neck2", "Neck3", "Head", "Jaw",
	"Tail0", "Tail1", "Tail2", "Tail3", "Tail4",
	"UpperBack", "LeftWingTop", "LeftWingBottom", "RightWingTop", "RightWingBottom",
	"LeftArmTop", "RightArmTop",
]

static var _clips: Dictionary = {}


static func clip(name: String) -> Array:
	if _clips.is_empty():
		_build()
	return _clips.get(name, [])


static func duration(name: String) -> float:
	var frames := clip(name)
	return 0.0 if frames.is_empty() else float(frames[-1]["t"])


static func has(name: String) -> bool:
	if _clips.is_empty():
		_build()
	return _clips.has(name)


## The offsets a clip holds at time `t`, as bone name -> Quaternion in skeleton space.
static func sample(name: String, t: float) -> Dictionary:
	var frames := clip(name)
	if frames.is_empty():
		return {}
	if t <= float(frames[0]["t"]):
		return frames[0]["pose"]
	if t >= float(frames[-1]["t"]):
		return frames[-1]["pose"]
	for i in range(frames.size() - 1):
		var a: Dictionary = frames[i]
		var b: Dictionary = frames[i + 1]
		var t0: float = a["t"]
		var t1: float = b["t"]
		if t < t0 or t > t1:
			continue
		## Smoothstep rather than linear, so a wind-up eases into its held pose and the strike out
		## of it -- most of what makes a telegraph readable.
		var k := smoothstep(0.0, 1.0, (t - t0) / maxf(0.0001, t1 - t0))
		return _blend(a["pose"], b["pose"], k)
	return frames[-1]["pose"]


static func _blend(from: Dictionary, to: Dictionary, k: float) -> Dictionary:
	var out := {}
	for bone: String in DRIVEN_BONES:
		var a: Quaternion = from.get(bone, Quaternion.IDENTITY)
		var b: Quaternion = to.get(bone, Quaternion.IDENTITY)
		if a == Quaternion.IDENTITY and b == Quaternion.IDENTITY:
			continue
		out[bone] = a.slerp(b, k)
	return out


## --- pose vocabulary, in skeleton space -------------------------------------------------------

static func _turn(axis: Vector3, degrees: float) -> Quaternion:
	return Quaternion(axis, deg_to_rad(degrees))


## The neck and head raised by `degrees` in all (negative lowers them), spread along the chain.
static func neck_up(degrees: float, head: float = 0.0) -> Dictionary:
	var out := {}
	for bone in NECK:
		out[bone] = _turn(Vector3.RIGHT, -degrees / NECK.size())
	out[HEAD] = _turn(Vector3.RIGHT, -head)
	return out


static func jaw_open(degrees: float) -> Dictionary:
	return {JAW: _turn(Vector3.RIGHT, degrees)}


## Both wings raised by `degrees` at the shoulder and `fold` more at the elbow (negative lowers).
static func wings_up(degrees: float, fold: float = 0.0) -> Dictionary:
	return {
		WING_L[0]: _turn(Vector3.FORWARD, -degrees), WING_R[0]: _turn(Vector3.FORWARD, degrees),
		WING_L[1]: _turn(Vector3.FORWARD, -fold), WING_R[1]: _turn(Vector3.FORWARD, fold),
	}


## The tail swung round by `degrees` in all, towards the dragon's left for positive.
static func tail_round(degrees: float) -> Dictionary:
	var out := {}
	for index in TAIL.size():
		## The tip swings further than the root.
		out[TAIL[index]] = _turn(Vector3.UP, -degrees * (0.6 + 0.2 * index) / TAIL.size())
	return out


## The chest reared back (positive) or thrown forward (negative).
static func rear(degrees: float) -> Dictionary:
	return {BODY[0]: _turn(Vector3.RIGHT, -degrees)}


## A front leg raised forward by `degrees`.
static func arm_up(bone: String, degrees: float) -> Dictionary:
	return {bone: _turn(Vector3.RIGHT, -degrees)}


static func _pose(parts: Array) -> Dictionary:
	var out := {}
	for part: Dictionary in parts:
		out.merge(part, true)
	return out


static func _key(t: float, parts: Array = []) -> Dictionary:
	return {"t": t, "pose": _pose(parts)}


static func _build() -> void:
	## --- fire breath -------------------------------------------------------------------
	## A long rear-back so a party at range has time to read it and move, then the head snaps
	## forward and down and holds, jaws wide, while the cone burns.
	_clips["breath"] = [
		_key(0.0),
		_key(0.9, [neck_up(40.0, 20.0), rear(12.0), wings_up(22.0, 10.0), jaw_open(10.0)]),
		_key(1.15, [neck_up(-22.0, -10.0), rear(-6.0), wings_up(8.0), jaw_open(32.0)]),
		_key(2.4, [neck_up(-18.0, -8.0), rear(-4.0), wings_up(6.0), jaw_open(30.0)]),
		_key(3.0),
	]

	## --- fire from the air -------------------------------------------------------------
	## On the wing: the neck curls down under it, so the flame pours onto the ground below.
	_clips["air_breath"] = [
		_key(0.0),
		_key(0.45, [neck_up(30.0, 10.0), jaw_open(12.0)]),
		_key(0.7, [neck_up(-55.0, -25.0), jaw_open(34.0)]),
		_key(1.6, [neck_up(-50.0, -22.0), jaw_open(30.0)]),
		_key(2.1),
	]

	## --- claw swipe --------------------------------------------------------------------
	## Rears up and lifts the right forefoot, then rakes down and forward with it.
	_clips["claw"] = [
		_key(0.0),
		_key(0.45, [rear(20.0), neck_up(16.0), arm_up(ARM_R, 75.0), arm_up(ARM_L, 25.0),
				wings_up(24.0, 10.0)]),
		_key(0.68, [rear(-10.0), neck_up(-12.0), arm_up(ARM_R, -20.0), arm_up(ARM_L, 5.0),
				wings_up(8.0)]),
		_key(1.3),
	]

	## --- tail sweep --------------------------------------------------------------------
	## Coils the tail round to one side, then whips it through the arc behind. The wind-up is
	## long and obvious on purpose: this is the attack that throws people off the mountain.
	_clips["tail_sweep"] = [
		_key(0.0),
		_key(0.85, [tail_round(70.0), neck_up(6.0)]),
		_key(1.15, [tail_round(-85.0)]),
		_key(1.9),
	]

	## --- wing beat ---------------------------------------------------------------------
	## Both wings up and then driven down hard. Short: it is the answer to melee crowding in.
	_clips["wing_flap"] = [
		_key(0.0),
		_key(0.5, [wings_up(55.0, 25.0), rear(10.0)]),
		_key(0.68, [wings_up(-35.0, -15.0), rear(-6.0)]),
		_key(1.35),
	]

	## --- roar --------------------------------------------------------------------------
	## No damage. Played on aggro and when enraged, so the party always knows the state changed.
	_clips["roar"] = [
		_key(0.0),
		_key(0.5, [neck_up(45.0, 25.0), jaw_open(36.0), wings_up(40.0, 20.0), rear(10.0)]),
		_key(1.4, [neck_up(38.0, 20.0), jaw_open(30.0), wings_up(34.0, 16.0), rear(8.0)]),
		_key(2.1),
	]

	## --- death -------------------------------------------------------------------------
	## Rears up once, then slumps: head down, wings fallen. Ends held, so the corpse stays down.
	_clips["death"] = [
		_key(0.0),
		_key(0.6, [neck_up(40.0, 20.0), jaw_open(30.0), wings_up(30.0, 15.0)]),
		_key(2.2, [neck_up(-60.0, -20.0), jaw_open(15.0), wings_up(-40.0, -30.0), rear(-12.0),
				tail_round(25.0)]),
	]
