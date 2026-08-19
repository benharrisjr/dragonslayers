class_name PlayerCharacter
extends Combatant

## A playable adventurer. One of these exists per (peer, split-screen slot) pair.
##
## Movement is owned by whichever machine is driving it, and only that machine reads input:
## remote copies just follow the transform the owner publishes. The exceptions are damage and
## knockback, which the host decides and the owner then obeys -- see Combatant.
##
## Magic and cooldowns are deliberately *not* host-validated. They are personal resources with
## no effect on anyone else's world, and paying a round trip to spend them would make casting
## feel spongy for the sake of policing friends.

signal magic_changed(current: float, maximum: float)
signal ability_used(index: int, ability: AbilityData)
signal respawned

## Below this height a player has fallen off the world. Set well under the lowest terrain so a
## deep pit still reads as a pit rather than an instant respawn.
const KILL_HEIGHT := -25.0
## Falling costs a heart's worth of points. Enough to make ledges frightening, not enough to
## make a knockback into a pit a run-ender.
const FALL_DAMAGE := 4

const AIR_CONTROL := 0.45
const GROUND_ACCEL := 60.0
const AIR_ACCEL := 22.0
const FRICTION := 14.0
## Grace period for jumping after walking off an edge, without which every platform gap feels
## like it ate the input.
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.14
## Seconds without spending magic before the meter starts refilling.
const MAGIC_REGEN_DELAY := 3.0
const MAGIC_REGEN_RATE := 22.0

@export var pid: int = 0

var archetype: ArchetypeData
var visual: CharacterVisual
var targeting: TargetingService
var camera_yaw: float = 0.0

var magic: float = 100.0
var max_magic: float = 100.0
var gold_collected: int = 0

var _input: PlayerInput
var _is_local: bool = false
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _magic_idle: float = 0.0
var _cooldowns: Dictionary = {}
var _was_on_floor: bool = true
var _safe_position: Vector3 = Vector3.ZERO
var _safe_timer: float = 0.0


func configure(player_pid: int, data: ArchetypeData) -> void:
	pid = player_pid
	archetype = data
	faction = Faction.PLAYER
	max_health = data.max_hearts * POINTS_PER_HEART
	health = max_health
	max_magic = data.max_magic
	magic = max_magic
	knockback_resistance = data.knockback_resistance
	name = "Player_%d" % pid

	_is_local = PlayerRegistry.peer_of(pid) == NetworkManager.local_peer_id()
	if _is_local:
		_input = PlayerInput.new(PlayerRegistry.slot_of(pid))
	set_multiplayer_authority(PlayerRegistry.peer_of(pid))

	visual = CharacterVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(data.model_path, data.weapon_paths)
	visual.set_loop(data.idle_anim)

	targeting = TargetingService.new()
	targeting.name = "Targeting"
	add_child(targeting)
	targeting.setup(self, PlayerRegistry.slot_of(pid), data.color)

	_safe_position = global_position
	PlayerRegistry.register_body(pid, self)
	health_changed.emit(health, max_health)
	magic_changed.emit(magic, max_magic)
	died.connect(_on_died)
	damaged.connect(_on_damaged)


func is_local_player() -> bool:
	return _is_local


func slot() -> int:
	return PlayerRegistry.slot_of(pid)


func abilities() -> Array[AbilityData]:
	return archetype.abilities if archetype != null else [] as Array[AbilityData]


func _physics_process(delta: float) -> void:
	_tick_knockback(delta)
	_tick_magic(delta)
	_tick_cooldowns(delta)

	if not _is_local:
		## Remote copies are moved by their owner's synchroniser; running the controller here
		## would fight it. They still need gravity-free move_and_slide to resolve collisions.
		_update_animation()
		return

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
		velocity.y -= gravity() * delta
		move_and_slide()
		return

	_read_actions()
	_move(delta)
	_check_fall(delta)
	_update_animation()


func _read_actions() -> void:
	if _input == null:
		return
	if _input.target_next_pressed():
		targeting.cycle(1)
	if _input.target_prev_pressed():
		targeting.cycle(-1)
	if _input.interact_pressed():
		_interact()
	if _input.attack_pressed():
		use_ability(-1)
	for index in abilities().size():
		if _input.ability_pressed(index):
			use_ability(index)


