class_name CombatResolver
extends RefCounted

## Turns an AbilityData plus a position and a facing into the list of things it hit.
##
## Shared by players, monsters and the dragon so that a cone is a cone no matter who swung it,
## and so that tuning `arc_degrees` changes every arc attack at once. Host-only: it is called
## from the damage path, and clients never resolve their own hits.


## Everything of the opposing faction inside a cone in front of `origin`.
static func arc_targets(tree: SceneTree, attacker: Combatant, origin: Vector3,
		facing: Vector3, ability: AbilityData) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	if flat_facing.length_squared() < 0.0001:
		return out
	flat_facing = flat_facing.normalized()
	var cos_limit := cos(deg_to_rad(ability.arc_degrees))
	for candidate: Combatant in _candidates(tree, attacker):
		var offset := candidate.global_position - origin
		## Vertical tolerance rather than a sphere: a monster standing on the plateau above you
		## should not be swingable, but one on a slight rise should.
		if absf(offset.y) > 2.2:
			continue
		offset.y = 0.0
		var distance := offset.length()
		if distance > ability.range or distance < 0.0001:
			continue
		if flat_facing.dot(offset / distance) < cos_limit:
			continue
		out.append(candidate)
	return out


## Everything of the opposing faction inside a sphere -- explosions and the dragon's wing flap.
static func radius_targets(tree: SceneTree, attacker: Combatant, origin: Vector3,
		radius: float) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for candidate: Combatant in _candidates(tree, attacker):
		if candidate.global_position.distance_to(origin) <= radius:
			out.append(candidate)
	return out


## Allies in range, for heals and party buffs. Includes the caster.
static func ally_targets(tree: SceneTree, caster: Combatant, radius: float) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var group := "players" if caster.faction == Combatant.Faction.PLAYER else "monsters"
	for node in tree.get_nodes_in_group(group):
		var ally := node as Combatant
		if ally != null and not ally.is_dead \
				and ally.global_position.distance_to(caster.global_position) <= radius:
			out.append(ally)
	return out


static func apply(ability: AbilityData, attacker: Combatant, targets: Array[Combatant],
		origin: Vector3) -> int:
	var hits := 0
	for target in targets:
		target.take_damage(ability.damage, origin, ability.knockback, ability.knockback_lift)
		hits += 1
	return hits


static func _candidates(tree: SceneTree, attacker: Combatant) -> Array:
	var group := "monsters" if attacker.faction == Combatant.Faction.PLAYER else "players"
	var out: Array = []
	for node in tree.get_nodes_in_group(group):
		var candidate := node as Combatant
		if candidate != null and not candidate.is_dead and candidate != attacker:
			out.append(candidate)
	return out
