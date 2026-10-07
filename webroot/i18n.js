// icbc_daily_water / webroot/i18n.js  v0.10.0
// WebUI 多语言: 中文(默认) / English / Français / Русский
// 约定: 只翻译「面向用户的界面文案」; 内部标识(日志键、conf 键名、路径、命令)一律不译。
// 缺 key 时回退中文, 再缺则原样返回 key, 不会出现空白界面。

export const LANGS = [
  { code: 'zh-CN', label: '中文' },
  { code: 'en', label: 'English' },
  { code: 'fr', label: 'Français' },
  { code: 'ru', label: 'Русский' },
];

export const DEFAULT_LANG = 'zh-CN';
const STORE_KEY = 'icbcauto.webui.lang';

const zh = {
  'app.title': '💧 澎湃自动化 · Xiaomi 17 Pro',
  'app.loading': '…',
  'app.nobridge': '⚠️ 未检测到 root 管理器接口',
  'app.nobridge.hint': '这个页面要靠 root 管理器打开：所有操作都通过管理器注入的 root 接口执行命令，直接用浏览器打开拿不到任何权限，页面上的报错都是这个原因。',
  'app.nobridge.fix': '请回到管理器里，从模块列表点开本模块的 WebUI。Magisk 用户请先装 KsuWebUI 或 MMRL —— 两者注入的是同一个接口，本模块不用改任何东西就能用；KernelSU / APatch 及其分支（KernelSU Next、SukiSU Ultra）在管理器里直接打开即可。命令行用户改用 webctl.sh，功能完全一样。',

  'btn.save': '保存',
  'btn.show': '显示',
  'btn.hide': '隐藏',
  'btn.add': '＋ 新增',
  'btn.refresh': '刷新状态',
  'btn.restart': '重启服务',
  'btn.logRefresh': '刷新',
  'btn.savePkg': '存',
  'btn.del': '删',
  'btn.runWater': '立即浇水',
  'btn.runTask': '立即跑',
  'btn.recStart': '开始录制',
  'btn.recStop': '停止录制',

  'card.prof.title': '📁 任务 Profiles',
  'card.prof.hint': '每个任务独立定时。内置「工行定时浇水」为脚本型；新建为录制型：包名非空时切到目标 app 后开始，离开暂停、回来继续；包名留空则亮屏录全量。要录左右边缘返回请填写目标包名；裸录会按规则过滤边缘滑动。锁屏自动暂停，全部录完点停止即可',
  'prof.schedHint': '到点自动：亮屏 → 解锁 → 执行任务（内置工行会打开工行；录制任务按包名打开或使用当前画面）→ 按设置熄屏。默认 07:30（避开工行夜间维护窗口）',
  'card.pin.title': '🔓 锁屏密码 (PIN)',
  'card.pin.hint': '6 位数字。仅写入本机 /data/adb/icbc_water/sched.conf（chmod 600）；状态、日志和接口不回显明文。保存后立即生效',
  'card.misc.title': '⚙️ 其它',
  'card.chk.title': '🔬 触发检查（没浇时看这里）',
  'card.chk.hint': '定时触发条件逐项显示，每 15 秒自动刷新；哪项 ✗ 就是没触发的原因',
  'card.log.title': '📜 运行日志',

  'lbl.unlockMode': '解锁方式',
  'lbl.watchOpen': '每日首次打开工行自动浇水',
  'lbl.sleepAfter': '浇完自动熄屏',
  'lbl.cleanupAfter': '跑完清理后台（释放内存）',
  'lbl.cleanupHint': '任务结束后自动退出目标 app，释放内存；下一个任务从干净状态开始',
  'lbl.pkg': '包',
  'lbl.enable': '启用',
  'lbl.lang': '语言',

  'opt.pin': 'PIN 盲打解锁',
  'opt.swipe': '上滑解锁（无密码）',
  'opt.cleanup.on': '开（跑完退出 app）',
  'opt.cleanup.off': '关（保持后台）',
  'opt.cleanup.inherit': '跟随全局',

  'ph.pinSet': '已设置（输入新密码才修改）',
  'ph.pinUnset': '未设置，请输入 6 位密码',
  'ph.npName': '新任务名(如 支付宝浇水)',
  'ph.npPkg': '包名（可留空：亮屏全量录）',
  'ph.pkgUnset': '未设(亮屏即录)',

  'st.todayDone': '今日已浇 ✅',
  'st.todayPending': '今日未浇',
  'st.svcRun': '运行中',
  'st.svcStop': '已停止',
  'st.on': '开',
  'st.off': '关',

  'chk.svc': '守护服务',
  'chk.enable': '定时开关',
  'chk.window': '在触发窗口（到点后 60 分钟内）',
  'chk.windowYes': '是（当前 {now}）',
  'chk.windowNo': '不在窗口',
  'chk.done': '当天定时已浇',
  'chk.doneYes': '已浇（今天不再自动浇）',
  'chk.doneNo': '未浇',
  'chk.screen': '触发时屏幕',
  'chk.screenOff': '已熄（直接唤醒）',
  'chk.screenOn': '亮着（会先锁屏再解锁）',
  'chk.fail': '连续失败 <3 次',
  'chk.failN': '{n} 次',
  'chk.failBlocked': '{n} 次（被暂停，超6小时自动清零）',

  'prof.script': '脚本型',
  'prof.record': '录制型',
  'prof.doneToday': '今日已跑',
  'prof.notToday': '今日未跑',
  'prof.failN': '失败{n}',
  'prof.acts': '动作 {n}',

  'prof.loadFail': '加载失败：{err}',
  'prof.empty': '还没有任务，用下面表单新增',
  'prof.bareNote': '裸录任务无包名，无法自动清理',

  'toast.pinEmpty': '未输入新密码',
  'toast.pinBad': '密码需 4-8 位数字',
  'toast.pinSaved': 'PIN 已保存',
  'toast.saved': '已保存',
  'toast.savedOn': '已开启',
  'toast.savedOff': '已关闭',
  'toast.nameEmpty': '请输入任务名',
  'toast.nameBad': '任务名只能中文/字母/数字/下划线/横线，且不超过24字',
  'toast.pkgBad': '包名格式不对',
  'toast.addFail': '新增失败：{err}',
  'toast.added': '任务已新增，点它的「开始录制」',
  'toast.enabled': '已启用',
  'toast.disabled': '已停用',
  'toast.schedSaved': '定时已保存',
  'toast.trigOk': '已触发「{name}」！屏不亮就重启服务',
  'toast.pkgSaved': '目标app已保存：{pkg}',
  'toast.pkgCleared': '已清空（亮屏即录）',
  'toast.delConfirm': '删除任务「{name}」及其录制动作？',
  'toast.deleted': '已删除',
  'toast.recStopped': '录制已停止',
  'toast.recNoApp': '还没识别到目标 app（请确认已切到该 app 操作）',
  'toast.recStart': '开始录制！切到目标 app 才会开录，离开自动暂停，操作完点「停止录制」',
  'toast.svcRestarted': '服务已重启',
  'toast.cleanupSaved': '后台清理已开启',
  'toast.cleanupOff': '后台清理已关闭',
  'toast.profCleanupSaved': '该任务的清理设置已保存',
  'toast.err': '操作失败：{err}',

  'log.empty': '(no log yet)',

  // v0.11.0 设备档案 / 跨设备回放缩放
  'dev.title': "📱 设备档案",
  'dev.model': "机型",
  'dev.label': "显示名",
  'dev.apply': "启用覆盖",
  'dev.apply.hint': "关闭＝用 17 Pro 的实测基线值（推荐）。开启＝用下面填的数值。",
  'dev.sw': "屏宽 (px)",
  'dev.sh': "屏高 (px)",
  'dev.d': "显示 ID",
  'dev.dpi': "界面密度 (DPI)",
  'dev.pin': "锁屏密码宫格",
  'dev.detect': "🔍 自动检测本机",
  'dev.detect.ok': "已检测到本机参数，请确认后保存",
  'dev.detect.nothing': "未检测到本机参数，请手动填写",
  'dev.bad.fields': "参数不合法：{f}",
  'dev.stable': "稳定",
  'dev.testing': "测试中",
  'dev.stable.hint': "该机型已验证，当前使用 17 Pro 实测基线",
  'dev.testing.hint': "「测试中」＝该机型尚未经过验证，不影响保存与使用",
  'dev.status.hint': "「稳定 / 测试中」是机型验证状态，不是运行状态，也不会阻止保存。",
  'dev.saved': "设备档案已保存",
  'scale.title': "📐 跨设备回放缩放",
  'scale.hint': "把别的机器上录的动作按分辨率比例换算后再回放。默认关闭；只有当任务是在分辨率不同的机器上录的才需要开。",
  'opt.scale.off': "不缩放",
  'opt.scale.on': "按比例缩放",
  'toast.profScaleSaved': "该任务的缩放设置已保存",


  // v0.12.0 界面重构: 概览区 / 折叠分组 / 键名标签
  'hero.hint': '到点自动：亮屏 → 解锁 → 跑任务 → 熄屏。下面各项按需展开，改完即时生效。',
  'ui.collapse': '收起全部',
  'ui.expand': '展开全部',
  'prof.new': '新增任务：脚本型任务（工行定时浇水）是内置的；这里新建的都是录制型。',
  'dev.hint.short': '默认就是 17 Pro 的实测值，别改。换机器时点「自动检测」填好再勾选「启用覆盖」。',
  'card.log.hint': '最近 60 行',
  'foot.ver': '模块 {ver} · 语言 {lang}',

  // v0.13.0 每周执行日 / 全场录取 / 图案解锁 / 内置工行任务可删
  'lbl.days': '每周执行日',
  'days.hint': '任务卡片里的执行日留空时跟随这里；只有点亮的那天才会自动跑。七天全灭等于停掉定时（手动「立即跑」不受影响）。',
  'day.1': '一',
  'day.2': '二',
  'day.3': '三',
  'day.4': '四',
  'day.5': '五',
  'day.6': '六',
  'day.7': '日',
  'opt.days.inherit': '跟随全局',
  'btn.addIcbc': '＋ 恢复内置工行任务',
  'lbl.recMode': '录制方式',
  'opt.rec.pkg': '指定包名录取',
  'opt.rec.all': '全场录取',
  'prof.recModeHint': '指定包名录取＝切到那个 app 才开录、离开自动暂停；全场录取＝不填包名，跨 App 全程录制，连回桌面和边缘返回都录下来（回放前默认先回桌面）。',
  'prof.allScope': '全场录取',
  'lbl.pHome': '回放前先回桌面',
  'opt.pattern': '图案解锁（九宫格）',
  'card.pat.hint': '按住拖动画出图案，或逐格点选；跳过的中间格会像 Android 一样自动补上。至少 4 个点，保存后到点自动一笔画完。',
  'pat.unset': '未画',
  'pat.set': '已设置（画新图案后点保存）',
  'btn.patSave': '保存图案',
  'btn.patClear': '清除',
  'btn.unlockTest': '🔒 测试解锁（锁屏→解锁）',
  'unlock.test.hint': '会真的锁一次屏再解锁，用来校准图案宫格和 PIN 键盘的坐标。测试期间屏幕会亮起。',
  'dev.pat': '锁屏图案宫格',
  'chk.day': '今天是执行日',
  'chk.dayYes': '是（周{day}）',
  'chk.dayNo': '不是（今天不会自动跑）',
  'toast.daysSaved': '执行日已保存',
  'toast.icbcRestored': '内置工行任务已恢复',
  'toast.recModeSaved': '录制方式已保存',
  'toast.pHomeSaved': '回放起点已保存',
  'toast.patBad': '至少画 4 个点，且不能重复',
  'toast.patSaved': '图案已保存',
  'toast.patCleared': '图案已清除',
  'toast.unlockTesting': '正在测试解锁…（约 5-10 秒）',
  'toast.unlockOk': '解锁成功 ✅ 图案/PIN 坐标没问题',
};