func _move(delta: float) -> void:
	var wish := Vector2.ZERO
	if _input != null and knockback_time <= 0.0 and not visual.is_acting():
		wish = _input.move_vector()
	## Movement is camera-relative, and each split-screen player has their own camera, so the
	## yaw comes from that player's pane rather than from a single world camera.
	var basis := Basis(Vector3.UP, camera_yaw)
	var direction := (basis * Vector3(wish.x, 0.0, -wish.y))
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var on_floor := is_on_floor()
	_coyote = COYOTE_TIME if on_floor else maxf(0.0, _coyote - delta)
	if _input != null and _input.jump_pressed():
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = archetype.jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
	elif not on_floor and velocity.y > 0.0 and _input != null and not _input.jump_held():
		## Variable jump height: releasing early cuts the arc, which is what makes the
		## platforming feel deliberate rather than floaty.
		velocity.y -= gravity() * 1.4 * delta

	var target_speed := archetype.move_speed
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	var control := 1.0 if on_floor else AIR_CONTROL
	if knockback_time > 0.0:
		## Being thrown means being thrown: a sliver of steering, no more, so a shove towards a
		## cliff cannot simply be walked out of.
		control = 0.15

	var desired := direction * target_speed
	velocity.x = move_toward(velocity.x, desired.x, accel * control * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * control * delta)
	if direction.length_squared() < 0.001 and on_floor and knockback_time <= 0.0:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)

	velocity.y -= gravity() * delta
	move_and_slide()

	## Face the target while one is selected, otherwise face the way you are going. Facing the
	## target is what makes clicking an enemy feel like committing to it.
	var current_target := targeting.target()
	var face_direction := Vector3.ZERO
	if current_target != null:
		face_direction = current_target.global_position - global_position
	elif direction.length_squared() > 0.01:
		face_direction = direction
	face_direction.y = 0.0
	if face_direction.length_squared() > 0.001:
		var wanted := atan2(face_direction.x, face_direction.z)
		rotation.y = lerp_angle(rotation.y, wanted, 1.0 - exp(-14.0 * delta))

	_was_on_floor = on_floor


func _check_fall(delta: float) -> void:
	## Remember the last patch of ground stood on for a moment, so respawn does not drop the
	## player back onto the lip they just slid off.
	if is_on_floor() and velocity.length() < 3.0:
		_safe_timer += delta
		if _safe_timer > 0.25:
			_safe_position = global_position
			_safe_timer = 0.0
	else:
		_safe_timer = 0.0

	if global_position.y < KILL_HEIGHT:
		if NetworkManager.is_host():
			_report_fell()
		else:
			_report_fell.rpc_id(1)
		respawn_at(_safe_position)


@rpc("any_peer", "call_remote", "reliable")
func _report_fell() -> void:
	if not NetworkManager.is_host() or is_dead:
		return
	## No knockback: the player is already airborne and about to be teleported, and shoving a
	## respawning body is how you get a respawn loop.
	take_damage(FALL_DAMAGE, global_position + Vector3.UP, 0.0, 0.0)


func respawn_at(position: Vector3) -> void:
	global_position = position + Vector3.UP * 1.5
	velocity = Vector3.ZERO
	knockback_time = 0.0
	respawned.emit()


# --- abilities ------------------------------------------------------------------------------

## `index` of -1 is the free weapon attack; 0+ indexes the archetype's ability list.
func use_ability(index: int) -> bool:
	if is_dead or archetype == null or visual.is_acting():
		return false
	var ability := archetype.basic_attack if index < 0 else abilities()[index] \
			if index < abilities().size() else null
	if ability == null:
		return false
	if _cooldowns.get(ability.id, 0.0) > 0.0:
		return false
	if not ability.can_afford(magic):
		return false

	_spend_magic(ability.magic_cost)
	_cooldowns[ability.id] = ability.cooldown
	visual.play_action(ability.animation, ability.animation_speed)
	ability_used.emit(index, ability)

	var aim := _aim_direction(ability)
	if NetworkManager.is_networked():
		_request_ability.rpc_id(1, String(ability.id), global_position, aim)
		_show_ability.rpc(String(ability.id))
	else:
		_request_ability(String(ability.id), global_position, aim)
	return true


