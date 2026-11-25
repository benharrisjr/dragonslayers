class_name GameSfx
extends RefCounted

## Placeholder sound effects, synthesised at start-up rather than recorded.
##
## Every sound is a short recipe -- a few swept tones and filtered noise bursts added together --
## rendered once into an AudioStreamWAV and handed to the template's SoundManager. They are meant
## to be replaced: registering a real recording under the same id (SoundManager.register_sfx)
## after `register()` has run is all it takes, and nothing that plays a sound has to change.
##
##   GameSfx.play(&"coin")                  # always heard
##   GameSfx.play_at(&"attack", position)   # quieter the further it is from a local player

const RATE := 22050
## A sound in the world is at full volume within NEAR of a player on this machine, fades with
## distance beyond that, and past HEARING is not played at all. With several players on one
## screen it is the nearest one that counts. There is no panning: one pair of speakers cannot be
## to the left of one split-screen player and the right of another.
const NEAR := 6.0
const HEARING := 38.0

## Each layer: wave ("sine", "square", "saw", "tri", "noise" or "hiss"), start time, length,
## start and end frequency (for noise, the filter's cutoff), volume, attack time, and how sharply
## it dies away. "noise" keeps what is below the cutoff, "hiss" what is above it.
const RECIPES: Dictionary = {
	&"attack": [
		["hiss", 0.0, 0.17, 900.0, 4200.0, 0.55, 0.03, 1.4],
		["sine", 0.0, 0.11, 320.0, 120.0, 0.18, 0.005, 1.0],
	],
	&"hook_fire": [
		["saw", 0.0, 0.15, 280.0, 1500.0, 0.26, 0.005, 1.0],
		["hiss", 0.0, 0.1, 2500.0, 5000.0, 0.22, 0.005, 1.5],
	],
	&"hook_grab": [
		["hiss", 0.0, 0.03, 5000.0, 5000.0, 0.5, 0.001, 1.0],
		["square", 0.0, 0.06, 1900.0, 1300.0, 0.22, 0.001, 1.0],
		["sine", 0.01, 0.2, 640.0, 610.0, 0.34, 0.002, 2.0],
	],
	&"lantern": [
		["noise", 0.0, 0.5, 350.0, 2600.0, 0.6, 0.14, 1.6],
		["sine", 0.0, 0.32, 190.0, 90.0, 0.22, 0.02, 1.0],
	],
	&"jump": [
		["square", 0.0, 0.15, 250.0, 640.0, 0.2, 0.005, 1.5],
	],
	&"hurt": [
		["square", 0.0, 0.24, 230.0, 65.0, 0.34, 0.002, 1.2],
		["noise", 0.0, 0.13, 1100.0, 200.0, 0.5, 0.002, 1.5],
	],
	&"chest": [
		["noise", 0.0, 0.1, 600.0, 200.0, 0.4, 0.004, 1.2],
		["tri", 0.06, 0.12, 392.0, 392.0, 0.3, 0.004, 1.0],
		["tri", 0.14, 0.12, 523.0, 523.0, 0.3, 0.004, 1.0],
		["tri", 0.22, 0.12, 659.0, 659.0, 0.3, 0.004, 1.0],
		["tri", 0.30, 0.3, 784.0, 784.0, 0.32, 0.004, 1.6],
	],
	&"coin": [
		["tri", 0.0, 0.07, 1568.0, 1568.0, 0.3, 0.002, 0.8],
		["tri", 0.06, 0.2, 2093.0, 2093.0, 0.3, 0.002, 1.8],
	],
	&"heart": [
		["sine", 0.0, 0.13, 523.0, 659.0, 0.32, 0.01, 0.8],
		["sine", 0.12, 0.26, 784.0, 784.0, 0.32, 0.01, 1.6],
	],
	&"item": [
		["square", 0.0, 0.1, 523.0, 523.0, 0.18, 0.004, 0.8],
		["square", 0.08, 0.1, 659.0, 659.0, 0.18, 0.004, 0.8],
		["square", 0.16, 0.1, 784.0, 784.0, 0.18, 0.004, 0.8],
		["square", 0.24, 0.4, 1047.0, 1047.0, 0.2, 0.004, 1.8],
		["tri", 0.24, 0.4, 523.0, 523.0, 0.2, 0.004, 1.8],
	],
	&"rock_lift": [
		["sine", 0.0, 0.28, 70.0, 150.0, 0.55, 0.03, 1.0],
		["noise", 0.0, 0.22, 300.0, 800.0, 0.35, 0.05, 1.2],
	],
	&"rock_throw": [
		["noise", 0.0, 0.26, 500.0, 2400.0, 0.5, 0.09, 1.2],
	],
	&"rock_shatter": [
		["noise", 0.0, 0.55, 3200.0, 250.0, 0.8, 0.002, 2.0],
		["sine", 0.0, 0.32, 115.0, 40.0, 0.5, 0.002, 1.2],
		["hiss", 0.1, 0.04, 4000.0, 4000.0, 0.35, 0.001, 1.0],
		["hiss", 0.19, 0.04, 3000.0, 3000.0, 0.3, 0.001, 1.0],
		["hiss", 0.3, 0.05, 3500.0, 3500.0, 0.22, 0.001, 1.0],
	],
	&"bomb": [
		["noise", 0.0, 0.9, 2400.0, 120.0, 0.95, 0.002, 1.8],
		["sine", 0.0, 0.6, 90.0, 32.0, 0.7, 0.002, 1.3],
		["square", 0.0, 0.18, 160.0, 50.0, 0.3, 0.001, 1.0],
	],
	&"door": [
		["noise", 0.0, 0.5, 220.0, 120.0, 0.55, 0.05, 1.4],
		["sine", 0.0, 0.4, 70.0, 55.0, 0.4, 0.02, 1.2],
	],
	&"secret": [
		["tri", 0.0, 0.12, 784.0, 784.0, 0.26, 0.004, 0.8],
		["tri", 0.1, 0.12, 740.0, 740.0, 0.26, 0.004, 0.8],
		["tri", 0.2, 0.12, 622.0, 622.0, 0.26, 0.004, 0.8],
		["tri", 0.3, 0.12, 440.0, 440.0, 0.26, 0.004, 0.8],
		["tri", 0.4, 0.12, 415.0, 415.0, 0.26, 0.004, 0.8],
		["tri", 0.5, 0.12, 659.0, 659.0, 0.26, 0.004, 0.8],
		["tri", 0.6, 0.12, 831.0, 831.0, 0.26, 0.004, 0.8],
		["tri", 0.7, 0.4, 1047.0, 1047.0, 0.3, 0.004, 1.8],
	],
	&"fan": [
		["noise", 0.0, 0.65, 500.0, 3600.0, 0.6, 0.16, 1.3],
		["hiss", 0.05, 0.45, 2500.0, 5000.0, 0.2, 0.15, 1.2],
	],
	&"net": [
		["hiss", 0.0, 0.15, 2200.0, 6000.0, 0.4, 0.03, 1.3],
	],
	&"bug": [
		["sine", 0.0, 0.07, 1800.0, 2700.0, 0.26, 0.004, 1.0],
		["sine", 0.08, 0.1, 2200.0, 3300.0, 0.26, 0.004, 1.2],
	],
	&"buy": [
		["tri", 0.0, 0.08, 1047.0, 1047.0, 0.28, 0.003, 0.8],
		["tri", 0.07, 0.08, 1319.0, 1319.0, 0.28, 0.003, 0.8],
		["tri", 0.14, 0.26, 1568.0, 1568.0, 0.3, 0.003, 1.8],
	],
	## The dragon. A low growl that swells and breaks into a rasp, with a deep thump under it.
	&"roar": [
		["saw", 0.0, 1.7, 95.0, 58.0, 0.42, 0.18, 1.1],
		["square", 0.05, 1.5, 62.0, 44.0, 0.22, 0.2, 1.0],
		["noise", 0.1, 1.5, 700.0, 260.0, 0.75, 0.25, 1.3],
		["hiss", 0.25, 1.1, 1200.0, 600.0, 0.25, 0.3, 1.5],
		["sine", 0.0, 0.5, 48.0, 36.0, 0.45, 0.02, 1.2],
	],
	## Great wings beating as it takes off.
	&"wings": [
		["noise", 0.0, 0.35, 420.0, 180.0, 0.7, 0.08, 1.6],
		["noise", 0.45, 0.35, 420.0, 180.0, 0.65, 0.08, 1.6],
		["noise", 0.9, 0.35, 420.0, 180.0, 0.55, 0.08, 1.6],
	],
	## A charge is full: a quick bright chime.
	&"charged": [
		["tri", 0.0, 0.08, 1319.0, 1319.0, 0.25, 0.002, 0.8],
		["tri", 0.06, 0.25, 1976.0, 1976.0, 0.28, 0.002, 1.8],
	],
	## A spin: one long whoosh, rising and falling.
	&"spin": [
		["hiss", 0.0, 0.45, 900.0, 4500.0, 0.5, 0.12, 1.1],
		["sine", 0.0, 0.3, 220.0, 120.0, 0.15, 0.02, 1.0],
	],
	## Knives or arrows loosed all at once: a rattle of short hisses.
	&"flurry": [
		["hiss", 0.0, 0.06, 3000.0, 5000.0, 0.4, 0.002, 1.2],
		["hiss", 0.05, 0.06, 2800.0, 5000.0, 0.35, 0.002, 1.2],
		["hiss", 0.1, 0.06, 3200.0, 5000.0, 0.35, 0.002, 1.2],
		["hiss", 0.15, 0.08, 2600.0, 5000.0, 0.3, 0.002, 1.4],
	],
	## The mage's ring: a shimmer sweeping up.
	&"arcane": [
		["sine", 0.0, 0.5, 330.0, 990.0, 0.3, 0.05, 1.2],
		["tri", 0.05, 0.45, 660.0, 1980.0, 0.15, 0.05, 1.4],
		["hiss", 0.15, 0.3, 4000.0, 7000.0, 0.15, 0.05, 1.5],
	],
	## Falling into the river.
	&"splash": [
		["noise", 0.0, 0.45, 2400.0, 500.0, 0.75, 0.005, 1.6],
		["hiss", 0.05, 0.35, 3000.0, 6000.0, 0.3, 0.01, 1.4],
	],
	&"boomerang": [
		["hiss", 0.0, 0.5, 1800.0, 3200.0, 0.3, 0.05, 0.8],
		["sine", 0.0, 0.45, 260.0, 300.0, 0.12, 0.03, 0.6],
	],
	&"leaves": [
		["hiss", 0.0, 0.22, 2500.0, 5500.0, 0.32, 0.02, 1.4],
		["noise", 0.03, 0.18, 1800.0, 900.0, 0.18, 0.01, 1.2],
	],
	&"grass_cut": [
		["hiss", 0.0, 0.12, 3000.0, 7000.0, 0.45, 0.004, 1.6],
		["hiss", 0.05, 0.1, 4000.0, 6500.0, 0.3, 0.004, 1.6],
	],
	&"deny": [
		["square", 0.0, 0.09, 150.0, 150.0, 0.25, 0.003, 0.6],
		["square", 0.12, 0.12, 120.0, 120.0, 0.25, 0.003, 0.8],
	],
}

