// icbc_daily_water WebUI 逻辑 v0.12.5 (多任务 Profiles + 操作录制 + 多语言 + 后台清理 + 多设备档案 + 文档缓存自愈)
// 走 KernelSU 注入的 ksu 接口执行 root 命令
import { exec, toast, moduleInfo } from './kernelsu.js';
import { t, setLang, getLang, langLabel, applyI18n, LANGS } from './i18n.js';

const W = '/data/adb/modules/icbc_daily_water/webctl.sh';
const $ = (id) => document.getElementById(id);
let busy = false;
let recPoll = null;   // 录制状态轮询定时器

// 全局默认「浇水时间 / 定时开关」。原本这两处是直接读 card.time 卡片里的 DOM
// (#time / #enable) —— 那张卡在 v0.12.8 去重时被删了, 而读引用有三处(下面的
// loadStatus / loadProfiles 各一处), 漏一处就会在模块顶层抛 TypeError 把整个
// app.js 挂掉、WebUI 白屏。改成由 loadStatus() 从 webctl status 单向灌进来,
// loadProfiles() 只读不写。
// 值格式都是 HHMM(如 '0730'), 与 webctl status 的 sched= / enable= 一致。
let gloSched = '0730';
let gloEn = true;
// 全局每周执行日 (sched.conf 的 SCHED_DAYS)。任务自己的 P_DAYS 为空时用这个值。
// 格式与服务端一致: '1234567'=每天, '0'=一周都不跑, 升序子串如 '135'=周一三五。
let gloDays = '1234567';
// 图案点序 (本地草稿)。画完还没保存时也留在这里, 保存成功后由服务端回读。
let patSeq = '';

// ---------- WebUI 文档缓存自愈 ----------
// 现象: 模块升级后 WebUI 仍是旧界面, 必须卸载重装才更新。
// 原因: WebView 缓存的是「文档本身」。index.html 里的 ?v= 只能救子资源 ——
// 文档陈旧时, 新版本那个 ?v= 压根到不了浏览器。
// 做法: 构建期把模块版本注进本文件(见 tools/build_zip.sh), 运行时与设备上模块的
// 实际版本比对; 对不上就说明当前文档是旧的, 换一个新 URL 强制重新拉一次文档。
// 上限 3 次, 避免极端情况下把用户锁死在刷新循环里。
//
// 三处刻意设计, 都是踩出来的:
// 1) 「源码态」判定不用字符串哨兵(拿占位符原文跟 BUILD_VC 比): 打包时按占位符
//    做替换, 任何以哨兵字符串为判据的代码都会被一起消化掉, 结果产物里判断恒为
//    真、自愈直接变成死代码。改用「是不是纯数字 / 有没有 v 前缀」判定 ——
//    versionCode 永远是纯数字、version 永远带 v, 这两条判据在任何替换下都成立。
// 2) versionCode 与 version 都注入: 不同 KernelSU 版本的 moduleInfo() 暴露的
//    字段不一样, 少注入一个就可能整段自愈静默失效。
// 3) const key 必须算在「一致就清计数」之前: const 有暂时性死区, 被后面才声明
//    的辅助函数引用会抛 ReferenceError, 而这里是在模块顶层调用的, 一抛就整个
//    app.js 挂掉、WebUI 直接白屏。所以这里干脆不写辅助函数, 全部顺序执行。
const BUILD_VC = '__BUILD_VC__';
const BUILD_VER = '__BUILD_VER__';
const HEAL_KEY = 'icbw.heal';

function selfHeal() {
  if (!/^\d+$/.test(BUILD_VC) || BUILD_VER.charAt(0) !== 'v') return;   // 源码态不做处理
  let mi = null;
  try { mi = moduleInfo(); } catch (e) { return; }   // ksu 桥未就绪, 等下次重试
  if (!mi) return;
  // 设备侧版本标识: 优先 versionCode, 退化到 version 字符串; 两条都认。
  let devTag = '';
  let same = false;
  if (mi.versionCode != null && String(mi.versionCode).trim() !== '') {
    devTag = 'c:' + String(mi.versionCode).trim();
    if (devTag === 'c:' + BUILD_VC) same = true;
  }
  if (mi.version) {
    const v = String(mi.version).trim().replace(/^v/i, '');
    if (v === BUILD_VER.replace(/^v/i, '')) same = true;
    if (!devTag) devTag = 'v:' + v;
  }
  if (!devTag) return;                               // 拿不到任何版本信息, 放弃
  const key = HEAL_KEY + '.' + devTag;
  if (same) {                                        // 文档与模块一致, 清掉计数
    try { sessionStorage.removeItem(key); } catch (e) {}
    return;
  }
  // 文档与模块对不上 => 当前文档是旧的, 换新 URL 强制重拉一次
  let n = 0;
  try { n = parseInt(sessionStorage.getItem(key) || '0', 10) || 0; } catch (e) {}
  if (n >= 3) return;
  try { sessionStorage.setItem(key, String(n + 1)); } catch (e) {}
  try {
    const u = new URL(location.href);
    u.searchParams.set('_cb', BUILD_VC + '.' + Date.now());
    location.replace(u.href);
  } catch (e) { /* URL 改不动(例如 about:blank)就只能等用户手动刷新 */ }
}

// ---------- root 桥可用性 ----------
// WebUI 的所有操作都是「执行一条 root 命令」, 而执行通道是管理器注入的全局 ksu
// 对象: KernelSU(v0.8.0 起)、APatch、以及它们的分支(KernelSU Next / SukiSU Ultra)
// 都注入这个同名对象, KsuWebUI 和 MMRL 在 Magisk 上也注入同名对象。
// 这里必须用 typeof 判断: 对象不存在时直接引用 ksu 会抛 ReferenceError, 而这段
// 代码在模块顶层执行, 一抛整个 app.js 就挂掉、WebUI 直接白屏 —— 恰好是最需要
// 给出「为什么打不开」的时候。
function bridgeOk() {
  return typeof globalThis.ksu !== 'undefined' && globalThis.ksu !== null;
}

async function run(arg, options) {
  try {
    const r = await exec('sh ' + W + ' ' + arg, options || {});
    return (r.stdout || '').trim();
  } catch (e) {
    // PIN 通过 options.env 传递，不进入命令 argv；异常信息仍统一脱敏。
    if (String(arg).indexOf('setpin') === 0) return 'EXEC_ERR';
    return 'EXEC_ERR ' + (e && e.message ? e.message : e);
  }
}

function toastMsg(m) { try { toast(m); } catch (e) {} }