## Aim at the selected target if there is one, otherwise at the nearest thing roughly in front,
## otherwise straight ahead. The middle case is what stops gamepad players having to fiddle
## with target cycling before every swing.
func _aim_direction(ability: AbilityData) -> Vector3:
	var chosen := targeting.target()
	if chosen == null:
		chosen = targeting.nearest_in_front(ability.range)
		if chosen != null and ability.shape == AbilityData.Shape.PROJECTILE:
			targeting.set_target(chosen)
	if chosen != null:
		var offset := chosen.global_position - global_position
		offset.y = 0.0
		if offset.length_squared() > 0.001:
			return offset.normalized()
	return -global_transform.basis.z


@rpc("authority", "call_remote", "reliable")
func _show_ability(ability_id: String) -> void:
	var ability := AbilityDB.get_ability(StringName(ability_id))
	if ability != null and visual != null:
		visual.play_action(ability.animation, ability.animation_speed)


@rpc("any_peer", "call_local", "reliable")
func _request_ability(ability_id: String, origin: Vector3, aim: Vector3) -> void:
	if not NetworkManager.is_host() or is_dead:
		return
	var ability := AbilityDB.get_ability(StringName(ability_id))
	if ability == null:
		return
	AbilityRunner.execute(self, ability, origin, aim)


func _spend_magic(amount: float) -> void:
	if amount <= 0.0:
		return
	magic = maxf(0.0, magic - amount)
	_magic_idle = 0.0
	magic_changed.emit(magic, max_magic)


func _tick_magic(delta: float) -> void:
	if magic >= max_magic:
		return
	_magic_idle += delta
	if _magic_idle < MAGIC_REGEN_DELAY:
		return
	magic = minf(max_magic, magic + MAGIC_REGEN_RATE * delta)
	magic_changed.emit(magic, max_magic)


func _tick_cooldowns(delta: float) -> void:
	for id: StringName in _cooldowns.keys():
		var remaining: float = _cooldowns[id] - delta
		if remaining <= 0.0:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = remaining


func cooldown_fraction(ability: AbilityData) -> float:
	if ability == null or ability.cooldown <= 0.0:
		return 0.0
	return clampf(float(_cooldowns.get(ability.id, 0.0)) / ability.cooldown, 0.0, 1.0)


func add_gold(amount: int) -> void:
	gold_collected += amount
	GameState.gold += amount


## Opens the nearest chest in reach. Deliberately a separate button from attack: swinging a
## sword at a chest you meant to open, or opening a chest while a skeleton closes in, are both
## worse than one extra key.
func _interact() -> void:
	var best: TreasureChest = null
	var best_distance := TreasureChest.INTERACT_RADIUS
	for node in get_tree().get_nodes_in_group("chests"):
		var chest := node as TreasureChest
		if chest == null or chest.is_open:
			continue
		var distance := global_position.distance_to(chest.global_position)
		if distance < best_distance:
			best_distance = distance
			best = chest
	if best != null:
		best.try_open(self)


# --- reactions --------------------------------------------------------------------------------

func _on_damaged(_amount: int, _from: Vector3) -> void:
	if not is_dead and archetype != null and visual != null:
		visual.play_action(archetype.hit_anim, 1.4)


func _on_died() -> void:
	if archetype != null and visual != null:
		visual.play_death(archetype.death_anim)
	## Death is a setback, not an elimination: a downed player returns after a beat, because a
	## friend watching the other three play is a friend who has stopped playing.
	get_tree().create_timer(4.0).timeout.connect(_revive)


func _revive() -> void:
	if not is_dead:
		return
	is_dead = false
	health = maxi(POINTS_PER_HEART, max_health / 2)
	health_changed.emit(health, max_health)
	magic = max_magic * 0.5
	magic_changed.emit(magic, max_magic)
	visual.stop_action()
	visual.set_loop(archetype.idle_anim)
	respawn_at(_safe_position)


func _update_animation() -> void:
	if visual == null or archetype == null or is_dead:
		return
	if not is_on_floor():
		visual.set_loop(archetype.jump_anim)
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	visual.set_loop(archetype.run_anim if planar > 1.0 else archetype.idle_anim)
