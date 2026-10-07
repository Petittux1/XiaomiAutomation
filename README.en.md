# XiaomiAutomation

[中文](README.md) · [Français](README.fr.md) · [Русский](README.ru.md)

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
- **Pick the weekdays**: both the global schedule and every task carry seven Mon–Sun toggles, so you choose exactly which days fire. A task with nothing ticked follows the global setting; `0` means no scheduled run at all that week (manual runs are unaffected).
- App-bound recording: recording starts once you switch to the target app, pauses when you leave and resumes when you come back; it also pauses on a locked or dark screen.
- **Record-everything mode**: switch the recording mode to "Record everything" and a task with an empty package name keeps recording across app switches, starting from the home screen; replay goes back to the home screen first by default so every run starts from the same place. The original package-bound mode is unchanged.
- Bare recording: with an empty package name it records from a lit screen, filtering system edge and bottom swipes by rule.
- **Pattern unlock**: the unlock method list gains "Pattern" — draw your 4–9 point pattern on the nine-dot pad in the WebUI and the module replays it by dragging before each run. The coordinates are tunable per device, and a "lock → unlock" round-trip test button is there for calibration.
- **The built-in task can be deleted and restored**: the built-in "ICBC daily watering" task can now be removed from the WebUI; once deleted it is not recreated on reboot or upgrade. The "Restore the built-in ICBC task" button rebuilds it on demand.
- On replay it handles waking the screen, unlocking, launching the target app and confirming the foreground, then restores rotation lock, stay-awake and the screen timeout.
- **Background cleanup after each run**: the target app is closed with `am force-stop` when the task ends, so it stops holding memory and the next task starts clean. One global switch, plus a per-task override.
- **Multilingual WebUI**: Chinese / English / Français / Русский, switchable from the top right; the choice is remembered.
- **Multi-device support**: a device-profile layer can adjust screen size, display ID, the lock-screen keypad geometry and the pattern grid per model, so recording, replay and PIN / pattern auto-unlock also work on other HyperOS 4 phones. The Xiaomi 17 Pro measured baseline is kept exactly as it is and is not affected.
- **WebUI updates with the module**: assets carry a version tag, caching is disabled, and the page self-checks whether the document is stale and reloads it — no more uninstalling and reinstalling after an update.
- **Pending-update banner**: right after you flash a new zip and before rebooting, the badge already reads the new version while the code that runs is still the old one — a banner at the top of the WebUI says so explicitly and disappears once the reboot has merged the update.
- **A calmer interface**: a status summary at the top, everything else tucked into collapsible sections so the first screen is no longer one wall of form; expand / collapse everything in one tap.
- The PIN is written only to the on-device config and never appears in the status output, the log or the source.

## Requirements

The module uses only the standard `customize.sh` + `service.sh` entry points: **no Zygisk, no `/system` changes, no metamodule required**. Scheduling, record/replay and PIN auto-unlock therefore all work under Magisk / APatch as well.

The WebUI is **not KernelSU-only** either. APatch has had module WebUI since build 10568, and it does exactly what KernelSU does: it serves `webroot/` from `https://mui.kernelsu.org` and injects a global object with the **same name**, `ksu` — the object this module's `kernelsu.js` talks to. The WebUI therefore works on APatch out of the box, with no code change at all. The same holds for the KernelSU forks (KernelSU Next, SukiSU Ultra).

Magisk is the one exception: upstream Magisk contains **no WebView code whatsoever** — not "unimplemented", it simply has no such capability — so it will not render `webroot/` on its own. To use the WebUI there you need a host app that provides one:

| Feature | KernelSU / forks | APatch | Magisk |
| --- | :---: | :---: | :---: |
| Scheduling / record / replay / PIN auto-unlock | ✅ | ✅ | ✅ |
| Module WebUI | ✅ | ✅ | ✅ with KsuWebUI or MMRL |

**KsuWebUI** and **MMRL** each obtain root on Magisk themselves and then inject that very same `ksu` global into `webroot/`. With either one installed this module needs no changes whatsoever and the WebUI works as-is — this is the ecosystem-wide practice on Magisk. This module ships a `config.json` declaring `"webui-engine": "ksu"`, so MMRL picks its `ksu`-compatible engine instead of its default WebUI X (whose API is not compatible).

> ⚠️ Both routes work, but **KsuWebUI is the sturdier one**: it is a standalone app that gets root itself and depends on no manager. MMRL's `ksu`-compatible engine was marked deprecated in its WebUI X Portable dependency on 2026-03-14 — MMRL currently happens to pin a version from 7 hours before that, so it works for now, and may stop working once MMRL updates. If it ever does, switch to KsuWebUI; this module needs no change.

