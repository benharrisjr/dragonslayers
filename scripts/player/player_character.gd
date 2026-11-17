class_name PlayerCharacter
extends Combatant

## A playable adventurer. One of these exists per (peer, split-screen slot) pair.
##
## There are no classes. What a player can do is the gear they carry (ItemDB): the sword, shield
## and hookshot go on hotkeys, the feather is what allows jumping and the boots are what allow
## dashing. Everything but the sword and shield is dropped on death.
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
## Something about what this player holds or has on their hotkeys changed.
signal gear_changed
signal inventory_toggled(open: bool)

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

## A raised shield stops anything arriving within 60 degrees of straight ahead.
const BLOCK_ARC_DOT := 0.5
## A blocked hit still shoves, just not far: enough to feel, not enough to clear a ledge.
const BLOCK_KNOCKBACK := 0.33
## Walking speed behind a raised shield, as a fraction of normal.
const BLOCK_SPEED := 0.35
## The boots' dash: a short burst, quick to come back, that covers about 3.6 m.
const DASH_SPEED := 20.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 0.9
const HOOK_COOLDOWN := 0.8
const HOOK_HEIGHT := 0.5
## The lantern drops its fire a stride ahead, and takes a moment before it can drop another.
const LANTERN_REACH := 1.8
const LANTERN_RADIUS := 2.0
const LANTERN_COOLDOWN := 2.5
const LANTERN_ANIM := "general/Use_Item"
## How long a player set alight by a friend's lantern runs about, how often the panic changes
## its mind about which way to run, and how much faster than a walk it is.
const ALIGHT_TIME := 3.0
const PANIC_TURN_INTERVAL := 0.35
const PANIC_SPEED := 1.35
const BLOCK_ANIM := "melee/Melee_Blocking"
const DASH_ANIM := "moveadv/Dodge_Forward"
const HOOK_ANIM := "general/Throw"

@export var pid: int = 0

var archetype: ArchetypeData
var visual: CharacterVisual
var targeting: TargetingService
var camera_yaw: float = 0.0

var magic: float = 100.0
var max_magic: float = 100.0
var gold_collected: int = 0

## Items held, in the order they were picked up.
var gear: Array[StringName] = []
## Which item is on each hotkey; &"" for an empty one.
var hotkeys: Array[StringName] = [&"", &"", &""]
## Shield raised. Published to the other peers with position, because the host is the one that
## has to know about it when a hit lands.
var blocking: bool = false
## This player's gear panel is up. Only they stop moving; the rest of the party plays on.
var inventory_open: bool = false
## The hookshot while it is out, on every peer.
var hook: Hookshot

var _input: PlayerInput
var _is_local: bool = false
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _magic_idle: float = 0.0
var _cooldowns: Dictionary = {}
var _was_on_floor: bool = true
var _safe_position: Vector3 = Vector3.ZERO
var _safe_timer: float = 0.0
var _dash_time: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _hook_cooldown: float = 0.0
var _lantern_cooldown: float = 0.0
## Seconds left on fire. Set on every peer, so everyone sees the flames.
var _alight_left: float = 0.0
var _panic_direction: Vector3 = Vector3.ZERO
var _panic_turn: float = 0.0
var _flames: MeshInstance3D


func configure(player_pid: int, data: ArchetypeData) -> void:
	pid = player_pid
	archetype = data
	faction = Faction.PLAYER
	max_health = data.max_hearts * POINTS_PER_HEART
	health = max_health
	max_magic = data.max_magic
	magic = max_magic
	knockback_resistance = data.knockback_resistance
	## Matches the capsule the body is given in GameWorld._spawn_player.
	hit_radius = 0.42
	hit_height = 1.6
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

	for item in ItemDB.STARTING:
		add_item(item)

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
		clamp_speed()
		move_and_slide()
		return

	_read_actions()
	_move(delta)
	_check_fall(delta)
	_update_animation()