// webctl 的 ERR 文案保持技术原文(多语言下也不翻译), 这里只给它加一个本地化前缀,
// 这样英文/法语/俄语用户也能看懂"是哪个操作失败了"。
function errToast(raw) { toastMsg(t('toast.err', { err: raw })); }
// EXEC_ERR 是 run() 自己拼的前缀(桥没注入 / ksu.exec 抛异常), 它不以 ERR 开头。
// 只判 'ERR' 会把这类失败当成成功, 落进 else 分支弹出「已保存」的假成功 ——
// loadDevice/devDetect 单独判了 EXEC_ERR, 这里也必须认, 否则 16 处调用点全都在漏。
function isErr(r) {
  const s = String(r || '');
  return s.indexOf('ERR') === 0 || s.indexOf('EXEC_ERR') === 0;
}

// ---------- 状态加载 ----------
function chkRow(name, state, good) {
  return '<div class="ck"><span>' + esc(name) + '</span><span class="' + (good ? 'ok' : 'bad') + '">' + esc(state) + '</span></div>';
}

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ---------- 每周执行日 ----------
// 星期文案写成 7 个字面量调用, 刻意不写成「拼键」: 回归守卫靠「字面量调用」
// 收集 i18n 引用点, 动态拼出来的键会变成四种语言里都没人引用的孤儿键。
function dayLabel(n) {
  if (n === 2) return t('day.2');
  if (n === 3) return t('day.3');
  if (n === 4) return t('day.4');
  if (n === 5) return t('day.5');
  if (n === 6) return t('day.6');
  if (n === 7) return t('day.7');
  return t('day.1');
}

const DAYS = ['1', '2', '3', '4', '5', '6', '7'];

// '1234567' / '135' / '0' / '' -> ['1','3','5'] 这样的选中列表
function dayList(s) {
  const str = String(s == null ? '' : s);
  return DAYS.filter((d) => str.indexOf(d) !== -1);
}

// 选中列表 -> 服务端要的升序串; 一个都没选写 '0'(一周都不跑), 不写空
// (空在服务端的含义是「跟随全局」, 那是另一个按钮的事)
function joinDays(list) { return list.length ? list.join('') : '0'; }

// inherit=true 表示这串值来自全局设置, 按钮画成虚线边框 —— 「亮着」不等于「自己定的」
function dayBtnsHtml(str, inherit) {
  const on = dayList(str);
  return DAYS.map((d) => {
    const cls = ((on.indexOf(d) !== -1 ? 'on' : '') + (inherit ? ' inherit' : '')).trim();
    const lab = dayLabel(parseInt(d, 10));
    return '<button type="button" data-act="pDay" data-day="' + d + '" class="' + cls +
           '" title="' + esc(lab) + '">' + esc(lab) + '</button>';
  }).join('');
}

function renderDayBtns(box, str, inherit) {
  if (!box) return;
  box.innerHTML = dayBtnsHtml(str, inherit);
}

async function loadStatus() {
  const out = await run('status');
  const cfg = {};
  for (const line of out.split('\n')) {
    // webctl 键名是小写且单行多 token (svc=… enable=… screen=… now=… sched=… last_ago=…)，
    // 逐 token 解析; 独立行 window_ok=yes / done_ok=yes 同样命中
    const tkre = /([A-Za-z_0-9-]+)=(\S+)/g;
    let tt;
    while ((tt = tkre.exec(line)) !== null) cfg[tt[1]] = tt[2];
    if (line.indexOf('today: ') === 0) cfg._today = line.slice(7);
    if (line.indexOf('service: ') === 0) cfg._svc = line.slice(9);
    if (line.indexOf('fail_times: ') === 0) cfg._fail = line.slice(12);
    if (line.indexOf('update: ') === 0) cfg._upd = line.slice(8);
  }
  // 今日状态
  const td = $('today');
  if (cfg._today === 'DONE') { td.textContent = t('st.todayDone'); td.className = 'pill ok'; }
  else { td.textContent = t('st.todayPending'); td.className = 'pill warn'; }
  // 新包已就位、等重启合并 —— 这时版本角标已经是新版本了, 不说一句就会以为升级
  // 已经生效, 然后对着旧代码调半天参数(v0.13.1 图案坐标就是这么白折腾的)。
  const ub = $('upd');
  if (cfg._upd && cfg._upd !== 'none') { ub.hidden = false; ub.textContent = t('ui.updatePending', { neu: cfg._upd }); }
  else { ub.hidden = true; }
  // 时间与开关: 只灌给模块级变量, 不再写 DOM(见文件头 gloSched/gloEn 的说明)
  gloSched = cfg.SCHED_TIME || '0730';
  gloEn = cfg.SCHED_ENABLE === '1';
  $('watch').checked = cfg.WATCH_OPEN === '1';
  $('sleep').checked = cfg.SLEEP_AFTER === '1';
  // 老配置里没有 CLEANUP_AFTER 时保持模块默认值(开), 与 service.sh 的回落一致。
  $('cleanup').checked = (cfg.CLEANUP_AFTER === undefined ? '1' : cfg.CLEANUP_AFTER) === '1';
  $('mode').value = (cfg.UNLOCK_MODE === 'swipe' || cfg.UNLOCK_MODE === 'pattern') ? cfg.UNLOCK_MODE : 'pin';
  $('patBox').hidden = $('mode').value !== 'pattern';
  $('pin').placeholder = (cfg.PIN && cfg.PIN.length > 0) ? t('ph.pinSet') : t('ph.pinUnset');
  // 图案是否已保存: 服务端把点序脱敏成「已设置」, 这里只判断有没有值。
  // 本地已经画了但还没保存时, 以画布里的草稿为准, 别被后台轮询刷掉。
  if (!patSeq) {
    $('patStat').textContent = (cfg.PATTERN && cfg.PATTERN.length > 0) ? t('pat.set') : t('pat.unset');
  }
  // 全局执行日 (任务自己的 P_DAYS 为空时跟随它)
  gloDays = (cfg.SCHED_DAYS && /^[0-7]+$/.test(cfg.SCHED_DAYS)) ? cfg.SCHED_DAYS : '1234567';
  renderDayBtns($('daysGlobalBtns'), gloDays, false);
  // 内置工行任务是否还在: 被删掉才给「恢复」入口
  $('icbcRow').hidden = cfg.icbc_present !== 'no';
  // 触发检查
  const svcRun = cfg._svc === 'running';
  const enabled = cfg.enable === '1';
  const screenOff = cfg.screen === '0';
  const winOk = cfg.window_ok === 'yes';
  const doneOk = cfg.done_ok === 'yes';
  // 今天是不是执行日。day_ok 缺失(服务端还没重启到新版本)时按「是」显示,
  // 不拿一个读不到的字段去吓唬用户。
  const dayOk = cfg.day_ok !== 'no';
  const failN = parseInt(cfg._fail || '0', 10);
  const failOk = failN < 3;
  const rows = [
    chkRow(t('chk.svc'), svcRun ? t('st.svcRun') : t('st.svcStop'), svcRun),
    chkRow(t('chk.enable'), enabled ? t('st.on') : t('st.off'), enabled),
    chkRow(t('chk.window'), winOk ? t('chk.windowYes', { now: cfg.now || '' }) : t('chk.windowNo'), winOk),
    chkRow(t('chk.day'), dayOk ? t('chk.dayYes', { day: dayLabel(parseInt(cfg.day || '1', 10)) }) : t('chk.dayNo'), dayOk),
    chkRow(t('chk.done'), doneOk ? t('chk.doneYes') : t('chk.doneNo'), !doneOk),
    chkRow(t('chk.screen'), screenOff ? t('chk.screenOff') : t('chk.screenOn'), true),
    chkRow(t('chk.fail'), failOk ? t('chk.failN', { n: failN }) : t('chk.failBlocked', { n: failN }), failOk)
  ];
  $('chk').innerHTML = rows.join('');
  // 概览区: 守护服务状态也做成一枚徽标, 不用展开「触发检查」就能看到
  const sp = $('svcpill');
  if (sp) {
    sp.textContent = svcRun ? t('st.svcRun') : t('st.svcStop');
    sp.className = 'chip ' + (svcRun ? 'ok' : 'warn');
  }
  loadProfiles();
}