static var _registered: bool = false


## Renders every recipe and registers it. Safe to call more than once.
static func register() -> void:
	if _registered:
		return
	_registered = true
	for id: StringName in RECIPES:
		SoundManager.register_sfx(id, render(RECIPES[id]), -4.0)


static func play(id: StringName, volume: float = 1.0) -> void:
	register()
	SoundManager.play_sfx(id, randf_range(0.95, 1.06), linear_to_db(maxf(volume, 0.001)))


## How loud a sound `distance` away is, 0 to 1.
static func loudness(distance: float) -> float:
	if distance <= NEAR:
		return 1.0
	if distance >= HEARING:
		return 0.0
	var t := (distance - NEAR) / (HEARING - NEAR)
	return (1.0 - t) * (1.0 - t)


## Plays a sound that happened at a place in the world, as loud as it is to the nearest player
## on this machine. Returns that volume, 0 (and nothing played) if nobody is in earshot. `reach`
## stretches the distances for something louder than ordinary: a dragon's roar at 3 is heard at
## full volume within 18 m and fades out by 114 m.
static func play_at(id: StringName, position: Vector3, reach: float = 1.0) -> float:
	var nearest := INF
	for pid in PlayerRegistry.local_pids():
		var body := PlayerRegistry.body_of(pid)
		if body != null and is_instance_valid(body):
			nearest = minf(nearest, (body as Node3D).global_position.distance_to(position))
	var volume := loudness(nearest / maxf(reach, 0.01))
	if volume > 0.0:
		play(id, volume)
	return volume


