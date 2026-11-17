class_name ProjectConfig extends RefCounted

## The one file of per-game values. Starting a new game from this template:
## fill these in, then rename the project in project.godot and project.env.

## ─── Steam ───────────────────────────────────────────────────────────────────
## 480 is Valve's public test app (Spacewar); replace with the game's app id.
const STEAM_APP_ID := 480
## The demo's app id, or 0 when there is no demo. FeedbackReporter tags reports
## from it as "demo".
const STEAM_DEMO_APP_ID := 0

## ─── Bug reports ─────────────────────────────────────────────────────────────
## The Cloudflare Worker relay deployed from tools/feedback_worker. This is the
## 9999 deployment; point it at the new game's worker (or reuse this one with a
## new GAME_KEY in its wrangler.toml).
const FEEDBACK_ENDPOINT := "https://feedback-9999.vgmrxgames.workers.dev/report"
## Per-game shared key the worker checks. While it is still the placeholder the
## reporter stays switched off, so a fresh template never posts anywhere.
const FEEDBACK_GAME_KEY_PLACEHOLDER := "CHANGE-ME"
const FEEDBACK_GAME_KEY := FEEDBACK_GAME_KEY_PLACEHOLDER

## ─── Links panel ─────────────────────────────────────────────────────────────
## An empty URL hides its button.
const DISCORD_URL := "https://discord.gg/PDUfaHnCts"
const WEBSITE_URL := "https://vgmrx.com"
## The game's store page, e.g. "https://store.steampowered.com/app/<id>".
const STORE_URL := ""

## ─── Scenes ──────────────────────────────────────────────────────────────────
const MAIN_MENU_SCENE := "res://scenes/menu/main_menu.tscn"
## Where the main menu's Play button goes.
const GAME_SCENE := "res://scenes/main.tscn"

## ─── Saves ───────────────────────────────────────────────────────────────────
const SAVE_SLOT_COUNT := 3