// ---------- Profiles ----------
async function loadProfiles() {
  const out = await run('profiles');
  // 录制状态恢复: 页面刷新/加载时, 若后台正在录制, 把对应任务卡的按钮恢复为「停止录制」并继续轮询
  let recSlug = null;
  const st = await run('record status');
  if (st.indexOf('recording=yes') === 0) {
    const m = st.match(/\bname=(\S+)/);
    if (m) recSlug = m[1];
    if (!recPoll) { recPoll = setInterval(pollRec, 3000); }
  }
  const box = $('profs');
  if (!out || out.indexOf('EXEC_ERR') === 0) {
    box.innerHTML = '<p class="midi">' + esc(t('prof.loadFail', { err: out })) + '</p>';
    return;
  }
  const list = [];
  for (const line of out.split('\n')) {
    const m = line.match(/^profile=(\S+)\s+(.*)$/);
    if (!m) continue;
    const p = { slug: m[1] };
    const tkre = /([A-Za-z_0-9-]+)=(\S+)/g;
    let tt;
    while ((tt = tkre.exec(m[2])) !== null) p[tt[1]] = tt[2];
    list.push(p);
  }
  if (!list.length) { box.innerHTML = '<p class="midi">' + esc(t('prof.empty')) + '</p>'; return; }
  // gloSched/gloEn 用模块级的(loadStatus 已灌好), 不再从 DOM 读 —— 那两个元素
  // 随 card.time 卡片一起删掉了, 这里再读就是顶层 TypeError 白屏。
  const gloClean = $('cleanup').checked;
  box.innerHTML = list.map((p) => {
    // 继承: p_sched/p_enable/pcleanup 为空时用全局
    const sched = p.psched || gloSched;
    const en = p.penable === '1' ? true : (p.penable === '' ? gloEn : false);
    const isScript = (p.ptype || 'script') === 'script';
    const isRec = p.slug === recSlug;
    const hasPkg = !!(p.ppkg && p.ppkg !== '');
    // 录制方式 / 回放起点 / 执行日 (P_DAYS 空 = 跟随全局 gloDays)
    const isAll = p.pscope === 'all';
    const homeOn = p.phome !== '0';
    const ownDays = !!(p.pdays && p.pdays !== '');
    // 该任务的实际清理开关: P_CLEANUP 覆盖全局, 都没有时回落到全局(与服务端一致)。
    let cleanOn;
    if (p.pcleanup === '1') cleanOn = true;
    else if (p.pcleanup === '0') cleanOn = false;
    else cleanOn = gloClean;
    const doneBadge = p.pdone === 'yes'
      ? '<span class="pill ok">' + esc(t('prof.doneToday')) + '</span>'
      : '<span class="pill warn">' + esc(t('prof.notToday')) + '</span>';
    // 清理徽标: 实际会不会退出 app 由 P_CLEANUP 覆盖全局决定, 裸录任务永远不算。
    const cleanBadge = hasPkg || isScript
      ? '<span class="pill' + (cleanOn ? ' ok' : ' warn') + '">🧹 ' + esc(cleanOn ? t('opt.cleanup.on') : t('opt.cleanup.off')) + '</span>'
      : '';
    return '<div class="prof" data-slug="' + esc(p.slug) + '">' +
      // 任务名独占一整行。名字和徽标挤在同一个 flex 行里时, 窄屏(17 Pro 约
      // 348dp)上徽标会把名字挤到只剩几像素, 而 min-width:0 又允许它继续缩 ——
      // 中文可以在任意两个字之间断行, 于是变成一个字一行竖着排; 拉丁文不肯断词
      // 所以看不出来。独占一行 + nowrap 从根上避免这件事。
      '<span class="pn" title="' + esc(p.pname || p.slug) + '">' + esc(p.pname || p.slug) + '</span>' +
      '<div class="pbadges">' +
        '<span class="pill">' + esc(isScript ? t('prof.script') : t('prof.record')) + '</span>' +
        (isAll ? '<span class="pill warn">' + esc(t('prof.allScope')) + '</span>' : '') +
        doneBadge +
        cleanBadge +
        (p.ptry && p.ptry !== '0' ? '<span class="pill">' + esc(t('prof.failN', { n: p.ptry })) + '</span>' : '') +
      '</div>' +
      '<div class="pm">' +
        '<span>' + esc(t('lbl.pkg')) + '</span>' +
        '<input class="pkgbox" data-act="pPkg" value="' + esc(p.ppkg || '') + '" placeholder="' + esc(isAll ? t('prof.allScope') : t('ph.pkgUnset')) + '"' + (isScript || isAll ? ' disabled' : '') + '>' +
        '<button class="small" data-act="pPkgSave"' + (isScript || isAll ? ' disabled' : '') + '>' + esc(t('btn.savePkg')) + '</button>' +
        (p.pacts && p.pacts !== '0' ? ' · ' + esc(t('prof.acts', { n: p.pacts })) : '') +
        (isScript || hasPkg || isAll ? '' : ' · ' + esc(t('prof.bareNote'))) +
      '</div>' +
      '<div class="prow2">' +
        '<label><input type="checkbox" data-act="pEnable" ' + (en ? 'checked' : '') + '> ' + esc(t('lbl.enable')) + '</label>' +
        '<input type="time" data-act="pTime" value="' + sched.slice(0, 2) + ':' + sched.slice(2) + '">' +
        '<button class="small" data-act="pTimeSave">' + esc(t('btn.savePkg')) + '</button>' +
        '<select class="cleanup" data-act="pCleanup" title="' + esc(t('lbl.cleanupAfter')) + '">' +
          '<option value=""' + (p.pcleanup ? '' : ' selected') + '>' + esc(t('opt.cleanup.inherit')) + '</option>' +
          '<option value="1"' + (p.pcleanup === '1' ? ' selected' : '') + '>' + esc(t('opt.cleanup.on')) + '</option>' +
          '<option value="0"' + (p.pcleanup === '0' ? ' selected' : '') + '>' + esc(t('opt.cleanup.off')) + '</option>' +
        '</select>' +
        (isScript ? '' :
        '<select class="cleanup" data-act="pScale" title="' + esc(t('scale.title')) + '">' +
          '<option value="0"' + (p.pscale === '1' ? '' : ' selected') + '>' + esc(t('opt.scale.off')) + '</option>' +
          '<option value="1"' + (p.pscale === '1' ? ' selected' : '') + '>' + esc(t('opt.scale.on')) + '</option>' +
        '</select>') +
        '<button class="small primary" data-act="pRun">' + esc(isScript ? t('btn.runWater') : t('btn.runTask')) + '</button>' +
        (isScript ? '' : '<button class="small' + (isRec ? ' rec-on' : '') + '" data-act="pRec" data-state="' + (isRec ? 'recording' : 'idle') + '">' + esc(isRec ? t('btn.recStop') : t('btn.recStart')) + '</button>') +
        '<button class="small danger" data-act="pDel">' + esc(t('btn.del')) + '</button>' +
      '</div>' +
      // 第二行: 录制方式 + 回放起点 (录制型) + 每周执行日 (所有任务)
      '<div class="prow2">' +
        (isScript ? '' :
          '<select class="cleanup" data-act="pScope" title="' + esc(t('lbl.recMode')) + '">' +
            '<option value="pkg"' + (isAll ? '' : ' selected') + '>' + esc(t('opt.rec.pkg')) + '</option>' +
            '<option value="all"' + (isAll ? ' selected' : '') + '>' + esc(t('opt.rec.all')) + '</option>' +
          '</select>' +
          '<label title="' + esc(t('lbl.pHome')) + '"><input type="checkbox" data-act="pHome"' + (homeOn ? ' checked' : '') + '> ' + esc(t('lbl.pHome')) + '</label>'
        ) +
        '<span class="dl" title="' + esc(t('lbl.days')) + '">' + esc(t('lbl.days')) + '</span>' +
        '<span class="daybtns" data-daybox>' + dayBtnsHtml(ownDays ? p.pdays : gloDays, !ownDays) + '</span>' +
        (ownDays ? '<button class="small ghost" data-act="pDaysInherit">' + esc(t('opt.days.inherit')) + '</button>' : '') +
      '</div>' +
    '</div>';
  }).join('');
}

