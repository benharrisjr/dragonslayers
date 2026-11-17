extends Node

## Audio buses, volumes, crossfading music and ambience, and pooled one-shot SFX.
##
##   SoundManager.play_music(preload("res://sound/music/title.ogg"))
##   SoundManager.play_ambience(stream)          # second looping layer, own slider
##   SoundManager.register_sfx(&"jump", stream)  # once, e.g. in a scene's _ready
##   SoundManager.play_sfx(&"jump")
##
## Every Button added to the tree gets hover and click sounds automatically.
## The Music, SFX and Ambience buses are created at runtime (there is no
## default_bus_layout.tres); volumes come from SaveManager.global_config.

const MUSIC_CROSSFADE_SEC := 1.5
const AMBIENCE_CROSSFADE_SEC := 2.0
const _SFX_POOL_SIZE := 8

## Baseline bus gain (dB) under each slider: a full slider plays the Music bus
## this much hotter and the Ambience bus this much quieter. Tune per game.
const MUSIC_BUS_BASE_DB := 4.0
const AMBIENCE_BUS_BASE_DB := -6.0

const _HOVER_PATH := "res://sound/003_Hover_03.wav"
const _CLICK_PATH := "res://sound/020_Confirm_10.wav"
const _SAVE_PATH := "res://sound/Save_Game.wav"
const _CLICK_DB := 2.0

var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer

var _sfx_streams: Dictionary = {}   # StringName id -> AudioStream
var _sfx_db: Dictionary = {}        # StringName id -> float volume_db
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_pool_idx: int = 0

# One looping player per stream that has ever been asked for. Only the audible
# track (plus whichever is fading out) actually plays: a silent player still
# runs its decoder, and several of those on a phone's audio thread crackle.
var _music_players: Dictionary = {}    # AudioStream -> AudioStreamPlayer
var _music_tween: Tween = null
var _current_music: AudioStream = null
# Where each track was when it last faded out, so fading it back in resumes
# mid-song instead of restarting.
var _music_positions: Dictionary = {}  # AudioStream -> float seconds

# Same scheme on the Ambience bus.
var _ambience_players: Dictionary = {}
var _ambience_tween: Tween = null
var _current_ambience: AudioStream = null
var _ambience_positions: Dictionary = {}


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	apply_saved_volumes()

	_hover_player = _make_player("SFX")
	_hover_player.stream = _load_stream(_HOVER_PATH)
	_click_player = _make_player("SFX")
	_click_player.stream = _load_stream(_CLICK_PATH)
	_click_player.volume_db = _CLICK_DB

	for i in _SFX_POOL_SIZE:
		_sfx_players.append(_make_player("SFX"))

	# The UI sounds that ship with the template. Games add their own with
	# register_sfx.
	register_sfx(&"hover", _hover_player.stream)
	register_sfx(&"click", _click_player.stream, _CLICK_DB)
	register_sfx(&"save", _load_stream(_SAVE_PATH))

	# Wire buttons already in the tree (the first scene loads before _ready fires)
	for node in get_tree().root.find_children("*", "Button", true, false):
		_wire_button(node as Button)
	# Auto-wire every Button added to the scene tree going forward
	get_tree().node_added.connect(_on_node_added)


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("SoundManager: missing sound %s" % path)
		return null
	return load(path) as AudioStream


# --- Volumes -------------------------------------------------------------------
# Sliders are linear 0..1. These set the bus only; the Options screen stores the
# value in SaveManager.global_config.

func set_master_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(linear, 0.0001)))


func set_music_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)) + MUSIC_BUS_BASE_DB)


func set_sfx_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func set_ambience_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index("Ambience")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)) + AMBIENCE_BUS_BASE_DB)


## Re-apply all four volumes from the saved config.
func apply_saved_volumes() -> void:
	var cfg: GlobalConfig = SaveManager.global_config
	if cfg == null:
		return
	set_master_volume(cfg.master_volume)
	set_music_volume(cfg.music_volume)
	set_sfx_volume(cfg.sfx_volume)
	set_ambience_volume(cfg.ambience_volume)


# --- Music ---------------------------------------------------------------------

## Crossfade to `stream` (looped). Asking for the track already playing is a
## no-op, so a screen can assert its music freely. A track that was playing
## earlier resumes where it faded out. `volume_db` trims a track mastered hotter
## or quieter than the rest.
func play_music(stream: AudioStream, fade: float = MUSIC_CROSSFADE_SEC, volume_db: float = 0.0) -> void:
	if _current_music == stream:
		return
	_current_music = stream
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = _crossfade(_music_players, _music_positions, stream, "Music", fade, volume_db)
	_music_tween.chain().tween_callback(_park_silent.bind(_music_players, _music_positions, true))