const en = {
  'app.title': '💧 XiaomiAutomation · Xiaomi 17 Pro',
  'app.loading': '…',
  'app.nobridge': '⚠️ No root manager interface detected',
  'app.nobridge.hint': 'This page has to be opened by a root manager: every action runs a command through the root interface the manager injects. Opened in a plain browser it gets no privileges at all, which is what the errors on this page mean.',
  'app.nobridge.fix': 'Go back to your manager and open this module\u2019s WebUI from the module list. On Magisk, install KsuWebUI or MMRL first \u2014 both inject the same interface, so this module needs no changes at all; on KernelSU / APatch and their forks (KernelSU Next, SukiSU Ultra) just open it in the manager. From a root shell, use webctl.sh instead \u2014 it does exactly the same thing.',

  'btn.save': 'Save',
  'btn.show': 'Show',
  'btn.hide': 'Hide',
  'btn.add': '＋ Add',
  'btn.refresh': 'Refresh',
  'btn.restart': 'Restart service',
  'btn.logRefresh': 'Refresh',
  'btn.savePkg': 'Set',
  'btn.del': 'Del',
  'btn.runWater': 'Water now',
  'btn.runTask': 'Run now',
  'btn.recStart': 'Start recording',
  'btn.recStop': 'Stop recording',

  'card.prof.title': '📁 Task profiles',
  'card.prof.hint': 'Each task has its own schedule. The built-in "ICBC daily watering" task is script-based; new tasks are record-based: with a package name recording starts once you switch to that app, pauses when you leave and resumes when you return; leaving the package name empty records everything from a lit screen. Fill in the package name to capture edge-back gestures; bare recording filters edge swipes by rule. Recording pauses on a locked screen — switch back and press Stop when done.',
  'prof.schedHint': 'At the scheduled time the module wakes the screen, unlocks, runs the task (the built-in ICBC task opens ICBC; recorded tasks open their target app or use the current screen) and sleeps the screen as configured. Default 07:30 (avoids the ICBC nightly maintenance window).',
  'card.pin.title': '🔓 Lock screen PIN',
  'card.pin.hint': '4-8 digits. Written only to the on-device /data/adb/icbc_water/sched.conf (chmod 600); the plaintext never appears in the status output, the log or this page. Takes effect immediately.',
  'card.misc.title': '⚙️ Other',
  'card.chk.title': '🔬 Trigger check (look here if nothing runs)',
  'card.chk.hint': 'Every trigger condition is listed and refreshed automatically every 15 seconds. A ✗ is the reason nothing fired.',
  'card.log.title': '📜 Run log',

  'lbl.unlockMode': 'Unlock method',
  'lbl.watchOpen': 'Water when ICBC is opened for the first time each day',
  'lbl.sleepAfter': 'Sleep the screen after watering',
  'lbl.cleanupAfter': 'Clean up the app in the background afterwards',
  'lbl.cleanupHint': 'The target app is closed after the task so it stops holding memory; the next task starts from a clean state.',
  'lbl.pkg': 'Pkg',
  'lbl.enable': 'Enable',
  'lbl.lang': 'Language',

  'opt.pin': 'Blind PIN entry',
  'opt.swipe': 'Swipe up (no password)',
  'opt.cleanup.on': 'On (close app afterwards)',
  'opt.cleanup.off': 'Off (keep it in background)',
  'opt.cleanup.inherit': 'Follow global setting',

  'ph.pinSet': 'Already set (type a new PIN to change it)',
  'ph.pinUnset': 'Not set yet, enter 4-8 digits',
  'ph.npName': 'New task name (e.g. Alipay watering)',
  'ph.npPkg': 'Package name (empty = record the whole screen)',
  'ph.pkgUnset': 'not set (records a lit screen)',

  'st.todayDone': 'Done today ✅',
  'st.todayPending': 'Not watered today',
  'st.svcRun': 'running',
  'st.svcStop': 'stopped',
  'st.on': 'on',
  'st.off': 'off',

  'chk.svc': 'Daemon service',
  'chk.enable': 'Schedule switch',
  'chk.window': 'Inside trigger window (60 min after the set time)',
  'chk.windowYes': 'yes (now {now})',
  'chk.windowNo': 'outside the window',
  'chk.done': 'Scheduled run done today',
  'chk.doneYes': 'done (no automatic run today)',
  'chk.doneNo': 'not done',
  'chk.screen': 'Screen state at trigger time',
  'chk.screenOff': 'off (woken directly)',
  'chk.screenOn': 'on (locked, then unlocked)',
  'chk.fail': 'Consecutive failures < 3',
  'chk.failN': '{n}',
  'chk.failBlocked': '{n} (paused; cleared automatically after 6 hours)',

  'prof.script': 'script',
  'prof.record': 'recorded',
  'prof.doneToday': 'ran today',
  'prof.notToday': 'not run today',
  'prof.failN': 'failed {n}',
  'prof.acts': '{n} actions',

  'prof.loadFail': 'Failed to load: {err}',
  'prof.empty': 'No tasks yet — add one with the form below',
  'prof.bareNote': 'A bare task has no package, so it cannot be cleaned up automatically',

  'toast.pinEmpty': 'No new PIN entered',
  'toast.pinBad': 'The PIN must be 4-8 digits',
  'toast.pinSaved': 'PIN saved',
  'toast.saved': 'Saved',
  'toast.savedOn': 'Enabled',
  'toast.savedOff': 'Disabled',
  'toast.nameEmpty': 'Enter a task name',
  'toast.nameBad': 'A task name may only contain letters, digits, Chinese characters, underscore and dash, up to 24 characters',
  'toast.pkgBad': 'Invalid package name',
  'toast.addFail': 'Could not add the task: {err}',
  'toast.added': 'Task added — press its "Start recording" button',
  'toast.enabled': 'Enabled',
  'toast.disabled': 'Disabled',
  'toast.schedSaved': 'Schedule saved',
  'toast.trigOk': 'Triggered "{name}"! If the screen does not light up, restart the service.',
  'toast.pkgSaved': 'Target app saved: {pkg}',
  'toast.pkgCleared': 'Cleared (records a lit screen)',
  'toast.delConfirm': 'Delete task "{name}" and its recorded actions?',
  'toast.deleted': 'Deleted',
  'toast.recStopped': 'Recording stopped',
  'toast.recNoApp': 'Target app not detected yet (make sure you switched to that app)',
  'toast.recStart': 'Recording! Switch to the target app to start — it pauses when you leave; press "Stop recording" when done',
  'toast.svcRestarted': 'Service restarted',
  'toast.cleanupSaved': 'Background cleanup enabled',
  'toast.cleanupOff': 'Background cleanup disabled',
  'toast.profCleanupSaved': 'Cleanup setting saved for this task',
  'toast.err': 'Operation failed: {err}',

  'log.empty': '(no log yet)',

  // v0.11.0 设备档案 / 跨设备回放缩放
  'dev.title': "📱 Device profile",
  'dev.model': "Model",
  'dev.label': "Display name",
  'dev.apply': "Enable override",
  'dev.apply.hint': "Off = use the measured 17 Pro baseline (recommended). On = use the values below.",
  'dev.sw': "Width (px)",
  'dev.sh': "Height (px)",
  'dev.d': "Display ID",
  'dev.dpi': "Density (DPI)",
  'dev.pin': "Lock-screen keypad",
  'dev.detect': "🔍 Auto-detect this phone",
  'dev.detect.ok': "Detected this phone's values — review and save",
  'dev.detect.nothing': "No values detected on this device — please fill them in manually",
  'dev.bad.fields': "Invalid value: {f}",
  'dev.stable': "Stable",
  'dev.testing': "Testing",
  'dev.stable.hint': "This model is verified; the measured 17 Pro baseline is in use",
  'dev.testing.hint': "“Testing” means this model is not yet verified — it does not block saving or use",
  'dev.status.hint': "“Stable / Testing” is the model's verification status, not a run status — it never blocks saving.",
  'dev.saved': "Device profile saved",
  'scale.title': "📐 Cross-device replay scaling",
  'scale.hint': "Convert actions recorded on another phone to this screen's resolution before replaying. Off by default; only needed when the task was recorded on a phone with a different resolution.",
  'opt.scale.off': "No scaling",
  'opt.scale.on': "Scale to screen",
  'toast.profScaleSaved': "Scaling setting saved for this task",


  // v0.12.0 界面重构: 概览区 / 折叠分组 / 键名标签
  'hero.hint': 'On schedule it wakes, unlocks, runs the tasks and turns the screen back off. Expand the sections below as needed — changes take effect immediately.',
  'ui.collapse': 'Collapse all',
  'ui.expand': 'Expand all',
  'prof.new': 'Add a task: script tasks (the built-in ICBC watering) are provided; anything you create here is a recorded one.',
  'dev.hint.short': 'The defaults are the measured 17 Pro values — do not change them. On another phone press “Auto-detect this phone”, check the numbers, then tick “Enable override”.',
  'card.log.hint': 'Last 60 lines',
  'foot.ver': 'Module {ver} · Language {lang}',

  // v0.13.0 weekly run days / whole-device recording / pattern unlock / deletable built-in task
  'lbl.days': 'Days of the week',
  'days.hint': 'A task whose own day list is empty follows this one. Only the lit days run automatically; turning all seven off stops the schedule (running a task manually still works).',
  'day.1': 'Mo',
  'day.2': 'Tu',
  'day.3': 'We',
  'day.4': 'Th',
  'day.5': 'Fr',
  'day.6': 'Sa',
  'day.7': 'Su',
  'opt.days.inherit': 'Follow global',
  'btn.addIcbc': '＋ Restore built-in ICBC task',
  'lbl.recMode': 'Recording mode',
  'opt.rec.pkg': 'Bound to a package',
  'opt.rec.all': 'Whole-device recording',
  'prof.recModeHint': 'Bound to a package: recording starts once you switch to that app and pauses when you leave it. Whole-device: no package needed — everything is captured across apps, including going home and edge-back gestures (replay starts from the home screen by default).',
  'prof.allScope': 'Whole-device',
  'lbl.pHome': 'Go home before replay',
  'opt.pattern': 'Pattern unlock (3x3 grid)',
  'card.pat.hint': 'Drag across the grid or tap the dots in order; skipped middle dots are filled in automatically, just like Android. At least 4 dots — once saved, the pattern is drawn in one stroke at the scheduled time.',
  'pat.unset': 'Not drawn',
  'pat.set': 'Set (draw a new pattern and press save)',
  'btn.patSave': 'Save pattern',
  'btn.patClear': 'Clear',
  'btn.unlockTest': '🔒 Test unlock (lock, then unlock)',
  'unlock.test.hint': 'Really locks the screen and then unlocks it — used to calibrate the pattern grid and the PIN keypad. The screen turns on during the test.',
  'dev.pat': 'Lock-screen pattern grid',
  'chk.day': 'Today is a scheduled day',
  'chk.dayYes': 'yes ({day})',
  'chk.dayNo': 'no (nothing runs automatically today)',
  'toast.daysSaved': 'Days saved',
  'toast.icbcRestored': 'Built-in ICBC task restored',
  'toast.recModeSaved': 'Recording mode saved',
  'toast.pHomeSaved': 'Replay start point saved',
  'toast.patBad': 'Draw at least 4 dots, without repeating any',
  'toast.patSaved': 'Pattern saved',
  'toast.patCleared': 'Pattern cleared',
  'toast.unlockTesting': 'Testing unlock… (about 5-10 s)',
  'toast.unlockOk': 'Unlocked ✅ the pattern/PIN coordinates are good',
};