// ---------- 录制状态轮询 ----------
async function pollRec() {
  // 录制中, 每 3 秒查一次 record status; 停止后刷新列表
  const out = await run('record status');
  const recOn = out.indexOf('recording=yes') === 0;
  if (!recOn) {
    if (recPoll) { clearInterval(recPoll); recPoll = null; }
    toastMsg(t('toast.recStopped'));
    loadProfiles(); loadLog();
    return;
  }
  // 目标 app 一直没识别到: 提示一次 (防长期 READY=0 白录)
  if (!window._recWarned && out.indexOf('READY') === -1) {
    const m = out.match(/\bname=(\S+)/);
    if (m) {
      window._recWarned = 1;
      toastMsg(t('toast.recNoApp'));
    }
  }
}

// ---------- 保存动作 ----------
// 保存浇水时间的 saveTime() 已随 card.time 卡片一起删除: 时间现在在 profile 行里
// 保存(onProfAct 的 pTimeSave -> `profile set <slug> p_sched`), 写的是 profile 自己的
// P_SCHED, 而 P_SCHED 才是调度器真正读的那个值。
// 命令行的 webctl.sh settime 仍然保留并已改成同步写 P_SCHED(见 webctl.sh)。

async function savePin() {
  if (busy) return;
  const v = $('pin').value.trim();
  if (!v) { toastMsg(t('toast.pinEmpty')); return; }
  if (!/^\d{4,8}$/.test(v)) { toastMsg(t('toast.pinBad')); return; }
  $('pin').value = '';
  busy = true;
  // 通过 KernelSU exec 的 env 传递，PIN 不出现在 shell 命令字符串/argv 中。
  const r = await run('setpin', { env: { WEBUI_PIN: v } });
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.pinSaved'));
  loadStatus();
}

// ---------- 图案解锁 ----------
// 九宫格从左上到右下编号 1..9, 与 service.sh pat_enter 的坐标推导一一对应。
// 画法: 按住拖过去, 或者逐格点 —— 两种都会走到同一个 patAdd()。
// 中间格自动补: Android 把「路过但没点」的中间格算进图案, 界面也必须补,
// 否则你在界面画 1→9, 手机端只点了两个角, 系统当成一条完全不同的线。
function patAdd(n) {
  n = String(n);
  if (!/^[1-9]$/.test(n) || patSeq.indexOf(n) !== -1) return;
  if (patSeq.length) {
    const a = parseInt(patSeq.charAt(patSeq.length - 1), 10);
    const b = parseInt(n, 10);
    const dr = Math.floor((b - 1) / 3) - Math.floor((a - 1) / 3);
    const dc = ((b - 1) % 3) - ((a - 1) % 3);
    const jump = (Math.abs(dr) === 2 && dc === 0) ||
                 (dr === 0 && Math.abs(dc) === 2) ||
                 (Math.abs(dr) === 2 && Math.abs(dc) === 2);
    if (jump) {
      const mid = String((a + b) / 2);
      if (patSeq.indexOf(mid) === -1) patSeq += mid;
    }
  }
  patSeq += n;
  renderPat();
}

function renderPat() {
  const pad = $('patPad');
  if (!pad) return;
  pad.querySelectorAll('.patdot').forEach((el) => {
    const n = el.dataset.n;
    const i = patSeq.indexOf(n);
    el.classList.toggle('on', i !== -1);
    // 选中格显示第几步 —— 校准几何时就是靠这个对「界面点序」和「实际滑动顺序」
    el.textContent = (i === -1) ? n : String(i + 1);
  });
  const svg = $('patSvg');
  const pts = [];
  patSeq.split('').forEach((n) => {
    const el = pad.querySelector('.patdot[data-n="' + n + '"]');
    if (!el) return;
    const r = el.getBoundingClientRect();
    const s = svg.getBoundingClientRect();
    pts.push((r.left + r.width / 2 - s.left).toFixed(1) + ',' + (r.top + r.height / 2 - s.top).toFixed(1));
  });
  $('patLine').setAttribute('points', pts.join(' '));
  $('patStat').textContent = patSeq ? patSeq.split('').join('·') : t('pat.unset');
}

