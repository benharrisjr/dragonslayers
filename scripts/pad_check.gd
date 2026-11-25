class_name PadCheck
extends Node

## Plays from the splash to a match and back out using nothing but gamepad events.
##
##   Godot --path . --headless -- --padcheck
##
## Every step is a synthetic joypad event pushed through Input.parse_input_event on device 0,
## so it exercises the same routing a real controller does: the template's pad cursor in the
## menus, the lobby's raw press-to-join, the per-player actions PlayerBindings builds, and the
## Start button that has to get past the blocked cursor during play.

const DEVICE := 0
const STEP_TIMEOUT := 8.0

## `--shots=DIR` saves a screenshot of each screen as it goes (needs a real window).
var _shots_dir := ""
var _passed := 0
var _failed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots_dir = argument.trim_prefix("--shots=")
	_run.call_deferred()


func _run() -> void:
	print("\n--- gamepad run-through")
	## A real window has a real pointer in it; one stray motion event would tell the pad cursor
	## the player had gone back to the mouse.
	PadCursor.ignore_real_mouse = true
	await _wait(0.5)

	## Splash: any button skips it.
	await _tap(JOY_BUTTON_A)
	_expect(await _until(func() -> bool: return _scene_path() == ProjectConfig.MAIN_MENU_SCENE),
			"a pad button skips the splash to the main menu")
	await _wait(1.5)

	await _shot("1_main_menu")
	## Main menu: Play has the hand, A presses it.
	_expect(await _click(_scene().get(&"_play_button"), func() -> bool: return _main() != null),
			"A on the main menu's Play opens the game scene")
	var main := _main()
	if main == null:
		return _finish()
	await _wait(1.0)

	await _shot("2_lobby_mode")
	## The join address can be entered with the pad alone.
	main.lobby.show_step(LobbyScreen.Step.ADDRESS)
	await _wait(0.3)
	var field: LineEdit = main.lobby._address_field
	var before := field.text
	var keypad := field.get_parent().get_child(2) as GridContainer
	_expect(await _click(keypad.get_child(0), func() -> bool: return field.text == before + "1"),
			"A on the number pad types into the address")
	_expect(await _click(keypad.get_child(11), func() -> bool: return field.text == before),
			"Del removes it again")
	await _shot("2b_lobby_address")
	main.lobby.show_step(LobbyScreen.Step.MODE)
	await _wait(0.3)

	## Lobby, mode step: the D-pad walks the hand down the buttons and back.
	var local_button: Control = (main.lobby._first_focus[LobbyScreen.Step.MODE] as PanelButton).get_focus_target()
	PadCursor.point_at(local_button)
	await get_tree().process_frame
	await _tap(JOY_BUTTON_DPAD_DOWN)
	var below := PadCursor.get_snapped()
	_expect(below != null and below != local_button and main.lobby.is_ancestor_of(below),
			"D-pad down moves the hand to the next lobby button")
	await _tap(JOY_BUTTON_DPAD_UP)
	_expect(PadCursor.get_snapped() == local_button, "D-pad up brings it back")

	_expect(await _click(main.lobby._first_focus[LobbyScreen.Step.MODE],
			func() -> bool: return main.lobby._step == LobbyScreen.Step.WORLD),
			"A on Local game opens the world step")
	await _wait(0.3)
	await _shot("2c_lobby_world")
	_expect(await _click(main.lobby._first_focus[LobbyScreen.Step.WORLD],
			func() -> bool: return main.lobby._step == LobbyScreen.Step.SEATS),
			"A on New world opens the seat step")
	_expect(not main.lobby.is_in_group(PadCursor.BLOCK_GROUP), "the seat step keeps the pad cursor")
	await _wait(0.5)

	await _tap(JOY_BUTTON_A)
	_expect(main.lobby.seats() == ([DEVICE] as Array[int]), "A claims player 1 for that pad")
	await _shot("3_lobby_seats")
	await _tap(JOY_BUTTON_B)
	_expect(main.lobby.seats().is_empty(), "B gives the seat back")

	## Nintendo layout: A and B trade places, here as everywhere else.
	_set_nintendo(true)
	await _tap(JOY_BUTTON_B)
	_expect(main.lobby.seats() == ([DEVICE] as Array[int]),
			"Nintendo layout: the right-hand button (its A) claims the seat")
	await _tap(JOY_BUTTON_A)
	_expect(main.lobby.seats().is_empty(), "Nintendo layout: the bottom button (its B) gives it back")
	_set_nintendo(false)

	## The seat is also the character select: up and down choose, A locks in, Start begins.
	await _tap(JOY_BUTTON_A)
	await _wait(0.2)
	_expect(main.lobby.heroes() == ([&"knight"] as Array[StringName]),
			"a new seat starts on the knight")
	var preview: HeroPreview = main.lobby._seat_cards[0]["preview"]
	_expect(preview.visible and preview.hero_id == &"knight"
			and HeroPreview.PASTIMES.has(preview.current_clip()),
			"its card shows the knight in 3D, passing the time")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_expect(main.lobby.heroes()[0] == &"barbarian", "D-pad down steps to the next hero")
	_axis(JOY_AXIS_LEFT_Y, 1.0)
	await _wait(0.1)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _wait(0.1)
	_expect(main.lobby.heroes()[0] == &"thief", "and so does the left stick, one step per push")
	_expect(preview.hero_id == &"thief", "the card's model changes with it")
	await _tap(JOY_BUTTON_DPAD_UP)
	await _tap(JOY_BUTTON_DPAD_UP)
	await _tap(JOY_BUTTON_DPAD_UP)
	_expect(main.lobby.heroes()[0] == &"archer", "up steps back, wrapping round past the knight")
	await _shot("3_lobby_seats")
	var start_button: PanelButton = main.lobby._seat_start
	_expect(start_button.disabled, "Start is off until everyone is ready")
	await _tap(JOY_BUTTON_START)
	await _wait(0.3)
	_expect(not main.in_match(), "and the Start button on the pad does nothing yet")
	await _tap(JOY_BUTTON_A)
	_expect(main.lobby.is_ready(DEVICE) and not start_button.disabled,
			"A locks the hero in, and Start comes on")
	_expect(preview.current_clip() == HeroPreview.CHEER, "the hero cheers")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_expect(main.lobby.heroes()[0] == &"archer", "a locked-in pick does not change")
	await _tap(JOY_BUTTON_B)
	_expect(not main.lobby.is_ready(DEVICE) and main.lobby.seats().size() == 1,
			"B unlocks the pick without giving up the seat")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_expect(main.lobby.heroes()[0] == &"knight", "so it can be changed again")
	await _tap(JOY_BUTTON_A)
	await _shot("3b_lobby_ready")
	await _tap(JOY_BUTTON_START)
	_expect(await _until(func() -> bool: return main.in_match()),
			"with everyone ready, Start begins the match")
	await _wait(2.0)

	var player := PlayerRegistry.body_of(PlayerRegistry.local_pids()[0]) as PlayerCharacter
	if player == null:
		_expect(false, "the pad's player is in the world")
		return _finish()
	_expect(PlayerBindings.devices_of(0) == [DEVICE], "player 1 is bound to the pad alone")
	_expect(player.archetype.id == &"knight" and player.gear.has(ItemDB.SHIELD),
			"and plays the hero picked for them")
	_expect(main.is_in_group(PadCursor.BLOCK_GROUP), "play blocks the pad cursor")

	await _shot("4_match")
	## Left stick moves.
	var from := player.global_position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _wait(0.8)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	var moved := player.global_position - from
	moved.y = 0.0
	_expect(moved.length() > 1.0, "the left stick moves the player (%.1f m)" % moved.length())

	## A jumps -- once the player holds the feather.
	await _wait(0.5)
	var ground := player.global_position.y
	await _tap(JOY_BUTTON_A)
	await _wait(0.3)
	_expect(player.global_position.y < ground + 0.2, "A does nothing without the feather")
	player.add_item(ItemDB.FEATHER)
	await _wait(0.3)
	ground = player.global_position.y
	_button(JOY_BUTTON_A, true)
	var peak := ground
	for _frame in 20:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	_button(JOY_BUTTON_A, false)
	_expect(peak > ground + 0.3, "A jumps with the feather (%.2f m)" % (peak - ground))
	await _wait(1.0)

	## Right stick turns and tilts the camera.
	var camera: PlayerCamera = main.split_screen.cameras[0]
	var yaw := camera.yaw
	var pitch := camera.pitch_offset
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _wait(0.3)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_expect(not is_equal_approx(camera.yaw, yaw), "the right stick turns the camera")
	_expect(camera.pitch_offset < pitch, "the right stick tilts the camera")

	## The three hotkeys, the bumpers, interact and the dash trigger.
	_expect(await _fires(&"p0_item_1", JOY_BUTTON_X), "X is hotkey 1")
	_expect(await _fires(&"p0_item_2", JOY_BUTTON_Y), "Y is hotkey 2")
	_expect(await _fires(&"p0_item_3", JOY_BUTTON_B), "B is hotkey 3")
	_expect(await _fires(&"p0_target_next", JOY_BUTTON_RIGHT_SHOULDER), "RB is next target")
	_expect(await _fires(&"p0_target_prev", JOY_BUTTON_LEFT_SHOULDER), "LB is previous target")
	_expect(await _fires(&"p0_interact", JOY_BUTTON_DPAD_UP), "D-pad up is interact")
	## Nintendo layout leaves play on the same physical buttons and relabels them.
	_set_nintendo(true)
	_expect(await _fires(&"p0_jump", JOY_BUTTON_A), "Nintendo layout: jump stays on the bottom button")
	_expect(await _fires(&"p0_item_1", JOY_BUTTON_X), "Nintendo layout: hotkey 1 stays on the left button")
	_expect(PlayerBindings.hotkey_label(0, 0) == "Y" and PlayerBindings.hotkey_label(0, 2) == "A"
			and PlayerBindings.jump_label() == "B", "Nintendo layout: the HUD prints that pad's letters")
	_set_nintendo(false)
	_expect(PlayerBindings.hotkey_label(0, 0) == "X", "and the Xbox letters come back")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await get_tree().process_frame
	_expect(Input.is_action_pressed(&"p0_dash"), "RT is dash")
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _wait(0.6)

	## Y holds the shield up for as long as it is held.
	_button(JOY_BUTTON_Y, true)
	await _wait(0.3)
	_expect(player.blocking, "holding the shield's button raises it")
	_button(JOY_BUTTON_Y, false)
	await _wait(0.2)
	_expect(not player.blocking, "letting go lowers it")

	## Holding X charges the attack; letting go when it is full spins.
	await _wait(0.8)
	_button(JOY_BUTTON_X, true)
	await _wait(0.15)
	_expect(player.charge_level == 0.0, "a moment's hold shows no charge yet")
	await _wait(1.0)
	_expect(player.charge_level >= 1.0, "holding X charges a spin attack")
	_button(JOY_BUTTON_X, false)
	await _wait(0.1)
	_expect(player.charge_level == 0.0
			and player.cooldown_fraction(player.archetype.charged_attack) > 0.0,
			"letting go of X spins")
	await _wait(0.8)

	## Select opens this player's gear panel -- and no longer the bug report form.
	player.add_item(ItemDB.HOOKSHOT)
	player.add_item(ItemDB.BOOMERANG)
	await _tap(JOY_BUTTON_BACK)
	await _wait(0.3)
	_expect(player.inventory_open, "Select opens the gear panel")
	_expect(not FeedbackReporter.is_open(), "Select does not open the bug report form")
	var panel: InventoryPanel = main.split_screen.huds[0]._inventory
	_expect(panel != null and panel.visible, "the panel is on screen in that player's pane")
	await _shot("5a_gear_panel")
	var from_open := player.global_position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _wait(0.3)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	await _wait(0.1)
	_expect(panel.selected_item() == ItemDB.BOOMERANG, "the stick moves along the items")
	_expect(player.global_position.distance_to(from_open) < 0.3,
			"and does not walk the player about while the panel is open")
	## The hookshot was found first, so it is what is equipped; swap to the boomerang.
	_expect(player.equipped() == ItemDB.HOOKSHOT, "the first usable found is the one equipped")
	await _tap(JOY_BUTTON_A)
	await _wait(0.1)
	_expect(player.equipped() == ItemDB.BOOMERANG, "A equips the highlighted usable")
	panel.select(ItemDB.BOOTS)
	await _tap(JOY_BUTTON_A)
	await _wait(0.1)
	_expect(player.equipped() == ItemDB.BOOMERANG and player.hotkeys[0] == ItemDB.SWORD,
			"static equipment cannot be equipped, and the sword keeps its button")
	_expect(not player.visual.is_acting(), "and uses nothing while the panel is open")
	await _shot("5b_gear_assigned")
	await _tap(JOY_BUTTON_BACK)
	await _wait(0.3)
	_expect(not player.inventory_open, "Select closes the panel")
	await _shot("5c_hud_hotkeys")

	## Holding LT and pushing the right stick brings up the gear wheel; letting the stick go
	## equips the slice it was pointing at.
	_expect(player.equipped() == ItemDB.BOOMERANG, "the boomerang is equipped going into the wheel")
	yaw = camera.yaw
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _wait(0.2)
	_expect(not player.wheel_open, "holding LT alone does not bring up the wheel")
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _wait(0.25)
	_expect(player.wheel_open, "LT and a push of the right stick bring up the gear wheel")
	var wheel: GearWheel = main.split_screen.huds[0]._wheel
	_expect(wheel != null and wheel.visible, "the wheel is on screen in that player's pane")
	_expect(player.wheel_choice == ItemDB.HOOKSHOT, "pushing the stick up points at the top slice")
	## Up and to the right, where the second of six slices sits.
	_axis(JOY_AXIS_RIGHT_X, 0.87)
	_axis(JOY_AXIS_RIGHT_Y, -0.5)
	await _wait(0.2)
	_expect(player.wheel_choice == ItemDB.BOOMERANG, "and up-right points at the next slice round")
	_expect(is_equal_approx(camera.yaw, yaw), "the camera holds still while LT has its stick")
	from_open = player.global_position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _wait(0.4)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_expect(player.global_position.distance_to(from_open) > 0.5,
			"the left stick still walks the player while the wheel is up")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _wait(0.2)
	await _shot("5d_gear_wheel")
	## Springing back: the stick passes through half deflection on its way to centre.
	_axis(JOY_AXIS_RIGHT_Y, -0.35)
	await _wait(0.05)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(player.wheel_open, "the wheel waits a moment after the stick comes to rest")
	await _wait(0.2)
	_expect(not player.wheel_open, "and closes 100 ms later")
	_expect(player.equipped() == ItemDB.HOOKSHOT, "equipping the slice the stick was let go at")
	## A slice for something not found yet changes nothing.
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	_axis(JOY_AXIS_RIGHT_Y, 0.4)
	await _wait(0.2)
	_expect(player.wheel_choice == ItemDB.FAN or not player.has_item(player.wheel_choice),
			"the stick can point at a slice for something not found yet")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _wait(0.3)
	_expect(not player.wheel_open and player.equipped() == ItemDB.HOOKSHOT,
			"letting go there closes the wheel with nothing changed")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _wait(0.2)
	yaw = camera.yaw
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _wait(0.3)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_expect(not player.wheel_open and not is_equal_approx(camera.yaw, yaw),
			"without LT the right stick is the camera again")
	await _wait(0.2)

	## Start pauses, and the players stop reading input while the menu is up.
	await _tap(JOY_BUTTON_START)
	await _wait(0.6)
	_expect(main._menu_open(), "Start opens the pause menu")
	_expect(not PlayerInput.enabled, "the menu takes the controls away from the players")
	_expect(not main.is_in_group(PadCursor.BLOCK_GROUP), "the pad cursor is back for the menu")
	await _shot("5_pause")
	from = player.global_position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _wait(0.5)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	moved = player.global_position - from
	moved.y = 0.0
	_expect(moved.length() < 0.2, "the stick does not move the player behind the menu")

	await _tap(JOY_BUTTON_START)
	_expect(await _until(func() -> bool: return not main._menu_open()), "Start closes it again")
	_expect(PlayerInput.enabled, "the players get their controls back")

	## B backs out of the menu as well.
	await _tap(JOY_BUTTON_START)
	await _wait(0.6)
	await _tap(JOY_BUTTON_B)
	_expect(await _until(func() -> bool: return not main._menu_open()), "B closes the pause menu")

	## Winning: the victory screen has buttons a pad can press.
	var first_world := main.world
	GameState.phase = GameState.Phase.VICTORY
	await _wait(0.5)
	_expect(main.outcome.visible, "victory shows the outcome screen")
	_expect(not main.is_in_group(PadCursor.BLOCK_GROUP), "the pad cursor is back for it")
	await _shot("6_outcome")
	## The match was started from the lobby's New world, so it is a saved world: the button
	## carries on in it rather than rolling a new one.
	_expect(main.outcome._rematch.text == "Keep exploring", "in a saved world it offers to keep exploring")
	_expect(await _click(main.outcome._rematch, func() -> bool:
		return main.world == first_world and not main.outcome.visible \
				and GameState.phase == GameState.Phase.PLAYING),
			"A on Keep exploring goes back to the same world")
	await _wait(1.0)
	_expect(PlayerInput.enabled and main.is_in_group(PadCursor.BLOCK_GROUP),
			"the match hands the controls back to the players")

	## Leaving: the menu's Main Menu button.
	await _tap(JOY_BUTTON_START)
	await _wait(0.6)
	main.options.main_menu_requested.emit()
	_expect(await _until(func() -> bool: return _scene_path() == ProjectConfig.MAIN_MENU_SCENE),
			"Main Menu returns to the main menu")
	_expect(PlayerRegistry.roster.is_empty(), "leaving clears the roster")
	_finish()


