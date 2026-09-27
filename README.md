# Xiaomi 17 Pro 自动化模块

[English](README.en.md) · [Français](README.fr.md) · [Русский](README.ru.md)

> **English summary** (the full English documentation is in [README.en.md](README.en.md); the rest of this file is the Chinese version, which is the primary one)
>
> **Xiaomi 17 Pro 自动化模块** is a **device-specific** root automation module for **Xiaomi 17 Pro / HyperOS 4**, installable on **KernelSU, Magisk and APatch**. It provides multi-profile scheduling, record/replay of arbitrary app interactions, and a built-in ICBC daily watering task (07:30 by default). Automation is done by **pure root control** (`screencap` / `getevent` / `sendevent`) — no accessibility service, no Xposed, no hooks, no `input` injection.
>
> | Feature | KernelSU | Magisk / APatch |
> | --- | :---: | :---: |
> | Scheduling / record / replay / PIN auto-unlock | ✅ | ✅ |
> | Module WebUI (Chinese / English / Français / Русский) | ✅ | ❌ — the WebUI needs the `kernelsu.js` bridge injected by KernelSU; use `webctl.sh` from a root shell instead |
>
> Other HyperOS 4 phones can be calibrated with the built-in device-profile layer (screen size, display ID, lock-keypad geometry), but the ICBC flow is only tested on the Xiaomi 17 Pro.
>
> **Disclaimer:** this project is for technical study and research only and has no connection to ICBC. Automating an app may violate its terms of service or local law — assess the risk yourself. The authors accept no responsibility for any consequences.
>
> **License:** MIT (redistribution permitted). All scripts ship as plain, unobfuscated source.

面向 **Xiaomi 17 Pro / HyperOS 4** 的 KSU / Magisk root 自动化模块。模块提供多 Profile 定时调度、任意 App 操作录制与回放，并保留内置的工行定时浇水任务。

实现方式为 **纯 root 直控**（`screencap` / `getevent` / `sendevent`），不使用无障碍服务、Xposed、Hook 或 `input` 注入。

> ⚠️ **免责声明**
> - 本项目仅供技术学习与研究，与工商银行官方无任何关联，未经官方授权。
> - 自动操作可能违反 App 用户协议或当地法律法规，请自行了解并评估风险。
> - 使用本项目造成的任何后果由使用者自负，作者与贡献者不承担任何责任。
> - 请勿用于商业用途、批量刷取或任何盈利目的；如相关功能被 App 或运营商禁止，请立即停止使用并卸载。
> - 涉及账户功能，风险自担；不建议在重要或实名账户上使用。

## 特性

- 内置「工行定时浇水」Profile，默认每天 `07:30` 执行；支持手动触发和每日首次打开工行时触发。
- 多 Profile 独立调度：每个任务可设置时间、启用状态、目标包名和操作序列。
- 目标 App 录制模式：切到目标 App 后开始录制，离开自动暂停，回到目标 App 继续；锁屏或暗屏时也会暂停。
- 裸录模式：包名留空时从亮屏画面开始录制；按规则过滤系统边缘/底部滑动。
- 回放时自动处理亮屏、锁屏解锁、目标 App 打开与前台确认，并恢复方向锁、常亮和屏幕超时设置。
- **跑完清理后台**：任务结束后自动 `am force-stop` 目标 App 回收内存，下次任务从干净状态开始；可全局开关，也可按任务单独覆盖。
- **多语言 WebUI**：中文 / English / Français / Русский，页面右上角可切换，选择会记住。
- **多设备适配**：内置设备档案层，可按机型调整屏幕尺寸、显示 ID 和锁屏密码宫格位置，让录制、回放和 PIN 自动解锁也能在别的澎湃 4 机型上用；Xiaomi 17 Pro 的实测基线原样保留、不受任何影响。
- **WebUI 升级即生效**：资源带版本号并禁用缓存，页面还会自检「文档是不是旧的」并自动重载 —— 模块更新后不再需要卸载重装。
- **界面清爽**：概览区一眼看状态，细节收进可折叠分组，首屏不再是一大坨表单；「展开全部 / 收起全部」一键切换。
- PIN 只写入本机配置，不在状态接口、运行日志或源码中出现明文。