function patHit(x, y) {
  const el = document.elementFromPoint(x, y);
  if (!el || !el.closest) return null;
  const d = el.closest('.patdot');
  return d ? d.dataset.n : null;
}

function bindPatPad() {
  const pad = $('patPad');
  if (!pad) return;
  let down = false;
  pad.addEventListener('pointerdown', (e) => {
    down = true;
    try { pad.setPointerCapture(e.pointerId); } catch (err) { /* 老 WebView 不支持就按普通事件走 */ }
    const n = patHit(e.clientX, e.clientY);
    if (n) patAdd(n);
    e.preventDefault();
  });
  pad.addEventListener('pointermove', (e) => {
    if (!down) return;
    const n = patHit(e.clientX, e.clientY);
    if (n) patAdd(n);
  });
  const up = () => { down = false; };
  pad.addEventListener('pointerup', up);
  pad.addEventListener('pointercancel', up);
  pad.addEventListener('pointerleave', up);
}

async function savePattern() {
  if (busy) return;
  if (patSeq.length < 4) { toastMsg(t('toast.patBad')); return; }
  busy = true;
  // 点序与 PIN 同规走 env, 不进命令字符串/argv
  const r = await run('setpattern', { env: { WEBUI_PATTERN: patSeq } });
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.patSaved'));
  loadStatus();
}

async function clearPattern() {
  if (busy) return;
  patSeq = '';
  renderPat();
  busy = true;
  const r = await run('setpattern', { env: { WEBUI_PATTERN: '' } });
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.patCleared'));
  loadStatus();
}

// 锁屏→解锁 往返测试: 服务端会先真锁一次再解锁, 用来校准图案宫格/PIN 键盘
async function testUnlock() {
  if (busy) return;
  busy = true;
  toastMsg(t('toast.unlockTesting'));
  const r = await run('unlock');
  busy = false;
  if (r.indexOf('UNLOCK_OK') === 0) { toastMsg(t('toast.unlockOk')); return; }
  // 没跑完就中止(锁没上/锁屏不要求凭据) —— 不是解不开, 是没得测, 给出人话原因。
  // 两个码写成字面量分支, 不做「前缀 + 变量」的动态取键: 回归守卫只认字面量引用,
  // 拼出来的半截键会被当成幽灵键(与 day.1..day.7 同一条规矩)。
  const sk = /^ERR unlock_skipped:\s*(\w+)/.exec(r || '');
  if (sk) {
    if (sk[1] === 'nolock') { errToast(t('unlock.skip.nolock')); return; }
    if (sk[1] === 'nocred') { errToast(t('unlock.skip.nocred')); return; }
    errToast(r);
    return;
  }
  errToast(r || 'no result');
}

async function toggle(key, val, okMsgOn, okMsgOff) {
  if (busy) return;
  busy = true;
  const r = await run(key + ' ' + val);
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(okMsgOn && val === '1' ? okMsgOn : (okMsgOff || t('toast.saved')));
  loadStatus();
}

// ---------- 新增任务 ----------
async function addProfile() {
  if (busy) return;
  const name = $('npName').value.trim();
  const pkg = $('npPkg').value.trim();
  if (!name) { toastMsg(t('toast.nameEmpty')); return; }
  // slug 校验须与 webctl 白名单一致: 中英数_横线, 无空格/特殊字符
  if (!/^[0-9A-Za-z_\u4e00-\u9fa5-]+$/.test(name) || name.length > 24) {
    toastMsg(t('toast.nameBad'));
    return;
  }
  // 包名可留空：空包名是“亮屏全量录制/回放当前画面”模式。
  if (pkg && !/^[0-9A-Za-z_.]+$/.test(pkg)) { toastMsg(t('toast.pkgBad')); return; }
  // 录制方式: 指定包名录取(原路径) / 全场录取(服务端强制空包名)
  const scope = ($('npScope') && $('npScope').value === 'all') ? 'all' : 'pkg';
  const hhmm = ($('npTime').value || '07:30').replace(':', '');
  busy = true;
  const r = await run("profile add '" + name + "' '" + name + "' '" +
                     (scope === 'all' ? '' : pkg) + "' " + hhmm + " " + scope);
  busy = false;
  if (isErr(r)) { errToast(t('toast.addFail', { err: r })); return; }
  toastMsg(t('toast.added'));
  // 新任务 slug = 任务名 (webctl 校验)
  $('npName').value = ''; $('npPkg').value = '';
  loadProfiles();
}

