class_name Combatant
extends CharacterBody3D

## Anything that can be hit: the four players, every monster, and the dragon.
##
## All damage in the game funnels through `take_damage`, and every call to it must supply a
## knockback impulse. That is not bookkeeping pedantry -- the map is built out of ledges and
## being shoved off one is a core verb, so an attack that forgot to say how hard it shoves
## would be a design bug, and making the parameter mandatory means it cannot be forgotten.
##
## Damage is always resolved on the host and then broadcast. Clients never decide that they
## were hit, which is what keeps four machines agreeing on who is alive.

signal health_changed(current: int, maximum: int)
signal died
signal damaged(amount: int, from_position: Vector3)
signal healed(amount: int)

enum Faction { PLAYER, MONSTER }

## Health is counted in heart *points*: three hearts of four points each. Storing points
## rather than hearts is what lets the HUD draw honest quarter-hearts and lets a chip-damage
## attack exist at all.
const POINTS_PER_HEART := 4

@export var faction: Faction = Faction.MONSTER
@export var max_health: int = 12
## Scales incoming knockback. A Knight shrugs off a shove that throws a Wizard off a cliff.
@export var knockback_resistance: float = 1.0

var health: int = 12
var is_dead: bool = false

## While this is above zero the body is being thrown and ignores its own movement input.
## Without it, a player could simply walk out of a knockback and the ledges would stop mattering.
var knockback_time: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)


func _ready() -> void:
	health = max_health
	add_to_group("combatants")
	add_to_group("players" if faction == Faction.PLAYER else "monsters")


func is_hostile_to(other: Combatant) -> bool:
	return other != null and not other.is_dead and other.faction != faction


## Host-side entry point for every hit in the game.
func take_damage(amount: int, from_position: Vector3, knockback: float,
		knockback_lift: float) -> void:
	if is_dead or not NetworkManager.is_host():
		return
	var direction := global_position - from_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		## Hit from exactly overhead or from inside the body: shove it the way it faces, so a
		## zero-length vector can never swallow the knockback silently.
		direction = -global_transform.basis.z
	direction = direction.normalized()
	## `call_local` handles the networked case; offline there is no peer to rpc through, so the
	## same function is invoked directly rather than special-casing the whole combat path.
	if NetworkManager.is_networked():
		_net_apply_hit.rpc(amount, from_position, direction, knockback, knockback_lift)
	else:
		_net_apply_hit(amount, from_position, direction, knockback, knockback_lift)


@rpc("authority", "call_local", "reliable")
func _net_apply_hit(amount: int, from_position: Vector3, direction: Vector3,
		knockback: float, knockback_lift: float) -> void:
	if is_dead:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	damaged.emit(amount, from_position)
	apply_knockback(direction, knockback, knockback_lift)
	if health == 0:
		is_dead = true
		died.emit()


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	if NetworkManager.is_networked():
		_net_heal.rpc(amount)
	else:
		_net_heal(amount)


@rpc("authority", "call_local", "reliable")
func _net_heal(amount: int) -> void:
	var before := health
	health = mini(max_health, health + amount)
	if health != before:
		healed.emit(health - before)
		health_changed.emit(health, max_health)


## Applied on every peer so the throw looks the same everywhere, including on the machine that
## owns the body -- the owner obeys knockback it did not ask for, which is the one place the
## host overrides client-authoritative movement.
func apply_knockback(direction: Vector3, force: float, lift: float) -> void:
	if force <= 0.0:
		return
	var scaled := force * knockback_resistance
	velocity.x = direction.x * scaled
	velocity.z = direction.z * scaled
	velocity.y = maxf(velocity.y, scaled * lift)
	## Long enough to clear a ledge edge, short enough that it never feels like a stun lock.
	knockback_time = maxf(knockback_time, 0.28)


func set_max_health(value: int) -> void:
	max_health = maxi(POINTS_PER_HEART, value)
	health = mini(health, max_health)
	health_changed.emit(health, max_health)


func hearts() -> float:
	return float(health) / float(POINTS_PER_HEART)


func max_hearts() -> int:
	return int(ceil(float(max_health) / float(POINTS_PER_HEART)))


func _tick_knockback(delta: float) -> void:
	if knockback_time > 0.0:
		knockback_time = maxf(0.0, knockback_time - delta)


func gravity() -> float:
	return _gravity


## Projectiles are spawned on every peer from identical parameters rather than replicated as
## objects: their motion is plain ballistics, so each machine can run it and arrive at the same
## place, and only the host's copy is allowed to resolve a hit.
func fire_projectile(ability: AbilityData, origin: Vector3, aim: Vector3) -> void:
	if NetworkManager.is_networked():
		_net_spawn_projectile.rpc(String(ability.id), origin, aim)
	else:
		_net_spawn_projectile(String(ability.id), origin, aim)


@rpc("authority", "call_local", "reliable")
func _net_spawn_projectile(ability_id: String, origin: Vector3, aim: Vector3) -> void:
	var ability := AbilityDB.get_ability(StringName(ability_id))
	if ability == null:
		return
	var projectile := Projectile.new()
	get_tree().current_scene.add_child(projectile)
	projectile.launch(self, ability, origin, aim)
