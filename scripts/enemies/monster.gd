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

var visual: CharacterVisual
var state: State = State.IDLE

var _target: Combatant
var _attack_timer: float = 0.0
var _state_timer: float = 0.0
var _attack: AbilityData
var _repath: float = 0.0


func configure(monster_data: MonsterData) -> void:
	data = monster_data
	faction = Faction.MONSTER
	max_health = monster_data.max_health
	health = max_health
	knockback_resistance = monster_data.knockback_resistance

	visual = CharacterVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(monster_data.model_path, {}, monster_data.scale)
	visual.set_loop(monster_data.idle_anim)

	_attack = _build_attack()
	home_position = global_position
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
	_tick_knockback(delta)
	if not is_on_floor():
		velocity.y -= gravity() * delta

	if is_dead:
		_slow_to_stop(delta)
		move_and_slide()
		return

	## Clients apply gravity and knockback so a shoved skeleton visibly flies, but the decisions
	## -- who to chase, when to swing -- belong to the host alone.
	if not NetworkManager.is_host():
		_slow_to_stop(delta)
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

	move_and_slide()
	_update_animation()


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
	collision_mask = 1
	if visual != null:
		visual.play_death(data.death_anim)
	if NetworkManager.is_host():
		loot_dropped.emit(self)
	## Long enough for the death animation to finish and for the loot to be noticed coming from
	## somewhere, short enough that a cleared area looks cleared.
	get_tree().create_timer(4.0).timeout.connect(queue_free)