func _read_actions() -> void:
	if _input == null:
		return
	if is_alight():
		## On fire: no gear, no panel, no plan.
		blocking = false
		set_inventory_open(false)
		return
	if _input.inventory_pressed():
		set_inventory_open(not inventory_open)
	if inventory_open:
		## The gear panel reads the same buttons to assign items, so they do nothing else.
		blocking = false
		return
	if _input.target_next_pressed():
		targeting.cycle(1)
	if _input.target_prev_pressed():
		targeting.cycle(-1)
	if _input.interact_pressed():
		_interact()

	var shield_held := false
	for slot in ItemDB.HOTKEY_COUNT:
		var item := hotkeys[slot]
		if item == &"" or not has_item(item):
			continue
		match item:
			ItemDB.SWORD:
				if _input.item_pressed(slot):
					use_ability(-1)
			ItemDB.SHIELD:
				shield_held = shield_held or _input.item_held(slot)
			ItemDB.HOOKSHOT:
				if _input.item_pressed(slot):
					fire_hookshot()
			ItemDB.LANTERN:
				if _input.item_pressed(slot):
					use_lantern()
	blocking = shield_held and is_on_floor() and hook == null and knockback_time <= 0.0 \
			and not visual.is_acting()
	if _input.dash_pressed():
		dash()


func _move(delta: float) -> void:
	## On the end of a latched hookshot the line decides where the body goes, not the stick.
	if hook != null and hook.is_reeling_owner():
		_move_on_hook()
		return

	var wish := Vector2.ZERO
	if _input != null and knockback_time <= 0.0 and not visual.is_acting() \
			and not inventory_open and hook == null:
		wish = _input.move_vector()
	## Movement is camera-relative, and each split-screen player has their own camera, so the
	## yaw comes from that player's pane rather than from a single world camera.
	var basis := Basis(Vector3.UP, camera_yaw)
	var direction := (basis * Vector3(wish.x, 0.0, -wish.y))
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	if is_alight() and knockback_time <= 0.0:
		## The stick is ignored. The body picks a direction, runs, and picks another.
		_panic_turn -= delta
		if _panic_turn <= 0.0:
			_panic_turn = PANIC_TURN_INTERVAL
			var heading := randf() * TAU
			_panic_direction = Vector3(cos(heading), 0.0, sin(heading))
		direction = _panic_direction

	var on_floor := is_on_floor()
	_coyote = COYOTE_TIME if on_floor else maxf(0.0, _coyote - delta)
	## No feather, no jump. Ramps are how everyone else gets up a cliff.
	if _input != null and _input.jump_pressed() and has_item(ItemDB.FEATHER) \
			and not inventory_open:
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

	var target_speed := archetype.move_speed * (BLOCK_SPEED if blocking else 1.0)
	if is_alight():
		target_speed *= PANIC_SPEED
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

	if _dash_time > 0.0:
		## A dash overrides steering for its short life: it goes where it was aimed.
		_dash_time -= delta
		velocity.x = _dash_direction.x * DASH_SPEED
		velocity.z = _dash_direction.z * DASH_SPEED

	velocity.y -= gravity() * delta
	clamp_speed()
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
	## A teleport, not a move: without this the body is drawn sliding across the map for a tick.
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	knockback_time = 0.0
	respawned.emit()


# --- abilities ------------------------------------------------------------------------------

## `index` of -1 is the free weapon attack; 0+ indexes the archetype's ability list.
func use_ability(index: int) -> bool:
	if is_dead or archetype == null or visual.is_acting() or is_alight():
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
		## Projectiles keep the vertical component so they fly at the target rather than past
		## its ankles -- which matters for anything tall, or standing on the plateau above.
		## Melee stays flat, since the arc test flattens it anyway.
		var offset := chosen.hit_centre() - hit_centre()
		if ability.shape != AbilityData.Shape.PROJECTILE:
			offset.y = 0.0
		if offset.length_squared() > 0.001:
			return offset.normalized()
	return facing()


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
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	_hook_cooldown = maxf(0.0, _hook_cooldown - delta)
	_lantern_cooldown = maxf(0.0, _lantern_cooldown - delta)
	if _alight_left > 0.0:
		_alight_left = maxf(0.0, _alight_left - delta)
		if _alight_left <= 0.0 and _flames != null:
			_flames.visible = false
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

func _on_damaged(amount: int, _from: Vector3) -> void:
	## A blocked hit arrives as zero damage. Flinching would lower the shield -- a flinch is an
	## action, and actions end a block -- so a block simply holds.
	if amount <= 0:
		return
	if not is_dead and archetype != null and visual != null:
		visual.play_action(archetype.hit_anim, 1.4)


