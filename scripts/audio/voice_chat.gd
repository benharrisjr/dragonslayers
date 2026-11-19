class_name VoiceChat
extends Node

## Proximity voice chat between machines in an online match.
##
## Each machine has one microphone, and it speaks for that machine's first player: the voice
## comes from where that player is standing. How loud it is on another machine depends on how
## far that player is from the nearest player there -- full volume close by, fading to nothing
## at FAR. Players on the same couch hear each other across the room and are not sent anything.
##
## The mirror is the exception. A speaker carrying one is heard at full volume, at any
## distance, by every machine that has a player carrying one too.
##
## Nothing is sent to a machine that would not hear it. The microphone is captured on a muted
## bus, cut down to roughly 12 kHz mono, gated so silence is not transmitted, packed to one byte
## a sample (mu-law) and sent unreliably in 40 ms pieces; a lost piece is a click, not a stall.

## Full volume inside NEAR, silent beyond FAR.
const NEAR := 8.0
const FAR := 40.0
## Roughly what the microphone is cut down to; the real rate is the mix rate over a whole number.
const TARGET_RATE := 12000
## Seconds of sound per packet.
const PACKET_TIME := 0.04
## Quieter than this (RMS) is not speech.
const GATE := 0.012
## How long the gate stays open after the last loud packet, so word endings are not clipped.
const HANG_TIME := 0.4
const MIC_BUS := "Mic"
const VOICE_BUS := "Voice"
## Microphones are quiet next to game audio; voices are played back this much hotter.
const VOICE_GAIN_DB := 6.0

## The V key. Stays as it was set from match to match.
static var muted: bool = false

var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _factor: int = 4
var _rate: int = TARGET_RATE
var _pending: PackedFloat32Array = PackedFloat32Array()
var _hang: float = 0.0
## Speaking machine -> {"player": AudioStreamPlayer, "playback": AudioStreamGeneratorPlayback,
## "rate": int}.
var _voices: Dictionary = {}
## Speaking player's pid -> the marker over their head.
var _marks: Dictionary = {}
var _status: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position += Vector2(14, -34)
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_status.add_theme_constant_override("outline_size", 4)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	layer.add_child(_status)


## Whether voices should be flowing at all: online, and in a match.
func active() -> bool:
	return NetworkManager.is_networked() and GameState.phase == GameState.Phase.PLAYING \
			and not PlayerRegistry.local_pids().is_empty()


func toggle_mute() -> void:
	muted = not muted


func _process(delta: float) -> void:
	for pid: int in _marks.keys():
		var mark := _marks[pid] as Node3D
		if not is_instance_valid(mark):
			_marks.erase(pid)
			continue
		var left := float(mark.get_meta("left", 0.0)) - delta
		mark.set_meta("left", left)
		mark.visible = left > 0.0

	if not active():
		_status.visible = false
		_stop_mic()
		return
	_status.visible = true
	if not _start_mic():
		_status.text = "No microphone"
		_status.modulate = Color(1, 1, 1, 0.5)
		return
	var speaking := _pump(delta)
	if muted:
		_status.text = "Mic muted  (V)"
		_status.modulate = Color(1.0, 0.55, 0.5)
	else:
		_status.text = "Mic on  (V)"
		_status.modulate = Color(0.6, 0.95, 0.5) if speaking else Color(1, 1, 1, 0.6)


# --- who hears whom ---------------------------------------------------------------------------

## How loud something `distance` away is, 0 to 1: full inside NEAR, gone by FAR.
static func falloff(distance: float) -> float:
	if distance <= NEAR:
		return 1.0
	if distance >= FAR:
		return 0.0
	var t := (distance - NEAR) / (FAR - NEAR)
	return (1.0 - t) * (1.0 - t)


## How loud `speaker` is to a machine whose players are `listeners`, 0 to 1. Two mirrors, one
## at each end, make it 1 whatever the distance.
static func gain_between(speaker: PlayerCharacter, listeners: Array) -> float:
	if speaker == null or not is_instance_valid(speaker):
		return 0.0
	var best := 0.0
	var mirrored := speaker.has_item(ItemDB.MIRROR)
	for node in listeners:
		var listener := node as PlayerCharacter
		if listener == null or not is_instance_valid(listener) or listener == speaker:
			continue
		if mirrored and listener.has_item(ItemDB.MIRROR):
			return 1.0
		best = maxf(best, falloff(listener.global_position.distance_to(speaker.global_position)))
	return best


## The bodies a machine is playing.
static func bodies_of_peer(peer_id: int) -> Array:
	var out: Array = []
	for pid: int in PlayerRegistry.bodies.keys():
		if PlayerRegistry.peer_of(pid) == peer_id and PlayerRegistry.body_of(pid) != null:
			out.append(PlayerRegistry.body_of(pid))
	return out


## The player this machine's microphone speaks for.
static func local_speaker() -> PlayerCharacter:
	var pids := PlayerRegistry.local_pids()
	return PlayerRegistry.body_of(pids[0]) as PlayerCharacter if not pids.is_empty() else null


# --- sending ----------------------------------------------------------------------------------