## 运行环境

模块只用到标准的 `customize.sh` + `service.sh` 入口：**不含 Zygisk、不改 `/system`、不需要 metamodule**。所以在 Magisk / APatch 下定时调度、录制回放、PIN 自动解锁都能正常跑。

但 **WebUI 依赖 KernelSU 注入的 `kernelsu.js` 桥**，Magisk / APatch 不提供这个桥：

| 功能 | KernelSU | Magisk / APatch |
| --- | :---: | :---: |
| 定时调度 / 录制 / 回放 / PIN 自动解锁 | ✅ | ✅ |
| 模块 WebUI | ✅ | ❌（用下面的 `webctl.sh`） |

在 Magisk / APatch 下想改配置，用 root shell 直接调 `webctl.sh`（与 WebUI 完全同一套后端）：

```sh
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh status'
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh settime 0730'
su -c 'sh /data/adb/modules/icbc_daily_water/webctl.sh trigger'      # 立刻跑一次内置任务
su -c 'WEBUI_PIN=123456 sh /data/adb/modules/icbc_daily_water/webctl.sh setpin'
```

PIN 刻意**只接受环境变量 `WEBUI_PIN`**，不接受命令行参数，这样明文不会出现在进程列表里。上面这条请在本地终端手敲，不要写进脚本、别名或聊天记录。

完整子命令见文件头注释：`webctl.sh status|setpin|settime|setenable|setmode|setopen|setsleep|setwatch|setcleanup|trigger[NAME]|restart|log|profiles|profile add/del/set|record start/stop/status`。

## 安装

1. 从 Releases 下载 `xiaomi-17-pro-automation-v0.12.3.zip`。
2. 在 KernelSU / Magisk 中刷入该 zip。
3. 重启设备后打开模块 WebUI，按需设置解锁方式和 PIN。
4. 首次使用录制任务时，填写目标 App 包名；切到该 App 后点击「开始录制」，操作完成后点击「停止录制」。

### 从旧版本升级

可以直接在 KernelSU / Magisk 中覆盖安装新版 zip。为保证旧用户配置和任务不丢失，模块内部兼容标识保持不变：

```text
id=icbc_daily_water
/data/adb/modules/icbc_daily_water
/data/adb/icbc_water
```

请不要手动删除这些目录或修改模块 ID；配置、Profile、PIN 和录制动作会继续沿用。

> 如果升级后 WebUI 仍显示旧界面，打开模块 WebUI 确认右上角版本号是否为 `v0.12.3`；若不是，说明装的是旧包。

## 使用说明

### 内置任务

首次安装会自动创建「工行定时浇水」任务。它是脚本型 Profile，调用内置 `water.sh` 完成工行首页判断、任务入口点击和浇水流程。默认定时为 `07:30`，可以在 WebUI 中修改。

### 录制任务

1. 在 WebUI 中新增任务，填写任务名和目标 App 包名；包名留空表示亮屏全量录制。
2. 点击任务的「开始录制」，切换到目标 App。
3. 完成操作后回到 WebUI，点击「停止录制」。
4. 确认动作数量后，可立即运行或等待该 Profile 的定时时间。

要录制左右边缘返回手势，请填写目标包名；App 绑定模式会保留边缘返回，普通离开 App 的动作会被丢弃。

### 跑完清理后台

「⚙️ 其它 → 跑完清理后台」控制所有任务跑完后是否自动退出目标 App，**默认开启**。它只回收进程，不会清除数据、账号或登录状态。

两种例外需要注意：

- **同 App 接力**：如果你把同一个 App 的操作拆成多个任务（例如前半段和后半段各录一个），前一个跑完就退出 App 会让后一个回到首页而错位。给接力链上的任务在任务卡里把清理选为「跟随全局」以外的方式即可，具体做法是把**接力中间的**任务设为「关（保持后台）」，只在链条最后一个任务保留清理。
- **裸录任务**（包名留空）没有确定的目标 App，服务端无从判断该退出哪个进程，因此这类任务不会自动清理，任务卡上会标注。

