class_name FeatureFlags extends RefCounted

## Coarse on/off switches: flip one const to turn a whole system off without
## unpicking the code that implements it. Add the game's own flags below.

## The achievement framework: definitions in data/achievements/achievements.tres,
## evaluation in autoloads/achievement_service.gd, and the main menu's
## Achievements panel. Independent of Steam, so Web/mobile builds keep
## achievements with no Steam anywhere in the picture.
const ACHIEVEMENTS := true

## Steam platform integration: API init, achievement pushes, the overlay. Off =
## achievements still track locally and queue for a later Steam-enabled boot.
## Also effectively off whenever the GodotSteam extension isn't loaded. See
## autoloads/steam_manager.gd.
const STEAM_INTEGRATION := true

## The in-game bug report form on the report_bug hotkey (F7), posted through the
## Cloudflare Worker in tools/feedback_worker. Also off while
## ProjectConfig.FEEDBACK_GAME_KEY is still the placeholder. See
## autoloads/feedback_reporter.gd.
const BUG_REPORTS := true