// ---------- Profile 操作 ----------
// 任务卡同时监听 click 和 change: 表单类控件(下拉/复选框)只在 change 时提交,
// 按钮只在 click 时提交。否则点一次下拉会先触发 click 再触发 change, 写两遍配置。
async function onProfAct(e, evType) {
  const btn = e.target.closest('button, input, select');
  if (!btn || !btn.dataset || !btn.dataset.act) return;
  const prof = btn.closest('.prof');
  if (!prof) return;
  const tag = btn.tagName;
  const isFormField = (tag === 'SELECT') || (tag === 'INPUT' && btn.type === 'checkbox');
  if (isFormField ? evType !== 'change' : evType !== 'click') return;
  const slug = prof.dataset.slug;
  const act = btn.dataset.act;
  // 只处理认识的动作; 像 pTime 这种纯输入框没有对应保存按钮, 直接忽略。
  if (['pEnable', 'pCleanup', 'pScale', 'pTimeSave', 'pRun', 'pPkgSave', 'pDel', 'pRec',
       'pScope', 'pHome', 'pDay', 'pDaysInherit'].indexOf(act) === -1) return;
  if (busy && act !== 'pEnable') return;
  busy = true;
  try {
    if (act === 'pEnable') {
      const r = await run('profile set ' + slug + ' p_enable ' + (btn.checked ? '1' : '0'));
      if (isErr(r)) { errToast(r); } else { toastMsg(btn.checked ? t('toast.enabled') : t('toast.disabled')); }
    } else if (act === 'pCleanup') {
      // 空值 = 跟随全局; 服务端会写成 P_CLEANUP= (空), 等同于未设置。
      const r = await run('profile set ' + slug + ' p_cleanup ' + (btn.value || ''));
      if (isErr(r)) { errToast(r); } else { toastMsg(t('toast.profCleanupSaved')); }
      loadProfiles();
    } else if (act === 'pScale') {
      // 0 = 不缩放(默认); 1 = 回放时按录制时分辨率等比换算。
      const r = await run('profile set ' + slug + ' p_scale ' + (btn.value === '1' ? '1' : '0'));
      if (isErr(r)) { errToast(r); } else { toastMsg(t('toast.profScaleSaved')); }
      loadProfiles();
    } else if (act === 'pScope') {
      // 录制方式: pkg=指定包名录取(原路径), all=全场录取(服务端会顺手清空 P_PKG)
      const r = await run('profile set ' + slug + ' p_scope ' + btn.value);
      if (isErr(r)) { errToast(r); } else { toastMsg(t('toast.recModeSaved')); }
      loadProfiles();
    } else if (act === 'pHome') {
      // 回放前先回桌面 (只在无包名时生效)
      const r = await run('profile set ' + slug + ' p_home ' + (btn.checked ? '1' : '0'));
      if (isErr(r)) { errToast(r); } else { toastMsg(t('toast.pHomeSaved')); }
    } else if (act === 'pDay') {
      // 点一天=把那天开/关。继承全局时, 当前生效值就是全局那串, 按它算增量 ——
      // 这样「全局是周一三五, 我只想关掉周三」点一下就成, 不必先把整周抄一遍。
      const daybox = prof.querySelector('[data-daybox]');
      if (!daybox) return;
      const on = Array.prototype.map.call(daybox.querySelectorAll('button.on'), (b) => b.dataset.day);
      const d = btn.dataset.day;
      const next = on.indexOf(d) === -1
        ? on.concat([d]).sort()
        : on.filter((x) => x !== d);
      const r = await run('profile set ' + slug + ' p_days ' + joinDays(next));
      if (isErr(r)) { errToast(r); } else { toastMsg(t('toast.daysSaved')); }
      loadProfiles();
    } else if (act === 'pDaysInherit') {
      const r = await run('profile set ' + slug + ' p_days ');
      if (isErr(r)) { errToast(r); } else { toastMsg(t('toast.daysSaved')); }
      loadProfiles();
    } else if (act === 'pTimeSave') {
      const ti = prof.querySelector('[data-act=pTime]');
      const hhmm = (ti.value || '07:30').replace(':', '');
      const r = await run('profile set ' + slug + ' p_sched ' + hhmm);
      if (isErr(r)) { errToast(r); } else { toastMsg(t('toast.schedSaved')); }
    } else if (act === 'pRun') {
      const r = await run('trigger ' + slug);
      if (isErr(r)) { errToast(r); return; }
      toastMsg(t('toast.trigOk', { name: slug }));
      setTimeout(loadStatus, 4000);
    } else if (act === 'pPkgSave') {
      const pgb = prof.querySelector('[data-act=pPkg]');
      const v = (pgb.value || '').trim();
      if (v && !/^[0-9A-Za-z_.]+$/.test(v)) { toastMsg(t('toast.pkgBad')); return; }
      const r = await run('profile set ' + slug + ' p_pkg ' + (v || ''));
      if (isErr(r)) { errToast(r); return; }
      toastMsg(v ? t('toast.pkgSaved', { pkg: v }) : t('toast.pkgCleared'));
      loadProfiles();
    } else if (act === 'pDel') {
      if (!window.confirm(t('toast.delConfirm', { name: slug }))) return;
      const r = await run('profile del ' + slug);
      if (isErr(r)) { errToast(r); return; }
      toastMsg(t('toast.deleted'));
      loadProfiles();
    } else if (act === 'pRec') {
      // 用 data-state 判断状态, 不看按钮文案 —— 切语言后依然可靠。
      if (btn.dataset.state === 'recording') {
        const r = await run('record stop ' + slug);
        if (isErr(r)) { errToast(r); return; }
        toastMsg(t('toast.recStopped'));
        if (recPoll) { clearInterval(recPoll); recPoll = null; }
        loadProfiles();
      } else {
        const r = await run('record start ' + slug);
        if (isErr(r)) { errToast(r); return; }
        window._recWarned = 0;
        toastMsg(t('toast.recStart'));
        btn.textContent = t('btn.recStop');
        btn.dataset.state = 'recording';
        btn.classList.add('rec-on');
        if (recPoll) clearInterval(recPoll);
        recPoll = setInterval(pollRec, 3000);
      }
    }
  } finally {
    busy = false;
  }
}

// ---------- 日志 ----------
async function loadLog() {
  const out = await run('log');
  $('log').textContent = out || t('log.empty');
}

// ---------- 底部版本信息 ----------
function loadFoot() {
  let ver = '';
  try {
    const mi = moduleInfo();
    if (mi && mi.version) ver = mi.version;
  } catch (e) {}
  const p = $('ver');
  if (ver) p.textContent = ver;
  $('footver').textContent = t('foot.ver', { ver: ver || p.textContent, lang: langLabel(getLang()) });
}

// ---------- 语言 ----------
function buildLangSelect() {
  const sel = $('lang');
  sel.innerHTML = LANGS.map((l) =>
    '<option value="' + esc(l.code) + '">' + esc(l.label) + '</option>'
  ).join('');
  sel.value = getLang();
}

// ---------- 折叠分组 ----------
// 页面默认只展开「定时」和「任务」, 其余收起来 —— 首屏不再是一大坨表单。
// 需要看全部时点概览区的「展开全部」, 之后再一键收起。
const SEC_SEL = 'main > details.sec';

function secsAll() { return document.querySelectorAll(SEC_SEL); }

function foldAll(open) {
  secsAll().forEach((d) => { d.open = open; });
  refreshFoldBtn();
}

function refreshFoldBtn() {
  const b = $('btnFold');
  if (!b) return;
  const anyOpen = Array.prototype.some.call(secsAll(), (d) => d.open);
  b.textContent = anyOpen ? t('ui.collapse') : t('ui.expand');
}

// 切换语言后整页重绘: 静态文案由 applyI18n 处理, 动态文案(状态/任务卡/日志)重跑一次。
function onLangChange() {
  setLang($('lang').value);
  loadFoot();
  refreshFoldBtn();
  loadStatus();
  loadLog();
}

// ---------- 事件 ----------
// (btnTime 的监听随 card.time 卡片一起删掉了 —— 保存时间现在走 profile 行的 pTimeSave)
$('btnPin').addEventListener('click', savePin);
$('btnPatSave').addEventListener('click', savePattern);
$('btnPatClear').addEventListener('click', clearPattern);
$('btnUnlockTest').addEventListener('click', testUnlock);
bindPatPad();
$('btnPAdd').addEventListener('click', addProfile);
$('btnShow').addEventListener('click', () => {
  const p = $('pin');
  const show = p.type === 'password';
  p.type = show ? 'text' : 'password';
  $('btnShow').textContent = show ? t('btn.hide') : t('btn.show');
});

$('lang').addEventListener('change', onLangChange);
$('btnFold').addEventListener('click', () => {
  const anyOpen = Array.prototype.some.call(secsAll(), (d) => d.open);
  foldAll(!anyOpen);
});