const fr = {
  'app.title': '💧 XiaomiAutomation · Xiaomi 17 Pro',
  'app.loading': '…',
  'app.nobridge': '⚠️ Aucune interface du gestionnaire root détectée',
  'app.nobridge.hint': 'Cette page doit être ouverte par un gestionnaire root : chaque action exécute une commande via l\u2019interface root injectée par le gestionnaire. Ouverte dans un simple navigateur, elle n\u2019a aucun privilège \u2014 c\u2019est la cause des messages d\u2019erreur affichés.',
  'app.nobridge.fix': 'Revenez à votre gestionnaire et ouvrez le WebUI du module depuis la liste. Sur Magisk, installez d\u2019abord KsuWebUI ou MMRL : les deux injectent la même interface, ce module n\u2019a donc aucune modification à faire ; sur KernelSU / APatch et leurs forks (KernelSU Next, SukiSU Ultra), ouvrez-le directement dans le gestionnaire. Depuis un shell root, utilisez webctl.sh \u2014 c\u2019est exactement équivalent.',

  'btn.save': 'Enregistrer',
  'btn.show': 'Afficher',
  'btn.hide': 'Masquer',
  'btn.add': '＋ Ajouter',
  'btn.refresh': 'Actualiser',
  'btn.restart': 'Redémarrer le service',
  'btn.logRefresh': 'Actualiser',
  'btn.savePkg': 'OK',
  'btn.del': 'Suppr.',
  'btn.runWater': 'Arroser',
  'btn.runTask': 'Lancer',
  'btn.recStart': 'Démarrer l\'enregistrement',
  'btn.recStop': 'Arrêter l\'enregistrement',

  'card.prof.title': '📁 Profils de tâches',
  'card.prof.hint': 'Chaque tâche a son propre horaire. La tâche intégrée « Arrosage ICBC quotidien » est de type script ; les nouvelles tâches sont de type enregistrement : avec un nom de package, l\'enregistrement démarre dès que vous basculez vers cette application, se met en pause quand vous quittez et reprend à votre retour ; laissez le package vide pour enregistrer tout l\'écran allumé. Renseignez le package pour capturer les gestes de retour par le bord ; l\'enregistrement nu filtre les balayages de bord. L\'enregistrement se met en pause sur écran verrouillé — revenez et appuyez sur Arrêter une fois terminé.',
  'prof.schedHint': 'À l\'heure prévue, le module allume l\'écran, déverrouille, exécute la tâche (la tâche ICBC intégrée ouvre ICBC ; les tâches enregistrées ouvrent leur application cible ou utilisent l\'écran courant), puis éteint l\'écran selon le réglage. Par défaut 07:30 (pour éviter la fenêtre de maintenance nocturne d\'ICBC).',
  'card.pin.title': '🔓 Code PIN de l\'écran de verrouillage',
  'card.pin.hint': '4 à 8 chiffres. Écrit uniquement dans le fichier local /data/adb/icbc_water/sched.conf (chmod 600) ; le texte clair n\'apparaît jamais dans l\'état, le journal ni cette page. Prise d\'effet immédiate.',
  'card.misc.title': '⚙️ Autres',
  'card.chk.title': '🔬 Vérification du déclenchement (consultez ici si rien ne se passe)',
  'card.chk.hint': 'Chaque condition de déclenchement est affichée et actualisée automatiquement toutes les 15 secondes. Un ✗ indique la raison du déclenchement.',
  'card.log.title': '📜 Journal d\'exécution',

  'lbl.unlockMode': 'Méthode de déverrouillage',
  'lbl.watchOpen': 'Arroser à la première ouverture quotidienne d\'ICBC',
  'lbl.sleepAfter': 'Éteindre l\'écran après l\'arrosage',
  'lbl.cleanupAfter': 'Nettoyer l\'application en arrière-plan ensuite',
  'lbl.cleanupHint': 'L\'application cible est fermée après la tâche afin de libérer la mémoire ; la tâche suivante démarre dans un état propre.',
  'lbl.pkg': 'Paquet',
  'lbl.enable': 'Activer',
  'lbl.lang': 'Langue',

  'opt.pin': 'Saisie aveugle du code PIN',
  'opt.swipe': 'Balayage vers le haut (sans mot de passe)',
  'opt.cleanup.on': 'Activé (fermer l\'application ensuite)',
  'opt.cleanup.off': 'Désactivé (garder en arrière-plan)',
  'opt.cleanup.inherit': 'Suivre le réglage global',

  'ph.pinSet': 'Déjà défini (saisissez un nouveau code pour le changer)',
  'ph.pinUnset': 'Non défini, saisissez 4 à 8 chiffres',
  'ph.npName': 'Nom de la nouvelle tâche (ex. arrosage Alipay)',
  'ph.npPkg': 'Nom de package (vide = enregistrer tout l\'écran)',
  'ph.pkgUnset': 'non défini (enregistre l\'écran allumé)',

  'st.todayDone': 'Fait aujourd\'hui ✅',
  'st.todayPending': 'Pas encore arrosé aujourd\'hui',
  'st.svcRun': 'en cours',
  'st.svcStop': 'arrêté',
  'st.on': 'activé',
  'st.off': 'désactivé',

  'chk.svc': 'Service de surveillance',
  'chk.enable': 'Interrupteur de programmation',
  'chk.window': 'Dans la fenêtre de déclenchement (60 min après l\'heure réglée)',
  'chk.windowYes': 'oui (actuellement {now})',
  'chk.windowNo': 'hors fenêtre',
  'chk.done': 'Exécution programmée effectuée aujourd\'hui',
  'chk.doneYes': 'effectuée (pas d\'autre exécution aujourd\'hui)',
  'chk.doneNo': 'non effectuée',
  'chk.screen': 'État de l\'écran au déclenchement',
  'chk.screenOff': 'éteint (réveil direct)',
  'chk.screenOn': 'allumé (verrouillé puis déverrouillé)',
  'chk.fail': 'Échecs consécutifs < 3',
  'chk.failN': '{n}',
  'chk.failBlocked': '{n} (en pause, remis à zéro automatiquement après 6 heures)',

  'prof.script': 'script',
  'prof.record': 'enregistré',
  'prof.doneToday': 'exécuté aujourd\'hui',
  'prof.notToday': 'pas exécuté aujourd\'hui',
  'prof.failN': '{n} échec(s)',
  'prof.acts': '{n} actions',

  'prof.loadFail': 'Échec du chargement : {err}',
  'prof.empty': 'Aucune tâche pour le moment — ajoutez-en une avec le formulaire ci-dessous',
  'prof.bareNote': 'Une tâche nue n\'a pas de package : le nettoyage automatique est impossible',

  'toast.pinEmpty': 'Aucun nouveau code saisi',
  'toast.pinBad': 'Le code PIN doit comporter 4 à 8 chiffres',
  'toast.pinSaved': 'Code PIN enregistré',
  'toast.saved': 'Enregistré',
  'toast.savedOn': 'Activé',
  'toast.savedOff': 'Désactivé',
  'toast.nameEmpty': 'Saisissez un nom de tâche',
  'toast.nameBad': 'Un nom de tâche ne peut contenir que des lettres, des chiffres, des caractères chinois, un tiret bas ou un tiret, sur 24 caractères maximum',
  'toast.pkgBad': 'Nom de package invalide',
  'toast.addFail': 'Impossible d\'ajouter la tâche : {err}',
  'toast.added': 'Tâche ajoutée — appuyez sur « Démarrer l\'enregistrement »',
  'toast.enabled': 'Activé',
  'toast.disabled': 'Désactivé',
  'toast.schedSaved': 'Horaire enregistré',
  'toast.trigOk': '« {name} » déclenché ! Si l\'écran ne s\'allume pas, redémarrez le service.',
  'toast.pkgSaved': 'Application cible enregistrée : {pkg}',
  'toast.pkgCleared': 'Effacé (enregistre l\'écran allumé)',
  'toast.delConfirm': 'Supprimer la tâche « {name} » et ses actions enregistrées ?',
  'toast.deleted': 'Supprimé',
  'toast.recStopped': 'Enregistrement arrêté',
  'toast.recNoApp': 'Application cible non détectée (assurez-vous d\'être sur cette application)',
  'toast.recStart': 'Enregistrement ! Basculez vers l\'application cible pour démarrer — cela se met en pause si vous quittez ; appuyez sur « Arrêter l\'enregistrement » une fois terminé',
  'toast.svcRestarted': 'Service redémarré',
  'toast.cleanupSaved': 'Nettoyage en arrière-plan activé',
  'toast.cleanupOff': 'Nettoyage en arrière-plan désactivé',
  'toast.profCleanupSaved': 'Réglage de nettoyage enregistré pour cette tâche',
  'toast.err': 'Échec de l\'opération : {err}',

  'log.empty': '(no log yet)',

  // v0.11.0 设备档案 / 跨设备回放缩放
  'dev.title': "📱 Profil d'appareil",
  'dev.model': "Modèle",
  'dev.label': "Nom affiché",
  'dev.apply': "Activer le remplacement",
  'dev.apply.hint': "Désactivé = valeurs de référence mesurées du 17 Pro (recommandé). Activé = les valeurs ci-dessous.",
  'dev.sw': "Largeur (px)",
  'dev.sh': "Hauteur (px)",
  'dev.d': "ID d'affichage",
  'dev.dpi': "Densité (DPI)",
  'dev.pin': "Pavé de l'écran de verrouillage",
  'dev.detect': "🔍 Détecter ce téléphone",
  'dev.detect.ok': "Valeurs de ce téléphone détectées — vérifiez et enregistrez",
  'dev.detect.nothing': "Aucune valeur détectée sur cet appareil — saisissez-les manuellement",
  'dev.bad.fields': "Valeur invalide : {f}",
  'dev.stable': "Stable",
  'dev.testing': "En test",
  'dev.stable.hint': "Ce modèle est vérifié ; la référence mesurée du 17 Pro est utilisée",
  'dev.testing.hint': "« En test » signifie que ce modèle n'est pas encore vérifié — cela n'empêche ni l'enregistrement ni l'utilisation",
  'dev.status.hint': "« Stable / En test » est l'état de vérification du modèle, pas l'état d'exécution — cela n'empêche jamais l'enregistrement.",
  'dev.saved': "Profil d'appareil enregistré",
  'scale.title': "📐 Mise à l'échelle entre appareils",
  'scale.hint': "Convertit les gestes enregistrés sur un autre téléphone vers la résolution de cet écran avant la relecture. Désactivé par défaut ; nécessaire seulement si la tâche a été enregistrée sur un téléphone de résolution différente.",
  'opt.scale.off': "Sans mise à l'échelle",
  'opt.scale.on': "Mettre à l'échelle",
  'toast.profScaleSaved': "Réglage d'échelle enregistré pour cette tâche",


  // v0.12.0 界面重构: 概览区 / 折叠分组 / 键名标签
  'hero.hint': 'À l\'heure prévue, le module réveille l\'écran, déverrouille, exécute les tâches puis l\'éteint. Dépliez les sections ci-dessous au besoin — les modifications sont immédiatement effectives.',
  'ui.collapse': 'Tout replier',
  'ui.expand': 'Tout déplier',
  'prof.new': 'Ajouter une tâche : les tâches script (l\'arrosage ICBC intégré) sont fournies ; tout ce que vous créez ici est une tâche enregistrée.',
  'dev.hint.short': 'Les valeurs par défaut sont celles mesurées sur le 17 Pro — ne les modifiez pas. Sur un autre téléphone, appuyez sur « Détecter ce téléphone », vérifiez les valeurs, puis cochez « Activer le remplacement ».',
  'card.log.hint': '60 dernières lignes',
  'foot.ver': 'Module {ver} · Langue {lang}',

  // v0.13.0 jours de la semaine / enregistrement global / déverrouillage par motif
  'lbl.days': 'Jours de la semaine',
  'days.hint': 'Une tâche sans liste de jours propre suit celle-ci. Seuls les jours allumés tournent automatiquement ; tout éteindre arrête l’ordonnancement (le lancement manuel reste possible).',
  'day.1': 'lu',
  'day.2': 'ma',
  'day.3': 'me',
  'day.4': 'je',
  'day.5': 've',
  'day.6': 'sa',
  'day.7': 'di',
  'opt.days.inherit': 'Suivre global',
  'btn.addIcbc': '＋ Restaurer la tâche ICBC intégrée',
  'lbl.recMode': 'Mode d’enregistrement',
  'opt.rec.pkg': 'Lié à un paquet',
  'opt.rec.all': 'Enregistrement global',
  'prof.recModeHint': 'Lié à un paquet : l’enregistrement commence une fois l’app au premier plan et se met en pause quand on la quitte. Global : sans paquet, tout est capturé d’une app à l’autre — retour écran d’accueil et gestes de bord compris (la reprise démarre depuis l’accueil par défaut).',
  'prof.allScope': 'Global',
  'lbl.pHome': 'Retour à l’accueil avant reprise',
  'opt.pattern': 'Déverrouillage par motif (grille 3x3)',
  'card.pat.hint': 'Glissez sur la grille ou touchez les points dans l’ordre ; les points du milieu sautés sont ajoutés automatiquement, comme sur Android. Au moins 4 points ; une fois enregistré, le motif est tracé d’un seul trait à l’heure prévue.',
  'pat.unset': 'Non tracé',
  'pat.set': 'Enregistré (tracez un nouveau motif puis enregistrez)',
  'btn.patSave': 'Enregistrer le motif',
  'btn.patClear': 'Effacer',
  'btn.unlockTest': '🔒 Tester le déverrouillage (verrouiller puis déverrouiller)',
  'unlock.test.hint': 'Verrouille réellement l’écran puis le déverrouille — sert à caler la grille du motif et le clavier PIN. L’écran s’allume pendant le test.',
  'dev.pat': 'Grille du motif de verrouillage',
  'chk.day': 'Aujourd’hui est un jour prévu',
  'chk.dayYes': 'oui ({day})',
  'chk.dayNo': 'non (rien ne démarre auto aujourd’hui)',
  'toast.daysSaved': 'Jours enregistrés',
  'toast.icbcRestored': 'Tâche ICBC intégrée restaurée',
  'toast.recModeSaved': 'Mode d’enregistrement enregistré',
  'toast.pHomeSaved': 'Point de départ de la reprise enregistré',
  'toast.patBad': 'Tracez au moins 4 points, sans en répéter',
  'toast.patSaved': 'Motif enregistré',
  'toast.patCleared': 'Motif effacé',
  'toast.unlockTesting': 'Test du déverrouillage… (5-10 s)',
  'toast.unlockOk': 'Déverrouillé ✅ coordonnées du motif et du PIN correctes',
};