func _start_mic() -> bool:
	if _mic != null:
		return true
	if DisplayServer.get_name() == "headless" \
			or not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return false
	if AudioServer.get_bus_index(MIC_BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, MIC_BUS)
		## Captured, never heard: nobody wants their own voice back through the speakers.
		AudioServer.set_bus_mute(index, true)
		AudioServer.add_bus_effect(index, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(AudioServer.get_bus_index(MIC_BUS), 0) as AudioEffectCapture
	if _capture == null:
		return false
	_factor = maxi(1, roundi(AudioServer.get_mix_rate() / float(TARGET_RATE)))
	_rate = int(AudioServer.get_mix_rate() / _factor)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = MIC_BUS
	add_child(_mic)
	_mic.play()
	_capture.clear_buffer()
	return true


func _stop_mic() -> void:
	if _mic != null:
		_mic.queue_free()
		_mic = null
		_pending.clear()
	if not _voices.is_empty() and not NetworkManager.is_networked():
		for peer: int in _voices:
			(_voices[peer]["player"] as Node).queue_free()
		_voices.clear()


## Moves whatever the microphone has heard since last frame out onto the network. Returns
## whether anything was loud enough to send.
func _pump(delta: float) -> bool:
	var available := _capture.get_frames_available()
	if available > 0:
		_pending.append_array(downsample(_capture.get_buffer(available), _factor))
	_hang = maxf(0.0, _hang - delta)
	var packet := int(_rate * PACKET_TIME)
	var sent := false
	while _pending.size() >= packet:
		var piece := _pending.slice(0, packet)
		_pending = _pending.slice(packet)
		if muted:
			continue
		if loudness(piece) >= GATE:
			_hang = HANG_TIME
		if _hang > 0.0:
			_send(piece)
			sent = true
	return sent


func _send(samples: PackedFloat32Array) -> void:
	var speaker := local_speaker()
	if speaker == null:
		return
	var data := encode(samples)
	for peer in multiplayer.get_peers():
		if gain_between(speaker, bodies_of_peer(peer)) > 0.0:
			_receive.rpc_id(peer, speaker.pid, _rate, data)


# --- receiving --------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable")
func _receive(pid: int, rate: int, data: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	## A machine speaks only for its own players.
	if PlayerRegistry.peer_of(pid) != sender or rate < 4000 or rate > 48000 or data.size() > 8192:
		return
	hear(sender, PlayerRegistry.body_of(pid) as PlayerCharacter, rate, data)


## Plays a piece of someone's voice at whatever volume the distance (or the mirrors) allows.
## Returns the volume it was played at, 0 to 1.
func hear(peer: int, speaker: PlayerCharacter, rate: int, data: PackedByteArray) -> float:
	var gain := gain_between(speaker, bodies_of_peer(NetworkManager.local_peer_id()))
	if gain <= 0.0:
		return 0.0
	var voice := _voice_for(peer, rate)
	(voice["player"] as AudioStreamPlayer).volume_db = linear_to_db(gain) + VOICE_GAIN_DB
	var playback := voice["playback"] as AudioStreamGeneratorPlayback
	if playback != null:
		## Starting from empty, lay down a little silence first: the next packet then has time
		## to arrive before this one runs out, which is the difference between speech and stutter.
		if playback.get_frames_available() >= int(rate * 0.45):
			for _pad in int(rate * 0.06):
				playback.push_frame(Vector2.ZERO)
		for sample in decode(data):
			if not playback.can_push_buffer(1):
				break
			playback.push_frame(Vector2(sample, sample))
	_mark(speaker)
	return gain


func _voice_for(peer: int, rate: int) -> Dictionary:
	if _voices.has(peer) and _voices[peer]["rate"] == rate \
			and is_instance_valid(_voices[peer]["player"]):
		return _voices[peer]
	if _voices.has(peer) and is_instance_valid(_voices[peer]["player"]):
		(_voices[peer]["player"] as Node).queue_free()
	if AudioServer.get_bus_index(VOICE_BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, VOICE_BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = rate
	generator.buffer_length = 0.5
	var player := AudioStreamPlayer.new()
	player.stream = generator
	player.bus = VOICE_BUS
	add_child(player)
	player.play()
	_voices[peer] = {"player": player, "rate": rate,
			"playback": player.get_stream_playback() as AudioStreamGeneratorPlayback}
	return _voices[peer]


## A small yellow note over the head of whoever is talking.
func _mark(speaker: PlayerCharacter) -> void:
	if speaker == null:
		return
	var mark := _marks.get(speaker.pid) as Label3D
	if mark == null or not is_instance_valid(mark):
		mark = Label3D.new()
		mark.text = "♪"
		mark.font_size = 96
		mark.pixel_size = 0.008
		mark.outline_size = 20
		mark.modulate = Color(1.0, 0.9, 0.3)
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.position.y = speaker.hit_height + 0.7
		speaker.add_child(mark)
		_marks[speaker.pid] = mark
	mark.set_meta("left", 0.3)
	mark.visible = true


# --- the sound itself -------------------------------------------------------------------------

## Stereo frames at the mix rate to mono at 1/factor of it, averaging each group.
static func downsample(frames: PackedVector2Array, factor: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := frames.size() / factor
	out.resize(count)
	for index in count:
		var sum := 0.0
		for step in factor:
			var frame := frames[index * factor + step]
			sum += (frame.x + frame.y) * 0.5
		out[index] = sum / factor
	return out


static func loudness(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum := 0.0
	for sample in samples:
		sum += sample * sample
	return sqrt(sum / samples.size())


## Mu-law: one byte a sample, with the steps packed close together where speech is quiet.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for index in samples.size():
		var value := clampf(samples[index], -1.0, 1.0)
		var squeezed := signf(value) * log(1.0 + 255.0 * absf(value)) / log(256.0)
		out[index] = clampi(roundi((squeezed + 1.0) * 127.5), 0, 255)
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	for index in data.size():
		var squeezed := float(data[index]) / 127.5 - 1.0
		out[index] = signf(squeezed) * (pow(256.0, absf(squeezed)) - 1.0) / 255.0
	return out