// (enable 的监听随 card.time 卡片一起删掉了 —— 定时开关现在按 profile 各自设,
//  走的是下面 profs 那条委托里的 pEnable -> `profile set <slug> p_enable`)
$('watch').addEventListener('change', (e) => toggle('setwatch', e.target.checked ? '1' : '0', t('toast.savedOn'), t('toast.savedOff')));
$('sleep').addEventListener('change', (e) => toggle('setsleep', e.target.checked ? '1' : '0', t('toast.savedOn'), t('toast.savedOff')));
$('cleanup').addEventListener('change', (e) => toggle('setcleanup', e.target.checked ? '1' : '0', t('toast.cleanupSaved'), t('toast.cleanupOff')));
$('mode').addEventListener('change', (e) => {
  // 先把图案画布亮出来再等保存回读: 切过去半天没反应的话, 用户会以为下拉是死的
  $('patBox').hidden = e.target.value !== 'pattern';
  toggle('setmode', e.target.value, null, null);
});

// 全局每周执行日 (只作用于「跟随全局」的任务)
$('daysGlobalBtns').addEventListener('click', async (e) => {
  const b = e.target.closest('button[data-day]');
  if (!b || busy) return;
  const box = $('daysGlobalBtns');
  const on = Array.prototype.map.call(box.querySelectorAll('button.on'), (x) => x.dataset.day);
  const d = b.dataset.day;
  const next = on.indexOf(d) === -1 ? on.concat([d]).sort() : on.filter((x) => x !== d);
  busy = true;
  const r = await run('setdays ' + joinDays(next));
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.daysSaved'));
  loadStatus();
});

// 恢复内置工行任务 (删掉之后这个按钮才可见)
$('btnAddIcbc').addEventListener('click', async () => {
  if (busy) return;
  busy = true;
  const r = await run('profile addicbc');
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.icbcRestored'));
  loadStatus();
});

// 录制方式选「全场录取」时包名没有意义, 直接禁掉并清空 —— 留着一个填得进字的框,
// 用户会以为填了会生效, 而服务端那边是强制清空的。
$('npScope').addEventListener('change', () => {
  const all = $('npScope').value === 'all';
  $('npPkg').disabled = all;
  if (all) $('npPkg').value = '';
});

$('profs').addEventListener('click', (e) => onProfAct(e, 'click'));
$('profs').addEventListener('change', (e) => onProfAct(e, 'change'));

// (btnTrigger 已随「立即浇水」去重删除 —— 运行任务统一走 profile 行的 pRun)

$('btnRestart').addEventListener('click', async () => {
  if (busy) return;
  busy = true;
  const r = await run('restart');
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.svcRestarted'));
  setTimeout(loadStatus, 2000);
});

$('btnRefresh').addEventListener('click', () => { loadStatus(); loadLog(); });
$('btnLog').addEventListener('click', loadLog);

// ---------- 设备档案 (v0.11.0) ----------
// 关键约定: 界面只把「检测结果预填给用户确认」, 绝不自动写配置。
// DEV_APPLY 是总闸, 关着(=默认)时各脚本根本不读 DEV_*, 用的是 17 Pro 实测基线。
let devDirty = false;

function devSet(id, v) { const e = $(id); if (e) e.value = (v == null ? '' : v); }

// 从 device get 的 key=value 行里取值。
// 只有 DEV_LABEL 需要把存储形态(下划线)还原成显示形态(空格)。
// 以前对所有键都做 _→空格, 会把 DEV_MODEL/DEV_STATUS 这类短标识也改写掉:
// 自动检测给的机型名是把非法字符换成 _ 得来的, 还原成空格后反而过不了保存校验。
function devParse(out) {
  const d = {};
  for (const line of String(out || '').split('\n')) {
    const m = line.match(/^(DEV_[A-Z_]+)=(.*)$/);
    if (m) d[m[1]] = (m[1] === 'DEV_LABEL') ? m[2].replace(/_/g, ' ') : m[2];
  }
  return d;
}

// 显示形态(空格) -> 存储形态(下划线)。device.conf 的标签键只认 [A-Za-z0-9_.-],
// 于是约定「存下划线、显空格」: 输入框允许用户写 'Xiaomi 11' 这种带空格的名字,
// 落盘前转成 Xiaomi_11, 读回来由 devParse 再转回空格显示。
function devToStore(s) { return String(s == null ? '' : s).trim().replace(/\s+/g, '_'); }

async function loadDevice() {
  const out = await run('device get');
  if (out.indexOf('EXEC_ERR') === 0) { return; }
  const d = devParse(out);
  if (devDirty) return;              // 用户正在改, 不要被后台轮询覆盖
  // 文件不存在时给 17 Pro 基线, 让界面永远有可读的值
  devSet('devApply',   (d.DEV_APPLIED === '1' || d.DEV_APPLY === '1') ? true : false);
  devSet('devModel',   d.DEV_MODEL  || '17pro');
  devSet('devLabel',   d.DEV_LABEL  || 'Xiaomi 17 Pro');
  devSet('devSW',      d.DEV_SW     || '1220');
  devSet('devSH',      d.DEV_SH     || '2656');
  devSet('devD',       (d.DEV_D     !== undefined && d.DEV_D !== '') ? d.DEV_D : '0');
  devSet('devDPI',     d.DEV_DPI    || '');
  devSet('devPX0',     d.DEV_PIN_X0 || '290');
  devSet('devPY0',     d.DEV_PIN_Y0 || '1015');
  devSet('devPDX',     d.DEV_PIN_DX || '320');
  devSet('devPDY',     d.DEV_PIN_DY || '210');
  // 图案宫格几何: 17 Pro 实测值(1220x2656 锁屏截图量点), 换机器覆盖后按覆盖值显示
  devSet('devPaX0',    d.DEV_PAT_X0 || '310');
  devSet('devPaY0',    d.DEV_PAT_Y0 || '1193');
  devSet('devPaDX',    d.DEV_PAT_DX || '300');
  devSet('devPaDY',    d.DEV_PAT_DY || '300');
  devRenderBadge(d);
}

// 徽标: 17 Pro 标「稳定」, 其余一律标「测试中」—— 不因为检测成功就改口。
function devRenderBadge(d) {
  const b = $('devBadge');
  if (!b) return;
  const applyOn = $('devApply') && $('devApply').checked;
  const model = ($('devModel') && $('devModel').value) || '';
  const isPro = (model === '17pro' || model === 'Xiaomi 17 Pro');
  let txt, cls;
  if (!applyOn) {
    txt = (isPro ? 'Xiaomi 17 Pro · ' : (model + ' · ')) + t('dev.stable');
    cls = 'pill ok';
  } else if (isPro) {
    // 17 Pro 开着覆盖: 数值通常与基线一致, 仍标稳定, 但要提示已偏离默认值
    txt = 'Xiaomi 17 Pro · ' + t('dev.stable');
    cls = 'pill ok';
  } else {
    txt = model + ' · ' + t('dev.testing');
    cls = 'pill warn';
  }
  b.textContent = txt;
  b.className = cls;
  // 「稳定 / 测试中」是「这个机型有没有被验证过」的静态标签, 不是运行状态,
  // 也不参与 devSave() 的任何判定 —— 但它黄色的样子很像卡住, 所以把含义显式写出来。
  b.title = (applyOn && !isPro) ? t('dev.testing.hint') : t('dev.stable.hint');
}

