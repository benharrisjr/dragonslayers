class_name Monster
extends Combatant

## A hostile. Simple chase-and-swing AI, run entirely on the host.
##
## Clients never think for a monster; they receive its transform and its damage events. That is
## the whole reason the world half of the game is host-authoritative -- four machines each
## running their own pathfinding would disagree within seconds, and "which skeleton is actually
## where" is not a question the players should ever have to resolve.
##
## Every monster attack knocks back hard. Monsters are not really trying to kill the party with
## damage; they are trying to push it towards the nearest ledge.

signal loot_dropped(monster: Monster)

enum State { IDLE, CHASE, WIND_UP, RECOVER, DEAD }

## How far it drifts from its spawn before giving up and going home, so a monster lured across
## two chunks does not simply follow forever.
const HOME_TOLERANCE := 1.5
const TURN_SPEED := 7.0

var data: MonsterData
var home_position: Vector3
## The last spot this monster stood on solid ground. Loot is dropped here rather than wherever
## the corpse ended up, because knocking things off ledges is the whole point of the combat and
## it should not quietly cost the party the reward for winning the fight.
var last_grounded_position: Vector3

var visual: CharacterVisual
var state: State = State.IDLE

var _target: Combatant
var _attack_timer: float = 0.0
var _state_timer: float = 0.0
var _attack: AbilityData
var _repath: float = 0.0
## Staggered so 40-odd skeletons do not all run their distance check on the same frame, which
## would turn a cheap test into a periodic spike -- exactly the stutter it is meant to remove.
var _cull_timer: float = randf() * Culling.CHECK_INTERVAL
var _dormant: bool = false
var _casting_shadow: bool = true


func configure(monster_data: MonsterData) -> void:
	data = monster_data
	faction = Faction.MONSTER
	max_health = monster_data.max_health
	health = max_health
	knockback_resistance = monster_data.knockback_resistance
	hit_radius = 0.45 * monster_data.scale
	hit_height = 1.7 * monster_data.scale

	visual = CharacterVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(monster_data.model_path, {}, monster_data.scale)
	visual.set_loop(monster_data.idle_anim)

	_attack = _build_attack()
	home_position = global_position
	last_grounded_position = global_position
	damaged.connect(_on_damaged)
	died.connect(_on_died)


## Monster attacks are AbilityData like everything else, so they route through the same
## CombatResolver as player swings and cannot accidentally skip knockback.
func _build_attack() -> AbilityData:
	var ability := AbilityData.new()
	ability.id = StringName("monster_%s" % data.id)
	ability.display_name = "%s Attack" % data.display_name
	ability.shape = AbilityData.Shape.MELEE_ARC if data.attack_range < 5.0 \
			else AbilityData.Shape.PROJECTILE
	ability.damage = data.damage
	ability.knockback = data.knockback
	ability.knockback_lift = data.knockback_lift
	ability.range = data.attack_range
	ability.arc_degrees = 70.0
	ability.cooldown = data.attack_cooldown
	ability.wind_up = data.wind_up
	ability.animation = data.attack_anim
	ability.projectile_speed = 16.0
	ability.vfx_color = Color(0.65, 0.9, 0.6)
	return ability