func _set_nintendo(on: bool) -> void:
	SaveManager.global_config.nintendo_layout = on
	SaveManager.apply_pad_layout()
	SaveManager.keybinds_changed.emit()


func _finish() -> void:
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _shot(shot_name: String) -> void:
	if _shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)


func _scene() -> Node:
	return SceneManager.get(&"_current_scene") as Node


func _scene_path() -> String:
	var scene := _scene()
	return scene.scene_file_path if scene != null and is_instance_valid(scene) else ""


func _main() -> Main:
	var scene := _scene()
	return scene as Main if scene != null and is_instance_valid(scene) else null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable) -> bool:
	var waited := 0.0
	while waited < STEP_TIMEOUT:
		if condition.call():
			return true
		await get_tree().process_frame
		waited += get_process_delta_time()
	return false


## Puts the pad's hand on a button and presses A. The hand is placed rather than walked there
## because where it first appears depends on where the real mouse was left, which a test run
## in a window cannot know.
func _click(target: Control, condition: Callable) -> bool:
	PadCursor.point_at(target)
	await get_tree().process_frame
	await _tap(JOY_BUTTON_A)
	if OS.get_cmdline_user_args().has("--padcheck-debug"):
		print("DBG snapped=", PadCursor.get_snapped(), " want=", target, " pos=", PadCursor.get_cursor_position(), " focus=", get_window().has_focus(), " mouse=", get_viewport().get_mouse_position(), " mode=", Input.mouse_mode)
	return await _until(condition)


func _button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(index: JoyButton) -> void:
	_button(index, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_button(index, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


## Whether pressing a pad button fires an action this frame.
func _fires(action: StringName, index: JoyButton) -> bool:
	_button(index, true)
	await get_tree().process_frame
	var fired := Input.is_action_pressed(action)
	_button(index, false)
	await get_tree().process_frame
	return fired