function devMarkDirty() {
  devDirty = true;
  devRenderBadge(null);
}

async function devDetect() {
  if (busy) return;
  busy = true;
  const out = await run('device detect');
  busy = false;
  // 桥没注入要说桥的事, 检测不到才说「手动填写」—— 旧版两句合成一句,
  // ksu.exec 抛异常时用户看到的是「未检测到本机参数」, 完全查不到真正原因。
  if (out.indexOf('EXEC_ERR') === 0) { errToast(out); return; }
  if (out.indexOf('DEV_DETECT=ok') === -1) { toastMsg(t('dev.detect.nothing')); return; }
  const d = devParse(out);
  if (d.DEV_MODEL) devSet('devModel', d.DEV_MODEL);
  // 显示名也一起回填: 以前不填, 档案里就会留下 loadDevice 兜底的 'Xiaomi 17 Pro',
  // 于是机型是 M2102K1C 而显示名写着 17 Pro —— 保存下来一份自相矛盾的档案。
  if (d.DEV_LABEL) devSet('devLabel', d.DEV_LABEL);
  if (d.DEV_SW)    devSet('devSW', d.DEV_SW);
  if (d.DEV_SH)    devSet('devSH', d.DEV_SH);
  if (d.DEV_DPI)   devSet('devDPI', d.DEV_DPI);
  // 显示 ID: 检测统一给 0, 只有当与当前值不同时才覆盖, 免得抹掉真机上的非 0 ID
  if (d.DEV_D !== undefined && d.DEV_D !== '' && $('devD') && $('devD').value !== d.DEV_D) {
    devSet('devD', d.DEV_D);
  }
  devDirty = true;
  devRenderBadge(null);
  toastMsg(t('dev.detect.ok'));
}

async function devSave() {
  if (busy) return;
  // 数值字段前端先自检一遍, 省得把非法值发到 root 侧
  const bad = [];
  const need = [['devSW','dev.sw',300],['devSH','dev.sh',300],['devD','dev.d',0],
                ['devDPI','dev.dpi',0],['devPX0','dev.pin',1],['devPY0','dev.pin',1],
                ['devPDX','dev.pin',1],['devPDY','dev.pin',1],
                ['devPaX0','dev.pat',1],['devPaY0','dev.pat',1],
                ['devPaDX','dev.pat',1],['devPaDY','dev.pat',1]];
  for (const [id, key, min] of need) {
    const v = ($(id) ? $(id).value : '').trim();
    if (v === '') continue;                       // 留空 = 保留原值
    if (!/^\d+$/.test(v)) { bad.push(t(key)); continue; }
    if (parseInt(v, 10) < min) { bad.push(t(key)); }
  }
  // 标签键必须先转成存储形态再校验、再发送。
  // v0.12.9 及以前拿显示形态去撞 /^[A-Za-z0-9_.-]+$/, 而 loadDevice() 兜底给的
  // 是 'Xiaomi 17 Pro'(带空格) —— 必然失败, 校验在发请求之前就 return 了,
  // 后端一个字节都收不到, 用户看到的现象正是「点保存没反应」。
  const model = devToStore($('devModel') ? $('devModel').value : '');
  const label = devToStore($('devLabel') ? $('devLabel').value : '');
  if (model && !/^[A-Za-z0-9_.-]+$/.test(model)) bad.push(t('dev.model'));
  if (label && !/^[A-Za-z0-9_.-]+$/.test(label)) bad.push(t('dev.label'));
  // bad 以前只 push 从没读过, 报错又只说「参数不合法」—— 数字明明全对却查不出是哪个
  // 字段, 用户只能判定成「保存功能坏了」。现在把字段名带出来。
  if (bad.length) { toastMsg(t('dev.bad.fields', { f: bad.join(', ') })); return; }

  const applyOn = $('devApply').checked;
  const isPro = (model === '17pro');
  // 状态标签: 只有 17 Pro 允许标「稳定」, 其余一律「测试中」, 界面不提供改写入口。
  const args = ['device set'];
  args.push('DEV_APPLY=' + (applyOn ? '1' : '0'));
  if (model) args.push('DEV_MODEL=' + model);
  if (label) args.push('DEV_LABEL=' + label);
  args.push('DEV_STATUS=' + (isPro ? 'stable' : 'testing'));
  const nums = [['devSW','DEV_SW'],['devSH','DEV_SH'],['devD','DEV_D'],['devDPI','DEV_DPI'],
                ['devPX0','DEV_PIN_X0'],['devPY0','DEV_PIN_Y0'],['devPDX','DEV_PIN_DX'],['devPDY','DEV_PIN_DY'],
                ['devPaX0','DEV_PAT_X0'],['devPaY0','DEV_PAT_Y0'],['devPaDX','DEV_PAT_DX'],['devPaDY','DEV_PAT_DY']];
  for (const [id, key] of nums) {
    const v = ($(id) ? $(id).value : '').trim();
    if (v !== '') args.push(key + '=' + v);
  }
  busy = true;
  const r = await run(args.join(' '));
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  devDirty = false;
  toastMsg(t('dev.saved'));
  loadDevice(); loadProfiles();
}

// 设备卡事件挂载
// 注意: 改版后卡片是 <details class="sec">, 不再有 .card 外层, 所以取最近的 <details>。
(function () {
  const box = $('devApply') ? $('devApply').closest('details') : null;
  if (!box) return;
  box.addEventListener('input', devMarkDirty);
  box.addEventListener('change', devMarkDirty);
  const bDet = $('btnDevDetect'), bSave = $('btnDevSave');
  if (bDet) bDet.addEventListener('click', devDetect);
  if (bSave) bSave.addEventListener('click', devSave);
})();

// 文档缓存自愈: 立刻试一次, 桥未就绪时再补两下。
selfHeal();
setTimeout(selfHeal, 400);
setTimeout(selfHeal, 1500);

// 初次加载: 先定语言(静态文案立即替换), 再拉状态
buildLangSelect();
applyI18n(document);
refreshFoldBtn();

// 缺桥时只显示整页提示, 不再往下走: 继续跑的话每 15 秒一次的轮询会全失败,
// 既是满屏 ERR 又是白耗电, 而且会把真正的原因(没注入 root 接口)淹掉。
if (!bridgeOk()) {
  const nb = $('nobridge');
  if (nb) nb.hidden = false;
} else {
  loadFoot();
  loadStatus();
  loadDevice();
  loadLog();
  setInterval(() => { loadStatus(); }, 15000);
}