const ru = {
  'app.title': '💧 XiaomiAutomation · Xiaomi 17 Pro',
  'app.loading': '…',
  'app.nobridge': '⚠️ Не обнаружен интерфейс root-менеджера',
  'app.nobridge.hint': 'Эту страницу должен открывать root-менеджер: каждое действие выполняет команду через интерфейс root, который внедряет менеджер. В обычном браузере прав нет вообще — именно поэтому на странице и появляются ошибки.',
  'app.nobridge.fix': 'Вернитесь в менеджер и откройте WebUI модуля из списка модулей. На Magisk сначала установите KsuWebUI или MMRL — оба внедряют тот же интерфейс, поэтому модуль менять не нужно; на KernelSU / APatch и их форках (KernelSU Next, SukiSU Ultra) просто откройте его в менеджере. Из root-оболочки используйте webctl.sh — он делает ровно то же самое.',

  'btn.save': 'Сохранить',
  'btn.show': 'Показать',
  'btn.hide': 'Скрыть',
  'btn.add': '＋ Добавить',
  'btn.refresh': 'Обновить',
  'btn.restart': 'Перезапустить службу',
  'btn.logRefresh': 'Обновить',
  'btn.savePkg': 'ОК',
  'btn.del': 'Удалить',
  'btn.runWater': 'Полить',
  'btn.runTask': 'Запустить',
  'btn.recStart': 'Начать запись',
  'btn.recStop': 'Остановить запись',

  'card.prof.title': '📁 Профили задач',
  'card.prof.hint': 'У каждой задачи своё расписание. Встроенная задача «Ежедневный полив ICBC» работает по скрипту; новые задачи пишутся с экрана: если указано имя пакета, запись начинается при переходе в это приложение, приостанавливается при выходе и возобновляется при возврате; если пакет не указан, записывается весь включённый экран. Укажите пакет, чтобы записать свайпы назад от края; при записи без пакета крайние свайпы отсекаются. Запись приостанавливается на заблокированном экране — вернитесь и нажмите «Остановить запись», когда закончите.',
  'prof.schedHint': 'В назначенное время модуль включает экран, разблокирует устройство, выполняет задачу (встроенная задача ICBC открывает ICBC; записанные задачи открывают своё приложение или используют текущий экран), а затем выключает экран согласно настройке. По умолчанию 07:30 (чтобы не попасть в ночное окно обслуживания ICBC).',
  'card.pin.title': '🔓 PIN-код экрана блокировки',
  'card.pin.hint': 'От 4 до 8 цифр. Записывается только в локальный файл /data/adb/icbc_water/sched.conf (chmod 600); открытый пароль никогда не попадает в состояние, журнал или на эту страницу. Действует сразу.',
  'card.misc.title': '⚙️ Прочее',
  'card.chk.title': '🔬 Проверка запуска (сюда, если ничего не срабатывает)',
  'card.chk.hint': 'Каждое условие запуска показано и автоматически обновляется каждые 15 секунд. Значок ✗ — это причина, по которой задача не запустилась.',
  'card.log.title': '📜 Журнал работы',

  'lbl.unlockMode': 'Способ разблокировки',
  'lbl.watchOpen': 'Полить при первом открытии ICBC за день',
  'lbl.sleepAfter': 'Гасить экран после полива',
  'lbl.cleanupAfter': 'Очищать приложение из фона после выполнения',
  'lbl.cleanupHint': 'Целевое приложение закрывается после задачи, освобождая память; следующая задача стартует с чистого состояния.',
  'lbl.pkg': 'Пакет',
  'lbl.enable': 'Вкл.',
  'lbl.lang': 'Язык',

  'opt.pin': 'Слепой ввод PIN',
  'opt.swipe': 'Смахивание вверх (без пароля)',
  'opt.cleanup.on': 'Вкл. (закрывать приложение)',
  'opt.cleanup.off': 'Выкл. (оставлять в фоне)',
  'opt.cleanup.inherit': 'Как в общих настройках',

  'ph.pinSet': 'Уже задан (введите новый код для смены)',
  'ph.pinUnset': 'Не задан, введите 4–8 цифр',
  'ph.npName': 'Имя новой задачи (например, полив Alipay)',
  'ph.npPkg': 'Имя пакета (пусто = запись всего экрана)',
  'ph.pkgUnset': 'не задан (пишет включённый экран)',

  'st.todayDone': 'Сегодня выполнено ✅',
  'st.todayPending': 'Сегодня ещё не полито',
  'st.svcRun': 'работает',
  'st.svcStop': 'остановлена',
  'st.on': 'вкл.',
  'st.off': 'выкл.',

  'chk.svc': 'Фоновая служба',
  'chk.enable': 'Переключатель расписания',
  'chk.window': 'В окне запуска (60 мин после заданного времени)',
  'chk.windowYes': 'да (сейчас {now})',
  'chk.windowNo': 'вне окна',
  'chk.done': 'Задание по расписанию выполнено сегодня',
  'chk.doneYes': 'выполнено (сегодня повторов не будет)',
  'chk.doneNo': 'не выполнено',
  'chk.screen': 'Состояние экрана в момент запуска',
  'chk.screenOff': 'выключен (пробуждение напрямую)',
  'chk.screenOn': 'включён (заблокирован, затем разблокируется)',
  'chk.fail': 'Сбой подряд < 3',
  'chk.failN': '{n}',
  'chk.failBlocked': '{n} (приостановлено, сбросится через 6 часов)',

  'prof.script': 'скрипт',
  'prof.record': 'запись',
  'prof.doneToday': 'выполнено сегодня',
  'prof.notToday': 'сегодня не выполнялось',
  'prof.failN': 'ошибок: {n}',
  'prof.acts': 'действий: {n}',

  'prof.loadFail': 'Не удалось загрузить: {err}',
  'prof.empty': 'Задач пока нет — добавьте через форму ниже',
  'prof.bareNote': 'У «голой» задачи нет пакета, автоматическая очистка невозможна',

  'toast.pinEmpty': 'Новый код не введён',
  'toast.pinBad': 'PIN должен состоять из 4–8 цифр',
  'toast.pinSaved': 'PIN сохранён',
  'toast.saved': 'Сохранено',
  'toast.savedOn': 'Включено',
  'toast.savedOff': 'Отключено',
  'toast.nameEmpty': 'Введите имя задачи',
  'toast.nameBad': 'Имя задачи: только буквы, цифры, китайские иероглифы, подчёркивание и дефис, не длиннее 24 символов',
  'toast.pkgBad': 'Неверное имя пакета',
  'toast.addFail': 'Не удалось добавить задачу: {err}',
  'toast.added': 'Задача добавлена — нажмите «Начать запись»',
  'toast.enabled': 'Включено',
  'toast.disabled': 'Отключено',
  'toast.schedSaved': 'Расписание сохранено',
  'toast.trigOk': '«{name}» запущена! Если экран не загорелся, перезапустите службу.',
  'toast.pkgSaved': 'Целевое приложение сохранено: {pkg}',
  'toast.pkgCleared': 'Очищено (пишет включённый экран)',
  'toast.delConfirm': 'Удалить задачу «{name}» и её записанные действия?',
  'toast.deleted': 'Удалено',
  'toast.recStopped': 'Запись остановлена',
  'toast.recNoApp': 'Целевое приложение не найдено (убедитесь, что вы перешли в него)',
  'toast.recStart': 'Идёт запись! Перейдите в целевое приложение; при выходе запись приостановится; по завершении нажмите «Остановить запись»',
  'toast.svcRestarted': 'Служба перезапущена',
  'toast.cleanupSaved': 'Очистка фона включена',
  'toast.cleanupOff': 'Очистка фона отключена',
  'toast.profCleanupSaved': 'Настройка очистки для этой задачи сохранена',
  'toast.err': 'Ошибка: {err}',

  'log.empty': '(no log yet)',

  // v0.11.0 设备档案 / 跨设备回放缩放
  'dev.title': "📱 Профиль устройства",
  'dev.model': "Модель",
  'dev.label': "Отображаемое имя",
  'dev.apply': "Включить переопределение",
  'dev.apply.hint': "Выключено = базовые измеренные значения 17 Pro (рекомендуется). Включено = значения ниже.",
  'dev.sw': "Ширина (px)",
  'dev.sh': "Высота (px)",
  'dev.d': "ID дисплея",
  'dev.dpi': "Плотность (DPI)",
  'dev.pin': "Клавиатура экрана блокировки",
  'dev.detect': "🔍 Определить этот телефон",
  'dev.detect.ok': "Параметры телефона определены — проверьте и сохраните",
  'dev.detect.nothing': "Параметры не определены — заполните вручную",
  'dev.bad.fields': "Недопустимое значение: {f}",
  'dev.stable': "Стабильно",
  'dev.testing': "Тестируется",
  'dev.stable.hint': "Эта модель проверена; используются измеренные значения 17 Pro",
  'dev.testing.hint': "«Тестируется» означает, что модель ещё не проверена — это не мешает сохранению и работе",
  'dev.status.hint': "«Стабильно / Тестируется» — состояние проверки модели, а не состояние работы; сохранение оно не блокирует.",
  'dev.saved': "Профиль устройства сохранён",
  'scale.title': "📐 Масштабирование между устройствами",
  'scale.hint': "Пересчитывает действия, записанные на другом телефоне, под разрешение этого экрана перед воспроизведением. По умолчанию выключено; нужно только если задача записана на телефоне с другим разрешением.",
  'opt.scale.off': "Без масштаба",
  'opt.scale.on': "Масштабировать",
  'toast.profScaleSaved': "Настройка масштаба сохранена для этой задачи",


  // v0.12.0 界面重构: 概览区 / 折叠分组 / 键名标签
  'hero.hint': 'По расписанию модуль будит экран, разблокирует, выполняет задачи и гасит экран. Разверните разделы ниже по мере надобности — изменения вступают в силу сразу.',
  'ui.collapse': 'Свернуть всё',
  'ui.expand': 'Развернуть всё',
  'prof.new': 'Добавить задачу: скриптовые задачи (встроенный полив ICBC) уже есть; всё, что вы создадите здесь, — записываемые.',
  'dev.hint.short': 'По умолчанию стоят измеренные значения 17 Pro — не меняйте их. На другом телефоне нажмите «Определить этот телефон», проверьте значения, затем поставьте «Включить переопределение».',
  'card.log.hint': 'Последние 60 строк',
  'foot.ver': 'Модуль {ver} · Язык {lang}',

  // v0.13.0 дни недели / запись всего экрана / паттерн / удаляемая встроенная задача
  'lbl.days': 'Дни недели',
  'days.hint': 'Задача без собственного списка дней следует этому. Автоматически запускаются только включённые дни; выключите все семь — расписание остановится (ручной запуск работает).',
  'day.1': 'пн',
  'day.2': 'вт',
  'day.3': 'ср',
  'day.4': 'чт',
  'day.5': 'пт',
  'day.6': 'сб',
  'day.7': 'вс',
  'opt.days.inherit': 'Как в глобальной',
  'btn.addIcbc': '＋ Вернуть встроенную задачу ICBC',
  'lbl.recMode': 'Режим записи',
  'opt.rec.pkg': 'Привязка к пакету',
  'opt.rec.all': 'Запись всего экрана',
  'prof.recModeHint': 'Привязка к пакету: запись начинается, когда приложение на переднем плане, и ставится на паузу при уходе. Без пакета: пишутся действия во всех приложениях — включая возврат на главный экран и жесты у края (повтор по умолчанию стартует с главного экрана).',
  'prof.allScope': 'Весь экран',
  'lbl.pHome': 'На главный экран перед повтором',
  'opt.pattern': 'Паттерн-разблокировка (сетка 3x3)',
  'card.pat.hint': 'Ведите пальцем по сетке или нажимайте точки по порядку; пропущенные средние точки добавляются автоматически, как в Android. Минимум 4 точки; после сохранения паттерн рисуется одним движением по расписанию.',
  'pat.unset': 'Не нарисован',
  'pat.set': 'Задан (нарисуйте новый и сохраните)',
  'btn.patSave': 'Сохранить паттерн',
  'btn.patClear': 'Стереть',
  'btn.unlockTest': '🔒 Проверить разблокировку (заблокировать и разблокировать)',
  'unlock.test.hint': 'Действительно блокирует экран, затем разблокирует — используется для калибровки сетки паттерна и клавиатуры PIN. Экран включится.',
  'dev.pat': 'Сетка паттерна блокировки',
  'chk.day': 'Сегодня день запуска',
  'chk.dayYes': 'да ({day})',
  'chk.dayNo': 'нет (сегодня ничего не запустится автоматически)',
  'toast.daysSaved': 'Дни сохранены',
  'toast.icbcRestored': 'Встроенная задача ICBC восстановлена',
  'toast.recModeSaved': 'Режим записи сохранён',
  'toast.pHomeSaved': 'Точка старта повтора сохранена',
  'toast.patBad': 'Нарисуйте минимум 4 точки без повторов',
  'toast.patSaved': 'Паттерн сохранён',
  'toast.patCleared': 'Паттерн стёрт',
  'toast.unlockTesting': 'Проверка разблокировки… (5-10 с)',
  'toast.unlockOk': 'Разблокировано ✅ координаты паттерна и PIN верны',
};

