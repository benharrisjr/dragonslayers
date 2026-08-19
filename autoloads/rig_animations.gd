extends Node

## Serves the shared KayKit Rig_Medium animation set to anything wearing that skeleton.
##
## Every humanoid in the game -- all four adventurers and every skeleton enemy -- skins to the
## same 23-joint rig, and none of the character .glb files contain a single animation. The ~140
## clips live in eight separate library .glb files instead, imported as AnimationLibrary
## resources (see their .import files, which are hand-set to importer="animation_library"
## rather than the default "scene").
##
## Clips are namespaced by pack, so a caller asks for "melee/Melee_1H_Attack_Chop" and the
## AnimationPlayer resolves it. Namespacing rather than flattening keeps the name collisions
## between packs (every pack ships its own "T-Pose") from silently shadowing each other.

const ANIM_ROOT := "res://art/KayKit_Character_Animations_1.1/Animations/gltf/Rig_Medium/"

const LIBRARIES := {
	"general": "Rig_Medium_General.glb",
	"move": "Rig_Medium_MovementBasic.glb",
	"moveadv": "Rig_Medium_MovementAdvanced.glb",
	"melee": "Rig_Medium_CombatMelee.glb",
	"ranged": "Rig_Medium_CombatRanged.glb",
	"special": "Rig_Medium_Special.glb",
	"sim": "Rig_Medium_Simulation.glb",
	"tools": "Rig_Medium_Tools.glb",
}

var _libraries: Dictionary = {}


func _ready() -> void:
	for key: String in LIBRARIES:
		var res: Resource = load(ANIM_ROOT + LIBRARIES[key])
		if res is AnimationLibrary:
			_libraries[key] = res
		else:
			push_error("RigAnimations: %s did not import as an AnimationLibrary" % LIBRARIES[key])


## Hangs every pack off an AnimationPlayer. The libraries are shared resources rather than
## copies -- playback never mutates them, and duplicating 140 clips per character would be
## pure waste with four players and a screen full of skeletons.
func attach(player: AnimationPlayer) -> void:
	for key: String in _libraries:
		if not player.has_animation_library(key):
			player.add_animation_library(key, _libraries[key])


func has_clip(qualified_name: String) -> bool:
	var parts := qualified_name.split("/", false, 1)
	if parts.size() != 2 or not _libraries.has(parts[0]):
		return false
	return (_libraries[parts[0]] as AnimationLibrary).has_animation(StringName(parts[1]))


func clip_length(qualified_name: String) -> float:
	var parts := qualified_name.split("/", false, 1)
	if parts.size() != 2 or not _libraries.has(parts[0]):
		return 0.0
	var lib: AnimationLibrary = _libraries[parts[0]]
	var clip := StringName(parts[1])
	return lib.get_animation(clip).length if lib.has_animation(clip) else 0.0


func library_count() -> int:
	return _libraries.size()
