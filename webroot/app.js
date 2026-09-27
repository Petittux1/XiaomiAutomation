// icbc_daily_water WebUI 逻辑 v0.10.0 (多任务 Profiles + 操作录制 + 多语言 + 后台清理)
// 走 KernelSU 注入的 ksu 接口执行 root 命令
import { exec, toast, moduleInfo } from './kernelsu.js';
import { t, setLang, getLang, langLabel, applyI18n, LANGS } from './i18n.js';

const W = '/data/adb/modules/icbc_daily_water/webctl.sh';
const $ = (id) => document.getElementById(id);
let busy = false;
let recPoll = null;   // 录制状态轮询定时器

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
function isErr(r) { return String(r || '').indexOf('ERR') === 0; }

// ---------- 状态加载 ----------
function chkRow(name, state, good) {
  return '<div class="ck"><span>' + esc(name) + '</span><span class="' + (good ? 'ok' : 'bad') + '">' + esc(state) + '</span></div>';
}

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
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
  }
  // 今日状态
  const td = $('today');
  if (cfg._today === 'DONE') { td.textContent = t('st.todayDone'); td.className = 'pill ok'; }
  else { td.textContent = t('st.todayPending'); td.className = 'pill warn'; }
  // 时间与开关
  const tt = cfg.SCHED_TIME || '0730';
  $('time').value = tt.slice(0, 2) + ':' + tt.slice(2);
  $('enable').checked = cfg.SCHED_ENABLE === '1';
  $('watch').checked = cfg.WATCH_OPEN === '1';
  $('sleep').checked = cfg.SLEEP_AFTER === '1';
  // 老配置里没有 CLEANUP_AFTER 时保持模块默认值(开), 与 service.sh 的回落一致。
  $('cleanup').checked = (cfg.CLEANUP_AFTER === undefined ? '1' : cfg.CLEANUP_AFTER) === '1';
  $('mode').value = cfg.UNLOCK_MODE === 'swipe' ? 'swipe' : 'pin';
  $('pin').placeholder = (cfg.PIN && cfg.PIN.length > 0) ? t('ph.pinSet') : t('ph.pinUnset');
  // 触发检查
  const svcRun = cfg._svc === 'running';
  const enabled = cfg.enable === '1';
  const screenOff = cfg.screen === '0';
  const winOk = cfg.window_ok === 'yes';
  const doneOk = cfg.done_ok === 'yes';
  const failN = parseInt(cfg._fail || '0', 10);
  const failOk = failN < 3;
  const rows = [
    chkRow(t('chk.svc'), svcRun ? t('st.svcRun') : t('st.svcStop'), svcRun),
    chkRow(t('chk.enable'), enabled ? t('st.on') : t('st.off'), enabled),
    chkRow(t('chk.window'), winOk ? t('chk.windowYes', { now: cfg.now || '' }) : t('chk.windowNo'), winOk),
    chkRow(t('chk.done'), doneOk ? t('chk.doneYes') : t('chk.doneNo'), !doneOk),
    chkRow(t('chk.screen'), screenOff ? t('chk.screenOff') : t('chk.screenOn'), true),
    chkRow(t('chk.fail'), failOk ? t('chk.failN', { n: failN }) : t('chk.failBlocked', { n: failN }), failOk)
  ];
  $('chk').innerHTML = rows.join('');
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
  const gloSched = ($('time').value || '07:30').replace(':', '');
  const gloClean = $('cleanup').checked;
  box.innerHTML = list.map((p) => {
    // 继承: p_sched/p_enable/pcleanup 为空时用全局
    const sched = p.psched || gloSched;
    const en = p.penable === '1' ? true : (p.penable === '' ? $('enable').checked : false);
    const isScript = (p.ptype || 'script') === 'script';
    const isRec = p.slug === recSlug;
    const hasPkg = !!(p.ppkg && p.ppkg !== '');
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
      '<div class="ph">' +
        '<span class="pn">' + esc(p.pname || p.slug) + '</span>' +
        '<span class="pill">' + esc(isScript ? t('prof.script') : t('prof.record')) + '</span>' +
        doneBadge +
        cleanBadge +
        (p.ptry && p.ptry !== '0' ? '<span class="pill">' + esc(t('prof.failN', { n: p.ptry })) + '</span>' : '') +
      '</div>' +
      '<div class="pm">' +
        '<span>' + esc(t('lbl.pkg')) + '</span>' +
        '<input class="pkgbox" data-act="pPkg" value="' + esc(p.ppkg || '') + '" placeholder="' + esc(t('ph.pkgUnset')) + '"' + (isScript ? ' disabled' : '') + '>' +
        '<button class="small" data-act="pPkgSave"' + (isScript ? ' disabled' : '') + '>' + esc(t('btn.savePkg')) + '</button>' +
        (p.pacts && p.pacts !== '0' ? ' · ' + esc(t('prof.acts', { n: p.pacts })) : '') +
        (isScript || hasPkg ? '' : ' · ' + esc(t('prof.bareNote'))) +
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
        '<button class="small primary" data-act="pRun">' + esc(isScript ? t('btn.runWater') : t('btn.runTask')) + '</button>' +
        (isScript ? '' : '<button class="small' + (isRec ? ' rec-on' : '') + '" data-act="pRec" data-state="' + (isRec ? 'recording' : 'idle') + '">' + esc(isRec ? t('btn.recStop') : t('btn.recStart')) + '</button>') +
        (p.slug === 'icbc' ? '' : '<button class="small danger" data-act="pDel">' + esc(t('btn.del')) + '</button>') +
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
async function saveTime() {
  if (busy) return;
  const v = $('time').value; // HH:MM
  if (!/^\d{2}:\d{2}$/.test(v)) { toastMsg(t('toast.timeBad')); return; }
  const hhmm = v.replace(':', '');
  busy = true;
  const r = await run('settime ' + hhmm);
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.timeSaved'));
  loadStatus(); loadLog();
}

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
  const hhmm = ($('npTime').value || '07:30').replace(':', '');
  busy = true;
  const r = await run("profile add '" + name + "' '" + name + "' '" + pkg + "' " + hhmm);
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
  if (['pEnable', 'pCleanup', 'pTimeSave', 'pRun', 'pPkgSave', 'pDel', 'pRec'].indexOf(act) === -1) return;
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

// 切换语言后整页重绘: 静态文案由 applyI18n 处理, 动态文案(状态/任务卡/日志)重跑一次。
function onLangChange() {
  setLang($('lang').value);
  loadFoot();
  loadStatus();
  loadLog();
}

// ---------- 事件 ----------
$('btnTime').addEventListener('click', saveTime);
$('btnPin').addEventListener('click', savePin);
$('btnPAdd').addEventListener('click', addProfile);
$('btnShow').addEventListener('click', () => {
  const p = $('pin');
  const show = p.type === 'password';
  p.type = show ? 'text' : 'password';
  $('btnShow').textContent = show ? t('btn.hide') : t('btn.show');
});

$('lang').addEventListener('change', onLangChange);

$('enable').addEventListener('change', (e) => toggle('setenable', e.target.checked ? '1' : '0', t('toast.savedOn'), t('toast.savedOff')));
$('watch').addEventListener('change', (e) => toggle('setwatch', e.target.checked ? '1' : '0', t('toast.savedOn'), t('toast.savedOff')));
$('sleep').addEventListener('change', (e) => toggle('setsleep', e.target.checked ? '1' : '0', t('toast.savedOn'), t('toast.savedOff')));
$('cleanup').addEventListener('change', (e) => toggle('setcleanup', e.target.checked ? '1' : '0', t('toast.cleanupSaved'), t('toast.cleanupOff')));
$('mode').addEventListener('change', (e) => toggle('setmode', e.target.value, null, null));

$('profs').addEventListener('click', (e) => onProfAct(e, 'click'));
$('profs').addEventListener('change', (e) => onProfAct(e, 'change'));

$('btnTrigger').addEventListener('click', async () => {
  if (busy) return;
  busy = true;
  const r = await run('trigger');
  busy = false;
  if (isErr(r)) { errToast(r); return; }
  toastMsg(t('toast.trigAll'));
  setTimeout(loadStatus, 3000);
});

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

// 初次加载: 先定语言(静态文案立即替换), 再拉状态
buildLangSelect();
applyI18n(document);
loadFoot();
loadStatus();
loadLog();
setInterval(() => { loadStatus(); }, 15000);