const DICTS = { 'zh-CN': zh, en: en, fr: fr, ru: ru };

let cur = DEFAULT_LANG;

// {name} 占位符替换; 未提供的占位符原样保留, 避免界面出现 "undefined"。
function fill(tpl, vars) {
  if (!vars) return tpl;
  return String(tpl).replace(/\{(\w+)\}/g, (m, k) => (
    Object.prototype.hasOwnProperty.call(vars, k) ? String(vars[k]) : m
  ));
}

export function t(key, vars) {
  const d = DICTS[cur] || zh;
  let s = d[key];
  if (s === undefined) s = zh[key];
  if (s === undefined) s = key;
  return fill(s, vars);
}

export function getLang() { return cur; }

export function langLabel(code) {
  const hit = LANGS.find((l) => l.code === code);
  return hit ? hit.label : code;
}

function readStore() {
  try { return localStorage.getItem(STORE_KEY) || ''; } catch (e) { return ''; }
}

function writeStore(code) {
  try { localStorage.setItem(STORE_KEY, code); } catch (e) {}
}

// 只接受白名单里的语言代码, 避免损坏的存储值把界面切到空字典。
export function normalize(code) {
  const c = String(code || '');
  if (DICTS[c]) return c;
  const short = c.split('-')[0];
  if (DICTS[short]) return short;
  return DEFAULT_LANG;
}