func _physics_process(delta: float) -> void:
	_update_activity(delta)
	if _dormant and _at_rest():
		## Nobody is close enough for this monster to matter and it is not going anywhere. It
		## keeps its position and its health and simply stops until somebody comes back.
		##
		## Resting is checked as well as distance because a monster shoved off a ledge can pass
		## out of range while still in mid-air, and skipping its physics then leaves it hanging
		## in the sky -- which is exactly what it did before this condition existed.
		return

	_tick_knockback(delta)
	if is_on_floor():
		last_grounded_position = global_position
	else:
		velocity.y -= gravity() * delta

	## Shoved into a pit. Without this it falls forever: invisible, unkillable, and still on the
	## books as a live monster. It dies where it stood instead, so the party is still paid for
	## the kill -- knocking things off ledges is the intended way to fight, not an exploit.
	if global_position.y < KILL_HEIGHT and not is_dead and NetworkManager.is_host():
		global_position = last_grounded_position
		reset_physics_interpolation()
		velocity = Vector3.ZERO
		take_damage(max_health * 2, last_grounded_position + Vector3.DOWN, 0.0, 0.0)
		return

	if is_dead:
		_slow_to_stop(delta)
		clamp_speed()
		move_and_slide()
		return

	## Still falling or still being thrown, but too far away to be worth thinking about: let the
	## physics finish playing out and skip the AI until it lands.
	if _dormant:
		_slow_to_stop(delta)
		clamp_speed()
		move_and_slide()
		return

	## Clients apply gravity and knockback so a shoved skeleton visibly flies, but the decisions
	## -- who to chase, when to swing -- belong to the host alone.
	if not NetworkManager.is_host():
		_slow_to_stop(delta)
		clamp_speed()
		move_and_slide()
		return

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_state_timer = maxf(0.0, _state_timer - delta)
	_repath = maxf(0.0, _repath - delta)
	if _repath <= 0.0:
		_repath = 0.35
		_target = _pick_target()

	match state:
		State.IDLE:
			_slow_to_stop(delta)
			if _target != null:
				_enter(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.WIND_UP, State.RECOVER:
			_slow_to_stop(delta)
			if _state_timer <= 0.0:
				_enter(State.CHASE if _target != null else State.IDLE)
		State.DEAD:
			_slow_to_stop(delta)

	clamp_speed()
	move_and_slide()
	_update_animation()


## Decides whether this monster is worth simulating and drawing. The animation player is the
## expensive part -- a skinned rig with 54 bone tracks costs the same whether it is on screen or
## 200 m behind the camera -- so it is switched off first and furthest out.
func _update_activity(delta: float) -> void:
	_cull_timer -= delta
	if _cull_timer > 0.0:
		return
	_cull_timer = Culling.CHECK_INTERVAL

	var distance := Culling.distance_to_nearest_player(global_position)
	var active := distance <= Culling.MONSTER_ACTIVE_RANGE
	## A dying monster always finishes its animation, wherever it is: freezing a corpse mid
	## collapse is more noticeable than any saving is worth.
	if is_dead:
		active = true

	if active != not _dormant:
		_dormant = not active
		if visual != null and visual.animation_player != null:
			visual.animation_player.active = active
	## Assigned only on change: every write goes through to the rendering server, and 40-odd
	## redundant writes several times a second is exactly the kind of thing that shows up as a
	## periodic hitch rather than as a lower average.
	var should_draw := distance <= Culling.MONSTER_VISIBLE_RANGE
	if visible != should_draw:
		visible = should_draw

	## Shadows are the other half of what a skinned character costs, and they are the half
	## nobody looks at once it is more than a few strides away.
	var should_shadow := distance <= Culling.MONSTER_SHADOW_RANGE
	if should_shadow != _casting_shadow:
		_casting_shadow = should_shadow
		var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if should_shadow \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for mesh in Culling.meshes_under(self):
			mesh.cast_shadow = mode


## Settled on the ground with nothing acting on it, so nothing would change if it were skipped.
func _at_rest() -> bool:
	return is_on_floor() and knockback_time <= 0.0 and velocity.length_squared() < 0.04


func _chase(delta: float) -> void:
	if _target == null:
		_enter(State.IDLE)
		return
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance <= data.attack_range and _attack_timer <= 0.0:
		_begin_attack()
		return

	## Walk home if the party ran off, rather than standing where it was abandoned.
	var destination := _target.global_position
	if global_position.distance_to(home_position) > data.leash_range:
		destination = home_position
		_target = null

	var direction := destination - global_position
	direction.y = 0.0
	if direction.length() < HOME_TOLERANCE:
		_slow_to_stop(delta)
		return
	direction = direction.normalized()
	var control := 0.2 if knockback_time > 0.0 else 1.0
	velocity.x = move_toward(velocity.x, direction.x * data.move_speed, 30.0 * control * delta)
	velocity.z = move_toward(velocity.z, direction.z * data.move_speed, 30.0 * control * delta)
	_face(direction, delta)


func _begin_attack() -> void:
	_attack_timer = data.attack_cooldown
	_enter(State.WIND_UP)
	_state_timer = data.wind_up + 0.25
	var aim := Vector3.ZERO
	if _target != null:
		aim = _target.global_position - global_position
		aim.y = 0.0
		aim = aim.normalized()
		_face(aim, 1.0)
	if NetworkManager.is_networked():
		_show_attack.rpc()
	visual.play_action(data.attack_anim, 1.2)
	AbilityRunner.execute(self, _attack, global_position, aim)


@rpc("authority", "call_remote", "reliable")
func _show_attack() -> void:
	if visual != null:
		visual.play_action(data.attack_anim, 1.2)


func _pick_target() -> Combatant:
	var best: Combatant = null
	var best_distance := data.aggro_range
	for body in PlayerRegistry.living_bodies():
		var player := body as Combatant
		if player == null:
			continue
		var distance := global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _enter(next: State) -> void:
	state = next


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var wanted := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, wanted, minf(1.0, TURN_SPEED * delta))


func _slow_to_stop(delta: float) -> void:
	var damping := 3.0 if knockback_time > 0.0 else 12.0
	velocity.x = move_toward(velocity.x, 0.0, damping * delta)
	velocity.z = move_toward(velocity.z, 0.0, damping * delta)


func _update_animation() -> void:
	if visual == null or visual.is_acting():
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	visual.set_loop(data.walk_anim if planar > 0.6 else data.idle_anim)


func _on_damaged(_amount: int, _from: Vector3) -> void:
	if not is_dead and visual != null and state != State.WIND_UP:
		visual.play_action(data.hit_anim, 1.5)


func _on_died() -> void:
	_enter(State.DEAD)
	collision_layer = 0
	collision_mask = LAYER_WORLD | LAYER_SCENERY
	if visual != null:
		visual.play_death(data.death_anim)
	if NetworkManager.is_host():
		loot_dropped.emit(self)
	## Long enough for the death animation to finish and for the loot to be noticed coming from
	## somewhere, short enough that a cleared area looks cleared.
	get_tree().create_timer(4.0).timeout.connect(queue_free)
