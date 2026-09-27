# Xiaomi 17 Pro Automation

[中文](README.md) · [Français](README.fr.md)

A KSU / Magisk root automation module for **Xiaomi 17 Pro / HyperOS 4**. It provides multi-profile scheduling, record-and-replay of any app, and keeps the built-in ICBC daily watering task.

It works by **direct root control** (`screencap` / `getevent` / `sendevent`) — no accessibility service, no Xposed, no hooks and no `input` injection.

> ⚠️ **Disclaimer**
> - This project is for technical study and research only. It has no connection to, and no authorisation from, Industrial and Commercial Bank of China.
> - Automated operation may violate an app's terms of service or local laws. Assess the risks yourself.
> - You bear all consequences of using this project. The author and contributors accept no liability.
> - Do not use it commercially, for bulk operations or for any profit-making purpose. If the relevant function is prohibited by an app or a carrier, stop using it and uninstall immediately.
> - It touches account features; risks are yours. Not recommended for important or real-name accounts.

## Features

- A built-in "ICBC daily watering" profile runs every day at `07:30` by default; it can also be triggered manually, and on the first ICBC launch of the day.
- Independent scheduling per profile: each task has its own time, enable flag, target package and action sequence.
- App-bound recording: recording starts once you switch to the target app, pauses when you leave and resumes when you come back; it also pauses on a locked or dark screen.
- Bare recording: with an empty package name it records from a lit screen, filtering system edge and bottom swipes by rule.
- On replay it handles waking the screen, unlocking, launching the target app and confirming the foreground, then restores rotation lock, stay-awake and the screen timeout.
- **Background cleanup after each run**: the target app is closed with `am force-stop` when the task ends, so it stops holding memory and the next task starts clean. One global switch, plus a per-task override.
- **Multilingual WebUI**: Chinese / English / Français / Русский, switchable from the top right; the choice is remembered.
- **WebUI updates with the module**: assets carry a version tag and caching is disabled, so you never have to uninstall and reinstall.
- The PIN is written only to the on-device config and never appears in the status output, the log or the source.

## Installation

1. Download `xiaomi-17-pro-automation-v0.10.0.zip` from Releases.
2. Flash that zip in KernelSU / Magisk.
3. Reboot, open the module WebUI and set the unlock method and PIN as needed.
4. For a recorded task, fill in the target app package name; switch to that app and press "Start recording", then press "Stop recording" when you are done.

### Upgrading from an older version

Just flash the new zip over the old one. To keep your existing configuration and tasks, the internal compatibility identifiers are unchanged:

```text
id=icbc_daily_water
/data/adb/modules/icbc_daily_water
/data/adb/icbc_water
```

Do not delete these directories or change the module ID; your configuration, profiles, PIN and recorded actions are carried over.

> If the WebUI still looks stale after upgrading, check the version in the top right — it must read `v0.10.0`. If it does not, the old package was installed.

## Usage

### Built-in task

The "ICBC daily watering" task is created on first install. It is a script profile that calls the built-in `water.sh`, which performs the ICBC home-page check, taps the task entry and runs the watering flow. The default schedule is `07:30` and can be changed in the WebUI.

### Recorded tasks

1. Add a task in the WebUI with a name and a target package name; leaving the package empty records the whole lit screen.
2. Press "Start recording" on the task, then switch to the target app.
3. Come back to the WebUI and press "Stop recording".
4. Check the action count, then run it now or wait for its schedule.

To capture edge-back gestures, fill in the target package name: the app-bound mode keeps edge swipes and discards actions taken in other apps.

### Background cleanup

"⚙️ Other → Clean up the app in the background afterwards" controls whether the target app is closed after every task. It is **on by default**. It only reclaims the process; it never clears data, accounts or the login state.

Two exceptions to keep in mind:

- **Chained tasks in the same app**: if you split one app's flow into several tasks (for example a first half and a second half), closing the app after the first one drops the next task back at the home screen. Set the tasks *in the middle* of the chain to "Off (keep in background)" and keep cleanup only on the last task of the chain.
- **Bare tasks** (no package name) have no well-defined target app, so the service cannot know which process to close. These are not cleaned up automatically; the task card says so.

"Water when ICBC is opened for the first time each day" runs on a separate path: you are holding the phone and opened ICBC yourself, so the module will not kick you out of the app.

### Lock screen and power

Before a task the module tries to wake and unlock the screen, either by blind PIN entry or by swiping up. It keeps the screen awake while running and restores the original rotation lock, `screen_off_timeout` and stay-awake setting afterwards. If the lock state cannot be confirmed it aborts safely instead of injecting blind coordinates.

### Language

The dropdown in the top right switches between Chinese / English / Français / Русский; the choice is stored in the browser's local storage. Log lines, commands and package names are technical content and stay untranslated.

## Devices and calibration

The default target device is the Xiaomi 17 Pro. The module discovers the touch device through `getevent -p` and converts coordinates from the touch axis range. `water.sh` holds the target display size and the ICBC flow coordinates; recalibrate before switching devices.

> Every model other than the Xiaomi 17 Pro is currently **under testing**: resolution, DPI and system bar heights all affect the UI layout, so changing the resolution alone is not enough to make the ICBC flow work. Do not try it on a daily-driver phone.

The pixel probes and coordinates of the ICBC flow live in the config block at the top of `water.sh`. A helper script is included to inspect pixel colours in a screenshot:

```sh
python3 tools/px.py screen.png 216,778 518,780 746,748
```

## Files

| File | Purpose |
|---|---|
| `module.prop` | Module metadata (display name, version, author) |
| `service.sh` | Multi-profile daemon and scheduler, wake/unlock/power restore, post-run cleanup |
| `water.sh` | Built-in ICBC watering business logic |
| `record.sh` | Touch event recording core |
| `replay.sh` | Recorded action replay core |
| `webctl.sh` | WebUI root command interface |
| `webroot/` | KernelSU WebUI page, scripts and translation dictionaries |
| `sched.conf` | Default config template (the live config lives in `/data/adb/icbc_water/`) |
| `customize.sh` | Install/upgrade flow, permissions and WebUI integrity check |
| `tools/px.py` | Screenshot pixel calibration helper |
| `tools/run_once.sh` | Run the built-in ICBC flow manually |
| `tools/build_zip.sh` | Produce the flashable zip from the repository |

## Building from source

Run this in the repository root:

```sh
bash tools/build_zip.sh
```

The script writes the following file into the parent directory:

```text
xiaomi-17-pro-automation-v0.10.0.zip
```

## License

[MIT](LICENSE) License.
