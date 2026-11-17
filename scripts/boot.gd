extends Control

## Root of the main scene. Normally it just hosts the splash, which hands over to the main menu.
##
## Started from a shell with one of the game's own flags (`-- --solo`, `--playtest`, `--host`,
## `--join=ADDR`, `--perf`, `--netcheck`, `--capture=PATH`) it skips the splash and the menu and
## goes straight to the game scene, which reads the same flags and starts the match. That is
## what keeps the automated playtest and the two-window netcode checks one command long.

const DIRECT_FLAGS: Array[String] = [
	"playtest", "solo", "host", "join", "perf", "netcheck", "capture",
]


func _enter_tree() -> void:
	## `-- --padcheck` plays the whole flow, splash included, on a simulated gamepad.
	if OS.get_cmdline_user_args().has("--padcheck"):
		var check := PadCheck.new()
		check.name = "PadCheck"
		get_tree().root.add_child.call_deferred(check)
		return
	if not _wants_direct_start():
		return
	## Removed before it enters the tree, so the splash never starts animating or loading the
	## menu behind a match nobody asked to see a logo for.
	var splash := get_node_or_null("SplashScreen")
	if splash != null:
		remove_child(splash)
		splash.free()
	SceneManager.change_scene.call_deferred(ProjectConfig.GAME_SCENE, false)


func _wants_direct_start() -> bool:
	for argument in OS.get_cmdline_user_args():
		var key := argument.trim_prefix("--").split("=", false, 1)[0]
		if DIRECT_FLAGS.has(key):
			return true
	return false