func _on_died() -> void:
	if archetype != null and visual != null:
		visual.play_death(archetype.death_anim)
	blocking = false
	set_inventory_open(false)
	_alight_left = 0.0
	if _flames != null:
		_flames.visible = false
	if hook != null:
		hook.retract()
	## Everything but the sword and shield falls where the player fell. This runs on every
	## peer, so they all agree the gear is gone; only the host puts it on the ground.
	var dropped := _strip_droppable_gear()
	if NetworkManager.is_host() and not dropped.is_empty():
		_drop_on_ground(dropped)
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
	if _flames != null and _flames.visible:
		var flicker := 0.85 + 0.25 * sin(Time.get_ticks_msec() * 0.03)
		_flames.scale = Vector3(flicker, 0.9 + 0.3 * sin(Time.get_ticks_msec() * 0.021), flicker)
	if visual == null or archetype == null or is_dead:
		return
	if not is_on_floor():
		visual.set_loop(archetype.jump_anim)
		return
	if blocking:
		visual.set_loop(BLOCK_ANIM)
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	visual.set_loop(archetype.run_anim if planar > 1.0 else archetype.idle_anim)


# --- gear -------------------------------------------------------------------------------------

func has_item(id: StringName) -> bool:
	return gear.has(id)


## Takes an item. Returns false if the player already holds one -- nobody carries two feathers,
## which is what leaves the second one on the ground for a friend.
func add_item(id: StringName) -> bool:
	if not ItemDB.exists(id) or gear.has(id):
		return false
	gear.append(id)
	## Anything that needs a button goes on the first free hotkey, so picking up the hookshot
	## is usable straight away without a trip through the gear panel.
	if not ItemDB.is_passive(id) and not hotkeys.has(id):
		var free := hotkeys.find(&"")
		if free >= 0:
			hotkeys[free] = id
	gear_changed.emit()
	return true


func remove_item(id: StringName) -> void:
	if not gear.has(id):
		return
	gear.erase(id)
	for slot in hotkeys.size():
		if hotkeys[slot] == id:
			hotkeys[slot] = &""
	gear_changed.emit()


## Puts a held item on a hotkey. If it was on another one the two swap, so an item is never on
## two buttons and a button is never silently emptied.
func assign_hotkey(slot: int, id: StringName) -> bool:
	if slot < 0 or slot >= hotkeys.size() or not has_item(id) or ItemDB.is_passive(id):
		return false
	var previous := hotkeys.find(id)
	if previous == slot:
		return true
	if previous >= 0:
		hotkeys[previous] = hotkeys[slot]
	hotkeys[slot] = id
	gear_changed.emit()
	return true


func hotkey_of(id: StringName) -> int:
	return hotkeys.find(id)


func set_inventory_open(open: bool) -> void:
	if inventory_open == open:
		return
	inventory_open = open
	inventory_toggled.emit(open)


## Whether an item could be used this instant -- what the HUD dims a hotkey by.
func item_ready(id: StringName) -> bool:
	match id:
		ItemDB.SWORD:
			return cooldown_fraction(archetype.basic_attack) <= 0.0
		ItemDB.HOOKSHOT:
			return hook == null and _hook_cooldown <= 0.0
		ItemDB.BOOTS:
			return _dash_cooldown <= 0.0
		ItemDB.LANTERN:
			return _lantern_cooldown <= 0.0
	return true


func _strip_droppable_gear() -> Array[StringName]:
	var dropped: Array[StringName] = []
	for id in gear.duplicate():
		if ItemDB.is_droppable(id):
			dropped.append(id)
			remove_item(id)
	return dropped


## Host only. Lays dropped gear in a ring where the player last stood on solid ground -- not
## where the body ended up, which may be the bottom of the sea or of a pit.
func _drop_on_ground(items: Array[StringName]) -> void:
	var at := global_position
	if not is_on_floor() and at.y < _safe_position.y - 1.0:
		at = _safe_position
	var chunk := Chunk.containing(get_tree(), at)
	if chunk == null:
		return
	for index in items.size():
		var angle := TAU * float(index) / float(items.size())
		chunk.drop_item(items[index], at + Vector3(cos(angle), 0.6, sin(angle)) * 1.3, pid)


# --- shield -----------------------------------------------------------------------------------

## The host decides every hit, so the block is applied here, on the host, before the hit is
## broadcast: damage from the front is cancelled outright and the shove is cut to a third.
func take_damage(amount: int, from_position: Vector3, knockback: float,
		knockback_lift: float) -> void:
	if blocking and blocks_from(from_position):
		amount = 0
		knockback *= BLOCK_KNOCKBACK
	super.take_damage(amount, from_position, knockback, knockback_lift)


