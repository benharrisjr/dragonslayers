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
	var attacker_height := attacker.hit_height if attacker != null else 1.7
	for candidate: Combatant in _candidates(tree, attacker):
		var offset := candidate.hit_centre() - (origin + Vector3.UP * attacker_height * 0.5)
		## Vertical tolerance scaled to how tall the pair actually are: a monster on the plateau
		## above should not be swingable, but a dragon's mid-body is metres above a player's and
		## must still be in reach.
		if absf(offset.y) > (attacker_height + candidate.hit_height) * 0.5 + 0.6:
			continue
		offset.y = 0.0
		var distance := offset.length()
		## Reach is to the target's surface, not its centre. Measuring to the centre means a
		## wide target has to be stood inside before a swing lands, which is impossible when it
		## also has a collision capsule.
		if distance > ability.range + candidate.hit_radius or distance < 0.0001:
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
		if candidate.hit_centre().distance_to(origin) <= radius + candidate.hit_radius:
			out.append(candidate)
	return out


## Allies in range, for heals and party buffs. Includes the caster.
static func ally_targets(tree: SceneTree, caster: Combatant, radius: float) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var group := "players" if caster.faction == Combatant.Faction.PLAYER else "monsters"
	for node in tree.get_nodes_in_group(group):
		var ally := node as Combatant
		if ally != null and not ally.is_dead \
				and ally.hit_centre().distance_to(caster.hit_centre()) <= radius + ally.hit_radius:
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
		## Faction is checked as well as the group. The group is an index for speed; hostility
		## is the actual rule, and trusting the index alone is what turned a mis-filed player
		## into a legal target for its own friends.
		if candidate != null and candidate != attacker and attacker.is_hostile_to(candidate):
			out.append(candidate)
	return out
