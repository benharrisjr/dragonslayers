class_name GlobalConfig extends Resource

## Cross-slot config persisted to user://global_config.tres: settings, controls
## and achievements, shared by every save slot. Display settings are NOT here
## (this file syncs through Steam Cloud); see GraphicsQuality's local_settings.cfg.

@export var last_slot: int = 0

## ─── Audio ───────────────────────────────────────────────────────────────────
@export var master_volume: float = 1.0
@export var music_volume: float = 1.0
@export var sfx_volume: float = 1.0
@export var ambience_volume: float = 1.0

## ─── Accessibility ───────────────────────────────────────────────────────────
## The game reads these before shaking or flashing the whole screen.
@export var screen_shake_enabled: bool = true
@export var screen_flash_enabled: bool = true
## Options toggle "Readable Font": text swaps to Atkinson Hyperlegible. See UIFont.
@export var readable_font: bool = false

## ─── Achievements ────────────────────────────────────────────────────────────
## Local mirror of Steam's account-wide achievement state. Cross-slot on purpose:
## a Steam achievement belongs to the account, not to a save file. The
## *conditions* still evaluate against whichever slot is loaded.

## StringName achievement_id -> true.
@export var achievements_unlocked: Dictionary = {}
## StringName achievement_id -> int unix seconds. Display/sort only.
@export var achievement_unlock_times: Dictionary = {}
## Ids earned while Steam was unavailable. Pushed and cleared on the next boot
## where Steam is up. See AchievementService.flush_pending().
@export var achievements_pending_steam: Array[StringName] = []

## ─── Controls ────────────────────────────────────────────────────────────────
## Device-level, so cross-slot. See Keybinds.

## StringName action -> int physical keycode; only actions the player rebound.
@export var keybinds: Dictionary = {}
## StringName action -> int pad input (Keybinds.PAD_*, named by the letter on
## the pad); only actions the player rebound. See Keybinds.rebind_pad.
@export var pad_binds: Dictionary = {}
## Draw key-prompt icons next to hotkeyed controls (Options toggle "Key Hints").
@export var show_key_hints: bool = true
## Options toggle "Click to Drag": a mouse click picks an item up and the next
## click drops it, like the pad's A, instead of holding the button down. See
## DragState.click_holds.
@export var click_to_drag: bool = false
## Gamepad sensitivity multipliers (Options "Pad Cursor" / "Pad Scroll" sliders).
## See PadCursor.
@export var pad_cursor_speed: float = 1.0
@export var pad_scroll_speed: float = 1.0
const PAD_SPEED_MIN := 0.25
const PAD_SPEED_MAX := 3.0
## Options "Nintendo Layout": A is the RIGHT face button (and X/Y swap) instead
## of the Xbox / Steam Deck default where A is the bottom one. See
## PadCursor.confirm_button / SaveManager.apply_pad_layout.
@export var nintendo_layout: bool = false

## ─── Patch notes ─────────────────────────────────────────────────────────────
## The newest build this install has launched (PatchNotes). The main menu pops
## notes newer than this once, then bumps it to the running version.
@export var last_seen_version: String = ""

## The address last typed into the lobby's Join screen, offered again next time.
@export var last_join_address: String = "127.0.0.1"