## Adds a recipe's layers together into one 16-bit mono clip.
static func render(layers: Array) -> AudioStreamWAV:
	var length := 0.0
	for layer: Array in layers:
		length = maxf(length, float(layer[1]) + float(layer[2]))
	var samples := PackedFloat32Array()
	samples.resize(int(length * RATE) + 1)
	## A fixed seed, so a sound is the same sound every time the game starts.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	for layer: Array in layers:
		_add_layer(samples, layer, rng)

	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size():
		bytes.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


static func _add_layer(samples: PackedFloat32Array, layer: Array,
		rng: RandomNumberGenerator) -> void:
	var wave: String = layer[0]
	var first := int(float(layer[1]) * RATE)
	var count := int(float(layer[2]) * RATE)
	var from: float = layer[3]
	var to: float = layer[4]
	var volume: float = layer[5]
	var attack := maxf(float(layer[6]), 0.0005) * RATE
	var decay: float = layer[7]
	var phase := 0.0
	var low := 0.0
	for step in count:
		var t := float(step) / float(count)
		var frequency := lerpf(from, to, t)
		var value := 0.0
		match wave:
			"noise", "hiss":
				## One-pole low-pass with a moving cutoff; the hiss is whatever it removed.
				var raw := rng.randf_range(-1.0, 1.0)
				low += (1.0 - exp(-TAU * frequency / RATE)) * (raw - low)
				value = low * 1.6 if wave == "noise" else raw - low
			_:
				phase = fmod(phase + frequency / RATE, 1.0)
				match wave:
					"sine":
						value = sin(phase * TAU)
					"square":
						value = 0.6 if phase < 0.5 else -0.6
					"saw":
						value = (phase * 2.0 - 1.0) * 0.7
					"tri":
						value = absf(phase * 4.0 - 2.0) - 1.0
		var envelope := minf(1.0, float(step) / attack) * pow(1.0 - t, decay)
		var at := first + step
		if at < samples.size():
			samples[at] += value * volume * envelope
