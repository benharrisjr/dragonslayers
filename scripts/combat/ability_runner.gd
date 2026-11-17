class_name AbilityRunner
extends RefCounted

## Host-side execution of an ability: wait out the wind-up, then make it happen.
##
## The wind-up delay is why this exists as a step of its own rather than resolving inline. An
## attack that damages on the frame the button was pressed reads as unfair in both directions --
## players get hit by monsters that have not swung yet, and their own swings connect before the
## sword has moved. Waiting the animation's wind-up makes the hit land when it looks like it does.

static func execute(caster: Combatant, ability: AbilityData, origin: Vector3,
		aim: Vector3) -> void:
	if caster == null or not is_instance_valid(caster) or ability == null:
		return
	if ability.wind_up > 0.0:
		await caster.get_tree().create_timer(ability.wind_up).timeout
	if not is_instance_valid(caster) or caster.is_dead:
		return

	## Re-read the caster's position after the wind-up: it may have been knocked halfway across
	## the chunk mid-swing, and resolving from where it started would be a ghost hit.
	var current_origin := caster.global_position
	match ability.shape:
		AbilityData.Shape.MELEE_ARC:
			var facing := aim if aim.length_squared() > 0.001 else caster.facing()
			var targets := CombatResolver.arc_targets(caster.get_tree(), caster, current_origin,
					facing, ability)
			CombatResolver.apply(ability, caster, targets, current_origin)
		AbilityData.Shape.PROJECTILE:
			caster.fire_projectile(ability, current_origin, aim)
		AbilityData.Shape.NOVA:
			var caught := CombatResolver.radius_targets(caster.get_tree(), caster,
					current_origin, ability.radius)
			CombatResolver.apply(ability, caster, caught, current_origin)
		AbilityData.Shape.SELF:
			if ability.heal > 0:
				for ally in CombatResolver.ally_targets(caster.get_tree(), caster, ability.radius):
					ally.heal(ability.heal)