In any environment you can drive the same backend from a root shell via `webctl.sh`:

```sh
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh status'
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh settime 0730'
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh trigger'      # run the built-in task now
su -c 'WEBUI_PIN=123456 sh /data/adb/modules/icbc_daily_water/webctl.sh setpin'
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh setdays 1234567'   # every day; 135 = Mon/Wed/Fri, 0 = nothing scheduled
su -c 'WEBUI_PATTERN=14789 sh /data/adb/modules/icbc_daily_water/webctl.sh setpattern'  # save the pattern; no value clears it
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh unlock'       # lock → unlock round-trip test (pattern / PIN calibration)
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh profile del icbc'   # delete the built-in ICBC task (no_icbc marker, never rebuilt)
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh profile addicbc'    # restore the built-in ICBC task
```

The PIN is deliberately accepted **only through the `WEBUI_PIN` environment variable**, never as a command-line argument, so the plaintext never shows up in the process list. The pattern works the same way through `WEBUI_PATTERN`: 4–9 distinct digits `1–9`, and an empty value clears the pattern. Type those lines by hand in a local terminal — do not put them in a script, an alias or a chat log.

The full subcommand list is in the file header: `webctl.sh status|setpin|setpattern|settime|setdays|setenable|setmode|setopen|setsleep|setwatch|setcleanup|unlock|trigger[NAME]|restart|log|profiles|profile add/addicbc/del/set|record start/stop/status`.

## Installation

1. Download `XiaomiAutomation-v0.13.2.zip` from Releases.
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

> Flashing alone is not enough: **reboot to activate**. The new package lands in `modules_update` and is merged into `modules` only at boot. In the meantime the version badge already shows the new release while the old code is still running — so the WebUI shows a yellow banner "New version vX is staged — reboot to activate it", and the banner disappearing is the sign that the new code is actually running (the boot log also records `UPDATE pending=vX reboot=needed`).

## Usage

### Built-in task

The "ICBC daily watering" task is created on first install. It is a script profile that calls the built-in `water.sh`, which performs the ICBC home-page check, taps the task entry and runs the watering flow. The default schedule is `07:30` and can be changed in the WebUI.

The built-in task can now be **deleted**: the "Delete" button on its card works like on any other task. Deleting writes the `/data/adb/icbc_water/no_icbc` marker, so neither the boot daemon nor an upgrade recreates it. To bring it back, press "Restore the built-in ICBC task" (or run `webctl.sh profile addicbc`) — it is rebuilt with the current global time and the marker is cleared, so you can delete and restore it as often as you like.

### Choosing the weekdays

- The **global execution days** row in "⚙️ Other" is a Mon–Sun button strip. All seven on means every day (the default); switching a day off stops every scheduled task on that day.
- Each task card has its own **execution days** row, defaulting to "Follow the global setting". Tick it and that task only runs on the days you picked, independent of the global row.
- Values: empty = follow the global setting (global empty = every day), `0` = never scheduled that week, otherwise an ascending `1-7` string (`135` = Mon / Wed / Fri).
- Manual "▶ Run" ignores execution days and always runs; the "first ICBC launch of the day" path only fires on execution days.

### Recorded tasks

1. Add a task in the WebUI with a name, then pick a **recording mode**:
   - **Package-bound recording** (default): fill in the target app package name; recording starts once you switch to that app, pauses when you leave and resumes when you come back.
   - **Record everything**: leave the package empty and switch the mode to "Record everything"; recording starts from the home screen and keeps going across app switches without pausing. Replay returns to the home screen first by default, so every run starts from the same place.
2. Press "Start recording" on the task, then switch to the target app.
3. Come back to the WebUI and press "Stop recording".
4. Check the action count, then run it now or wait for its schedule.

To capture edge-back gestures, use package-bound recording with the target package filled in: that mode keeps edge swipes and discards actions taken in other apps.

### Background cleanup

"⚙️ Other → Clean up the app in the background afterwards" controls whether the target app is closed after every task. It is **on by default**. It only reclaims the process; it never clears data, accounts or the login state.

Two exceptions to keep in mind:

- **Chained tasks in the same app**: if you split one app's flow into several tasks (for example a first half and a second half), closing the app after the first one drops the next task back at the home screen. Set the tasks *in the middle* of the chain to "Off (keep in background)" and keep cleanup only on the last task of the chain.
- **Bare tasks** (no package name) have no well-defined target app, so the service cannot know which process to close. These are not cleaned up automatically; the task card says so.

