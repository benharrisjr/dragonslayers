# Steam uploads (SteamPipe)

`steam/steam_upload.sh` exports the desktop builds and uploads them to Steam with
`steamcmd`. It **never sets a build live**: after an upload, pick the build on the
partner site (App Admin → SteamPipe → Builds) and set it live on a branch yourself.

```sh
steam/steam_upload.sh --app demo --preview   # dry run: export + manifests, no upload
steam/steam_upload.sh --app demo             # export + upload
steam/steam_upload.sh --app full --desc "playtest 3"
./build.sh --steam demo                      # normal build.sh run, then Steam upload
```

Staging lives in `builds/steam/<app>/` (gitignored): `content/<depot>/` is exactly
what ships, `scripts/` holds the generated VDFs, `output/` holds steamcmd logs.
Each run wipes and re-exports the content dirs; `--skip-export` re-uploads what's there.

## One-time setup

1. **Install steamcmd:** `brew install --cask steamcmd` (or set `STEAMCMD=/path/to/steamcmd`).
2. **Builder account:** make a separate Steam account, invite it to the Steamworks
   partner group, and give it only *Edit App Metadata* and *Publish App Changes To
   Steam* on the full game and the demo.
3. **Cache the login** (Steam Guard asks for a code once):
   ```sh
   steamcmd +login <builder_account> +quit
   ```
4. **Tell the script who to log in as:**
   ```sh
   export STEAM_BUILDER_USER=<builder_account>
   ```
   (Put it in your shell profile, or in `~/.config/<game>/nightly-build.env` for cron.)
5. **Create depots** for each app (App Admin → SteamPipe → Depots), then
   **Publish** the change so steamcmd can see them:

   | Depot key     | Operating system | Architecture | Launch option executable |
   |---------------|------------------|--------------|--------------------------|
   | `windows`     | Windows          | 64-bit       | `<GAME_NAME>.exe`               |
   | `mac`         | macOS            | —            | `<GAME_NAME>.app`               |
   | `linux_x64`   | Linux + SteamOS  | 64-bit       | `<GAME_NAME>.sh`                |
   | `linux_arm64` | Linux + SteamOS  | arm64        | `<GAME_NAME>.sh`                |

   Add a launch option per OS (Installation → General) pointing at the executable above.
6. **Fill in IDs** in `steam/steam_ids.env`. A blank depot ID is skipped, so you can
   upload a subset (e.g. leave arm64 blank if Steam won't take it).

## Runtime App ID

`autoloads/steam_manager.gd` reads the `SteamAppId` env var that Steam sets at launch,
so the same export initialises as the demo or the full game, whichever one Steam
launched. `APP_ID` there is only the fallback for editor/dev runs (with
`steam_appid.txt`, which the depot VDFs exclude so it never ships).

## Steam Cloud (Auto-Cloud)

Saves sync through **Steam Auto-Cloud**. There's no cloud code in the game: Steam
uploads matching files after the process exits and downloads them before launch.
That's why every quit route has to go through `SaveManager.request_quit()`, which
writes the saves before exit.

Full game: App Admin → Cloud → Steam Cloud Settings:

- Byte quota per user **50 MB**, number of files per user **50**.
- Root path:

  | Root                 | Subdirectory     | Pattern  | OS       | Recursive |
  |----------------------|------------------|----------|----------|-----------|
  | `WinAppDataRoaming`  | `game-template` | `*.tres` | All OSes | No        |

- Root overrides (subdirectory unchanged, only the root changes):

  | Original root       | OS              | New root           |
  |---------------------|-----------------|--------------------|
  | `WinAppDataRoaming` | macOS           | `MacAppSupport`    |
  | `WinAppDataRoaming` | Linux + SteamOS | `LinuxXdgDataHome` |

- **Save**, then **Publish** the app changes. Cloud settings don't take effect until published.

These match Godot's custom user dir (`config/custom_user_dir_name`):
`%APPDATA%\game-template`, `~/Library/Application Support/game-template`,
`~/.local/share/game-template`. Rename that setting and the cloud paths break.

What syncs: `save_slot_N.tres`, `global_config.tres`, and their `.bak.tres` copies.
What stays local (it isn't `*.tres` or isn't at the top level): `logs/`, `dev_sandbox/`,
`window_override.cfg`, and `local_settings.cfg` (graphics tier, fullscreen and
window preset are per machine, so a windowed desktop doesn't follow you onto a Deck).

**Checking it:** the boot log prints `Steam: Cloud: account on, app on, N files`
(`SteamManager.cloud_summary()`). Steam's library page shows the cloud status, and
https://store.steampowered.com/account/remotestorage lists the uploaded files.
