extends Node3D
var t := 0.0
var shots := 0
func _ready() -> void:
	var a := ArchetypeDB.get_archetype(&"archer")
	var anims := ["ranged/Ranged_Bow_Aiming_Idle", "ranged/Ranged_Bow_Idle", "general/Idle_A"]
	for i in 3:
		var v := CharacterVisual.new()
		add_child(v)
		v.build(a.model_path, a.weapon_paths)
		v.position = Vector3((i - 1) * 1.6, 0, 0)
		v.rotation.y = deg_to_rad(90)
		v.set_loop(anims[i])
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.4, 4.2)
	cam.look_at(Vector3(0, 0.7, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
func _process(d: float) -> void:
	t += d
	if t > 1.5:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		get_tree().quit()