## Whether something at `from_position` is inside the arc the shield covers.
func blocks_from(from_position: Vector3) -> bool:
	var toward := from_position - global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		return false
	return facing().dot(toward.normalized()) >= BLOCK_ARC_DOT


# --- boots ------------------------------------------------------------------------------------

func dash() -> bool:
	if not has_item(ItemDB.BOOTS) or _dash_cooldown > 0.0 or is_dead or hook != null \
			or is_alight() \
			or knockback_time > 0.0 or visual.is_acting() or inventory_open:
		return false
	## Where the stick is pointing, or straight ahead with the stick at rest.
	var direction := facing()
	if _input != null:
		var wish := _input.move_vector()
		if wish.length_squared() > 0.04:
			direction = Basis(Vector3.UP, camera_yaw) * Vector3(wish.x, 0.0, -wish.y)
	direction.y = 0.0
	_dash_direction = direction.normalized()
	_dash_time = DASH_TIME
	_dash_cooldown = DASH_COOLDOWN
	rotation.y = atan2(_dash_direction.x, _dash_direction.z)
	_show_clip_everywhere(DASH_ANIM, 2.4)
	return true


## Plays a one-shot clip on this player's body on every peer.
func _show_clip_everywhere(clip: String, speed: float) -> void:
	visual.play_action(clip, speed)
	if NetworkManager.is_networked():
		_net_show_clip.rpc(clip, speed)


@rpc("authority", "call_remote", "reliable")
func _net_show_clip(clip: String, speed: float) -> void:
	if visual != null:
		visual.play_action(clip, speed)


# --- lantern ----------------------------------------------------------------------------------

## Drops a patch of fire on the ground a stride ahead. It burns monsters and anything flammable
## standing in it -- trees, grass, fences, crates -- and leaves the party alone.
func use_lantern() -> bool:
	if not has_item(ItemDB.LANTERN) or _lantern_cooldown > 0.0 or is_dead or hook != null \
			or is_alight() \
			or knockback_time > 0.0 or visual.is_acting():
		return false
	var ahead := global_position + facing() * LANTERN_REACH
	## Onto the ground, wherever that is: down a step, up a ramp. Nothing to light over a pit.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			ahead + Vector3.UP * 1.5, ahead + Vector3.DOWN * 3.0)
	query.collision_mask = LAYER_WORLD
	var ground := space.intersect_ray(query)
	if ground.is_empty():
		return false
	_lantern_cooldown = LANTERN_COOLDOWN
	if NetworkManager.is_networked():
		_net_drop_fire.rpc(ground["position"])
	else:
		_net_drop_fire(ground["position"])
	return true


## Like the dragon's fire, a patch is lit on every peer and only the host's copy burns anything.
@rpc("authority", "call_local", "reliable")
func _net_drop_fire(at: Vector3) -> void:
	var patch := FirePatch.new()
	GameWorld.effects_root(get_tree()).add_child(patch)
	patch.ignite(at, LANTERN_RADIUS, Faction.MONSTER, true, pid)
	if visual != null:
		visual.play_action(LANTERN_ANIM, 1.8)


# --- on fire ----------------------------------------------------------------------------------

func is_alight() -> bool:
	return _alight_left > 0.0


## Host only: sets this player on fire. It costs no health -- it is a friend's lantern, not the
## dragon -- but for a few seconds the player runs about with no say in where.
func set_alight(seconds: float) -> void:
	if is_dead or not NetworkManager.is_host():
		return
	if NetworkManager.is_networked():
		_net_set_alight.rpc(seconds)
	else:
		_net_set_alight(seconds)


@rpc("any_peer", "call_local", "reliable")
func _net_set_alight(seconds: float) -> void:
	if is_dead or not _sent_by_host():
		return
	_alight_left = seconds
	_panic_turn = 0.0
	if hook != null and _is_local:
		hook_release()
	if _flames == null:
		_flames = _build_flames()
	_flames.visible = true


## A flickering cone of flame over the body, so everyone can see who is on fire.
func _build_flames() -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.5
	cone.radial_segments = 8
	var flames := MeshInstance3D.new()
	flames.mesh = cone
	flames.material_override = FirePatch.shared_material()
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.position.y = 1.3
	add_child(flames)
	return flames


# --- hookshot ---------------------------------------------------------------------------------