## Fade the music to silence.
func stop_music(fade: float = MUSIC_CROSSFADE_SEC) -> void:
	play_music(null, fade)


## Forget where `stream` faded out, so its next play_music starts from the top.
func restart_music_position(stream: AudioStream) -> void:
	_music_positions.erase(stream)


# --- Ambience ------------------------------------------------------------------
# A second looping layer on its own bus and slider, crossfaded independently of
# the music.

func play_ambience(stream: AudioStream, fade: float = AMBIENCE_CROSSFADE_SEC, volume_db: float = 0.0) -> void:
	if _current_ambience == stream:
		return
	_current_ambience = stream
	if _ambience_tween and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_ambience_tween = _crossfade(_ambience_players, _ambience_positions, stream, "Ambience", fade, volume_db)
	_ambience_tween.chain().tween_callback(_park_silent.bind(_ambience_players, _ambience_positions, false))


func stop_ambience(fade: float = AMBIENCE_CROSSFADE_SEC) -> void:
	play_ambience(null, fade)


## Fades `stream` up and every other playing track in `players` down to silence.
func _crossfade(players: Dictionary, positions: Dictionary, stream: AudioStream,
		bus: String, fade: float, volume_db: float) -> Tween:
	if stream != null and not players.has(stream):
		_set_looping(stream)
		var created := _make_player(bus)
		created.stream = stream
		created.volume_linear = 0.0
		players[stream] = created
	var target_player: AudioStreamPlayer = players.get(stream)
	if target_player and not target_player.playing:
		target_player.volume_linear = 0.0
		target_player.play(positions.get(stream, 0.0))
	var tween := create_tween().set_parallel(true)
	# A tween with no tweeners errors when it runs; this keeps it valid when
	# nothing is playing (stop_music before any music).
	tween.tween_interval(0.0)
	var secs := maxf(fade, 0.0)
	for key in players:
		var player: AudioStreamPlayer = players[key]
		if not player.playing:
			continue
		var target := db_to_linear(volume_db) if key == stream else 0.0
		tween.tween_property(player, "volume_linear", target, secs)
	return tween


# After a crossfade settles: stop every track that faded to silence, remembering
# where it was so the next fade-in picks up from there.
func _park_silent(players: Dictionary, positions: Dictionary, is_music: bool) -> void:
	var current := _current_music if is_music else _current_ambience
	for key in players:
		if key == current:
			continue
		var player: AudioStreamPlayer = players[key]
		if player.playing:
			positions[key] = player.get_playback_position()
			player.stop()


# Music and ambience always loop, whatever the import settings say.
func _set_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)


# --- SFX -----------------------------------------------------------------------

## Make `stream` playable as play_sfx(id). `volume_db` is that sound's baseline
## gain, so it is tuned once here instead of at every call site.
func register_sfx(id: StringName, stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	_sfx_streams[id] = stream
	_sfx_db[id] = volume_db


func has_sfx(id: StringName) -> bool:
	return _sfx_streams.has(id)


## Play a registered one-shot on the next pooled player (round-robin, so more
## than _SFX_POOL_SIZE overlapping sounds cut the oldest). Unknown ids are
## skipped silently.
func play_sfx(id: StringName, pitch: float = 1.0) -> void:
	var stream: AudioStream = _sfx_streams.get(id)
	if stream == null or _sfx_players.is_empty():
		return
	var player := _sfx_players[_sfx_pool_idx]
	_sfx_pool_idx = (_sfx_pool_idx + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = _sfx_db.get(id, 0.0)
	player.pitch_scale = maxf(pitch, 0.01)
	player.play()


func _on_node_added(node: Node) -> void:
	if node is Button:
		_wire_button(node as Button)


func _wire_button(btn: Button) -> void:
	if not btn.mouse_entered.is_connected(play_hover):
		btn.mouse_entered.connect(play_hover)
	if not btn.pressed.is_connected(play_click):
		btn.pressed.connect(play_click)


func play_hover() -> void:
	# A touch generates an emulated mouse_entered in the same instant as the
	# press, so on touch devices every tap would play hover + click stacked.
	if Platform.is_touch_device():
		return
	if _hover_player and _hover_player.stream:
		_hover_player.stop()
		_hover_player.play()


func play_click() -> void:
	if _click_player and _click_player.stream:
		_click_player.stop()
		_click_player.play()