「每日首次打开工行自动浇水」是另一条链路：你正在用手机、主动打开了工行，模块不会把你踢出 App。

### 锁屏与电源

任务执行前会尝试亮屏并解锁，支持 PIN 盲打或上滑解锁。执行期间会临时保持常亮，结束后恢复原来的方向锁、`screen_off_timeout` 和常亮设置。锁屏状态无法确认时会安全中止，不会盲目注入坐标。

### 语言

WebUI 右上角的下拉可切换中文 / English / Français / Русussian（Русский），选择保存在浏览器本地存储中。日志、命令和包名属于技术内容，保持原文不翻译。

## 设备与校准

默认目标设备为 Xiaomi 17 Pro，模块通过 `getevent -p` 自动发现触摸设备，并根据触摸轴范围换算坐标。

### 换机器用：设备档案

「📱 设备档案」卡片只影响三样东西：**屏幕宽高、显示 ID、锁屏密码宫格位置**。这三个值直接决定录制、回放和 PIN 自动解锁能不能正常工作，别的机器和 17 Pro 不一样，所以要单独填。

- **Xiaomi 17 Pro**：卡片默认就是这套已实测的值，**不需要改动**。「启用覆盖」保持关闭，模块用的就是 `water.sh` / `sched.conf` 里的原值。
- **其它澎湃 4 机型**（小米 17 / 17 Pro Max 等）：点「🔍 自动检测本机」自动填入 `wm size` 和 `wm density` 的值，核对无误后勾上「启用覆盖」再保存。锁屏密码宫格无法自动可靠识别，需要手动填 —— 不填就用 17 Pro 的值，别的机器上会点错格子。
- 设备档案存放在 `/data/adb/icbc_water/device.conf`。`DEV_APPLY=0`（默认）表示「不覆盖，按 17 Pro 基线走」；只有 `DEV_APPLY=1` 才启用覆盖。所有数值都要通过「唯一 + 纯数字」校验，填错或文件损坏最多让覆盖不生效，不会把浇水流程带歪。

> **除 Xiaomi 17 Pro 外，其它机型均为「测试中」状态。** 分辨率、DPI、系统导航栏高度都会影响 UI 布局，所以：**工行流程不保证可用**；但**录制、回放、PIN 自动解锁等基础功能是可以正常使用的**。请勿在主力机上直接使用。

### 跨机器回放录好的动作

每个录制型任务卡上有一个「不缩放 / 按比例缩放」下拉。如果某个任务是在**分辨率不同的机器**上录的、现在要在本机回放，把它选为「按比例缩放」——模块会读录制文件头里记录的分辨率，把每个坐标按比例换算。默认是「不缩放」，同机录制回放不受任何影响。

### 工行流程坐标

工行流程的像素探针和坐标集中在 `water.sh` 顶部配置区。可使用仓库中的辅助工具检查截图颜色：

```sh
python3 tools/px.py screen.png 216,778 518,780 746,748
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块元数据（显示名称、版本、作者） |
| `service.sh` | 多 Profile 守护与调度、亮屏/解锁/电源恢复、跑完清理 |
| `water.sh` | 内置工行浇水业务逻辑 |
| `record.sh` | 触摸事件录制内核 |
| `replay.sh` | 录制动作回放内核 |
| `webctl.sh` | WebUI root 命令接口 |
| `webroot/` | KernelSU WebUI 页面、脚本与多语言词典 |
| `sched.conf` | 默认配置模板（安装后实际配置位于 `/data/adb/icbc_water/`） |
| `device.conf` | 设备档案模板（安装后实际位于 `/data/adb/icbc_water/device.conf`） |
| `customize.sh` | 安装/升级兼容流程、权限设置与 WebUI 完整性校验 |
| `tools/px.py` | 截图像素校准工具 |
| `tools/run_once.sh` | 手动运行内置工行流程 |
| `tools/build_zip.sh` | 从仓库内容生成可刷入 zip |

## 从源码构建

在仓库根目录执行：

```sh
bash tools/build_zip.sh
```

脚本会在仓库父目录生成：

```text
xiaomi-17-pro-automation-v0.12.3.zip
```

## 许可证

[MIT](LICENSE) License.