## Fires the hookshot at the selected target, or the nearest thing in front, or straight ahead.
func fire_hookshot() -> bool:
	if not has_item(ItemDB.HOOKSHOT) or hook != null or _hook_cooldown > 0.0 or is_dead \
			or is_alight() \
			or knockback_time > 0.0 or visual.is_acting():
		return false
	## Fired from knee height and level, so it catches the low things worth catching -- a chest
	## is only 0.7 m tall -- as well as walls, trees and rocks.
	var origin := global_position + Vector3.UP * HOOK_HEIGHT
	var aim := facing()
	var chosen := targeting.target()
	if chosen == null:
		chosen = targeting.nearest_in_front(Hookshot.RANGE)
	if chosen != null:
		var offset := chosen.hit_centre() - origin
		if offset.length_squared() > 0.001:
			aim = offset.normalized()
	rotation.y = atan2(aim.x, aim.z)
	if NetworkManager.is_networked():
		_net_fire_hook.rpc(origin, aim)
	else:
		_net_fire_hook(origin, aim)
	return true


## The hook is built on every peer from the same origin and aim, like a projectile. Only the
## owner's copy tests for collisions; what it finds is sent on with the calls below.
@rpc("authority", "call_local", "reliable")
func _net_fire_hook(origin: Vector3, aim: Vector3) -> void:
	if hook != null:
		hook.queue_free()
	hook = Hookshot.new()
	GameWorld.effects_root(get_tree()).add_child(hook)
	hook.launch(self, origin, aim)
	if visual != null:
		visual.play_action(HOOK_ANIM, 1.8)


## Owner side: the hook struck something that does not move.
func hook_struck_world(point: Vector3) -> void:
	if NetworkManager.is_networked():
		_net_hook_latched.rpc(point)
	else:
		_net_hook_latched(point)


## Owner side: the hook struck a body. The host does the pulling, as it does all shoving.
func hook_struck_body(body: Combatant) -> void:
	var path := body.get_path()
	if NetworkManager.is_networked():
		_net_hook_caught.rpc(path)
		_request_hook_pull.rpc_id(1, path)
	else:
		_net_hook_caught(path)
		_request_hook_pull(path)


## Owner side: the hook is done, whether it missed, arrived or gave up.
func hook_release() -> void:
	if NetworkManager.is_networked():
		_net_hook_retract.rpc()
	else:
		_net_hook_retract()


@rpc("authority", "call_local", "reliable")
func _net_hook_latched(point: Vector3) -> void:
	if hook != null:
		hook.latch(point)


@rpc("authority", "call_local", "reliable")
func _net_hook_caught(body_path: NodePath) -> void:
	if hook != null:
		hook.catch(get_node_or_null(body_path) as Combatant)


@rpc("authority", "call_local", "reliable")
func _net_hook_retract() -> void:
	if hook != null:
		hook.retract()


@rpc("any_peer", "call_local", "reliable")
func _request_hook_pull(body_path: NodePath) -> void:
	if not NetworkManager.is_host() or is_dead:
		return
	var body := get_node_or_null(body_path) as Combatant
	if body == null or body == self or body.is_dead:
		return
	## Stops a stride short, so the catch arrives in front of the player rather than inside them.
	var offset := global_position - body.global_position
	offset.y = 0.0
	var landing := global_position - offset.normalized() * 1.6
	body.pull_towards(landing, Hookshot.PULL_SPEED)


## Called by the hook itself, on each peer, once it is back in hand.
func hook_finished(finished: Hookshot) -> void:
	if hook == finished:
		hook = null
		_hook_cooldown = HOOK_COOLDOWN


## Owner's movement while latched: straight along the line until it arrives, gives up, or is
## stopped by something in the way.
func _move_on_hook() -> void:
	var line := hook.head - (global_position + Vector3.UP * HOOK_HEIGHT)
	var distance := line.length()
	var stuck := hook.pull_time > 0.25 and get_real_velocity().length() < 2.0
	if distance < Hookshot.ARRIVE_DISTANCE or hook.pull_time > Hookshot.MAX_PULL_TIME or stuck:
		## Let go with a small hop, which is what carries the body over the lip of a ledge it
		## was pulled up to rather than leaving it pressed against the cliff below.
		velocity *= 0.25
		velocity.y = maxf(velocity.y, 6.0)
		hook_release()
	else:
		velocity = line / distance * Hookshot.PULL_SPEED
	move_and_slide()