"Water when ICBC is opened for the first time each day" runs on a separate path: you are holding the phone and opened ICBC yourself, so the module will not kick you out of the app.

### Lock screen and power

Before a task the module tries to wake and unlock the screen, either by blind PIN entry, by replaying your pattern, or by swiping up. It keeps the screen awake while running and restores the original rotation lock, `screen_off_timeout` and stay-awake setting afterwards. If the lock state cannot be confirmed it aborts safely instead of injecting blind coordinates.

**Pattern unlock**: choose "Pattern" as the unlock method, then tap out 4–9 distinct dots on the nine-dot pad in the WebUI (drag to connect them; the "middle dot" Android accepts is filled in automatically) and save. The pattern stays in the on-device config — the interface only ever echoes "set", never the dot order. The pad defaults to coordinates measured on the Xiaomi 17 Pro (its 1220×2656 lock screen); on another phone tune `PAT_X0` / `PAT_Y0` (top-left dot) and `PAT_DX` / `PAT_DY` (spacing) in the "📱 Device profile" card, then press the "lock → unlock test" button: success prints `UNLOCK_OK`, and a miss means nudge the four values and try again. With no pattern set the module falls back to PIN or swipe.

**What the unlock test means when it stops**: the "lock → unlock test" now has two gates — the lock screen must actually appear, and a single swipe must not unlock the phone, before any coordinates are drawn. If the lock screen never appears (the screen was not locked) you get "Test aborted: the lock screen never appeared"; if a single swipe goes straight to the home screen (no pattern/PIN was required) you get "Test aborted: a single swipe went straight to the home screen". Both report `UNLOCK_SKIP` (`nolock` / `nocred`) instead of `UNLOCK_OK` — without those gates a miscalibrated draw still reported success, which sent calibration in the wrong direction.

### Language

The dropdown in the top right switches between Chinese / English / Français / Русский; the choice is stored in the browser's local storage. Log lines, commands and package names are technical content and stay untranslated.

## Devices and calibration

The default target device is the Xiaomi 17 Pro. The module discovers the touch device through `getevent -p` and converts coordinates from the touch axis range.

### Moving to another phone: the device profile

The "📱 Device profile" card affects exactly these things: **screen width/height, display ID, the lock-screen keypad geometry, and the nine-dot pattern grid**. Those are what decide whether recording, replay and PIN / pattern auto-unlock work, and they differ on other phones, so they need their own values.

- **Xiaomi 17 Pro**: the card already holds the measured values — **leave them alone**. Keep "Enable override" off and the module uses the original values from `water.sh` / `sched.conf`.
- **Other HyperOS 4 models** (Xiaomi 17, 17 Pro Max, …): press "🔍 Auto-detect this phone" to fill in `wm size` and `wm density`, check the numbers, then tick "Enable override" and save. The lock-screen keypad cannot be detected reliably, so fill it in by hand — otherwise the 17 Pro values are used and the wrong digits get tapped.
- **Pattern grid**: `PAT_X0` / `PAT_Y0` is the pixel position of the first dot (top-left) and `PAT_DX` / `PAT_DY` the horizontal / vertical spacing (defaults `310 / 1193 / 300 / 300`, measured on the 17 Pro's 1220×2656 lock screen). Verify with the "lock → unlock test" button: if the wrong cells get drawn, adjust these four values and re-test until it prints `UNLOCK_OK`.
- The profile lives in `/data/adb/icbc_water/device.conf`. `DEV_APPLY=0` (the default) means "no override, use the 17 Pro baseline"; only `DEV_APPLY=1` turns the override on. Every value must pass a "unique + digits only" check, so a mistake or a corrupted file can at worst leave the override inactive — it cannot break the watering flow.

> **Every model other than the Xiaomi 17 Pro is "testing".** Resolution, DPI and system bar heights all affect the UI layout, so: **the ICBC flow is not guaranteed to work**; but **recording, replay and PIN auto-unlock work normally**. Do not try it on a daily-driver phone.

### Replaying actions recorded on another phone

Each recorded task has a "No scaling / Scale to screen" dropdown. If a task was recorded on a phone with a **different resolution** and you want to replay it here, pick "Scale to screen" — the module reads the resolution recorded in the file header and converts every coordinate proportionally. The default is "No scaling", so recording and replaying on the same phone is unaffected.

### ICBC flow coordinates

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
| `device.conf` | Device profile template (the live one lives in `/data/adb/icbc_water/device.conf`) |
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
XiaomiAutomation-v0.13.2.zip
```

## License

[MIT](LICENSE) License.
