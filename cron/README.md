# Nightly build

Make the runner executable:

```sh
chmod +x /path/to/project/cron/nightly_build.sh
```

Add this entry with `crontab -e` to run it at 3:00 AM every night:

```cron
0 3 * * * /path/to/project/cron/nightly_build.sh
```

The runner fetches and fast-forwards `main`, runs `build.sh`, and uses its existing
Google Drive upload. Output is appended to `cron/logs/nightly-build.log`.

The default build is `all` platforms and uploads to the `gdrive` remote and
folder named by `GDRIVE_FOLDER_DEFAULT` in `project.env`. Override these values in
`$HOME/.config/<GAME_NAME>/nightly-build.env`:

```sh
GDRIVE_REMOTE=gdrive
GDRIVE_FOLDER=my-game-builds
NIGHTLY_BUILD_PLATFORMS="mac windows linux-x64 linux-arm64"
IOS_TEAM_ID=XXXXXXXXXX
```

Before enabling the job, configure `rclone` for the selected remote and make
sure Godot export templates and any required signing environment are available
to the cron process.