// 检测顺序: 用户上次选择 > 浏览器语言 > 默认中文。
export function detectLang() {
  const saved = normalize(readStore());
  if (saved !== DEFAULT_LANG) return saved;
  let nav = '';
  try { nav = navigator.language || ''; } catch (e) {}
  if (nav) {
    const n = normalize(nav);
    if (n !== DEFAULT_LANG) return n;
  }
  return DEFAULT_LANG;
}

// 把 index.html 上的 data-i18n / data-i18n-ph / data-i18n-title 替换成当前语言。
// 用 textContent 而非 innerHTML: 词典里没有 HTML, 天然免疫注入。
export function applyI18n(root) {
  const scope = root || document;
  cur = detectLang();
  try { document.documentElement.lang = cur; } catch (e) {}
  scope.querySelectorAll('[data-i18n]').forEach((el) => {
    el.textContent = t(el.getAttribute('data-i18n'));
  });
  scope.querySelectorAll('[data-i18n-ph]').forEach((el) => {
    el.setAttribute('placeholder', t(el.getAttribute('data-i18n-ph')));
  });
  scope.querySelectorAll('[data-i18n-title]').forEach((el) => {
    el.setAttribute('title', t(el.getAttribute('data-i18n-title')));
  });
  const sel = document.getElementById('lang');
  if (sel) sel.value = cur;
  return cur;
}

export function setLang(code) {
  cur = normalize(code);
  writeStore(cur);
  applyI18n(document);
  return cur;
}
