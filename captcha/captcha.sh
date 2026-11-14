# icbc_daily_water / captcha/captcha.sh  验证码求解进程的生命周期 (由 replay.sh / record.sh source)
# 只在回放或录制进行中运行一个 Python worker, 会话结束 (含异常退出) 即杀掉; 平时零开销。
#   cap_on            0 = 开关开启且 Termux Python 与求解器都在
#   cap_start MODE    MODE=replay: 起 worker, 经两条 FIFO 一问一答; MODE=record: worker 自己每 ~0.7 s 截屏检测
#   cap_check         (回放) 截屏检测, 有验证码就当场求解; 返回 1 = 解不出, 调用方按失败收尾
#   cap_stop          结束 worker, 清理 FIFO/标志文件 (可重复调用)
# 调用方需先设 M / BASE; CAP_LOGF 为求解日志 (默认模块日志 $M/log.txt)。
CAP_PREFIX=/data/data/com.termux/files/usr
CAP_PY=$CAP_PREFIX/bin/python
CAP_FLAG=$BASE/captcha.on     # 录制时: 验证码在屏 (record.sh 据此暂停录取)
CAP_PID=
CAP_IN=
CAP_OUT=

cap_on() {
  # sched.conf 的 CAPTCHA_SOLVE: 0 = 关; 缺省/其它 = 开 (前提是找得到 Python 且通过 cap_trust)
  CAP_V=$(sed -n 's/^CAPTCHA_SOLVE=//p' "$BASE/sched.conf" 2>/dev/null | head -1)
  [ "$CAP_V" = "0" ] && return 1
  [ -x "$CAP_PY" ] && [ -f "$M/captcha/capsolve.py" ] && cap_trust
}

# root 要执行的是 Termux 的解释器和库: 只接受「属主是 Termux 应用 uid、组/其他人不可写」的,
# 求解器脚本本身必须属 root 且他人不可写。不满足就不启用 (记一行日志说明原因)。
cap_perm_ok() {  # $1 路径 $2 期望 uid
  CAP_S=$(stat -c '%u %A' "$1" 2>/dev/null) || return 1
  [ "${CAP_S%% *}" = "$2" ] || return 1
  case "${CAP_S#* }" in ?????w*|????????w*) return 1;; esac
  return 0
}
cap_trust() {
  CAP_UID=$(stat -c %u /data/data/com.termux 2>/dev/null)
  case "$CAP_UID" in ''|0|*[!0-9]*) CAP_WHY="Termux app uid unknown"; return 1;; esac
  CAP_REAL=$(readlink -f "$CAP_PY" 2>/dev/null)
  for CAP_F in "$CAP_REAL" "$CAP_PREFIX" "$CAP_PREFIX/bin" "$CAP_PREFIX/lib" "$CAP_PREFIX"/lib/python3.*/site-packages; do
    cap_perm_ok "$CAP_F" "$CAP_UID" || { CAP_WHY="untrusted owner/mode: $CAP_F"; return 1; }
  done
  for CAP_F in "$M/captcha" "$M/captcha/capsolve.py"; do
    cap_perm_ok "$CAP_F" 0 || { CAP_WHY="solver not root-owned: $CAP_F"; return 1; }
  done
  return 0
}

cap_start() {
  CAP_MODE=$1
  : "${CAP_LOGF:=$M/log.txt}"
  CAP_WHY=
  if ! cap_on; then
    [ -n "$CAP_WHY" ] && echo "$(date +%m%d-%H%M) CAPTCHA disabled: $CAP_WHY" >> "$CAP_LOGF"
    return 1
  fi
  rm -f "$CAP_FLAG" "$BASE/captcha.idle" 2>/dev/null
  if [ "$CAP_MODE" = "replay" ]; then
    CAP_IN=$BASE/cap.in.$$; CAP_OUT=$BASE/cap.out.$$
    # 回放互斥 (replay.lock), 残留的只可能是上次被 kill -9 的回放留下的
    rm -f "$BASE"/cap.in.* "$BASE"/cap.out.* 2>/dev/null
    mkfifo "$CAP_IN" "$CAP_OUT" 2>/dev/null || { CAP_IN=; CAP_OUT=; return 1; }
  else
    CAP_IN=-; CAP_OUT=-
  fi
  # 绝对路径直调 (KSU busybox standalone 不走 PATH); Termux 的库路径只给 Python 自己,
  # capsolve 起 screencap/input 时会去掉它。-I: 忽略 PYTHON* 变量、不加用户 site、不把脚本目录/cwd
  # 放进 sys.path; -S: 不执行 site-packages 里的 .pth/sitecustomize (capsolve 自己把 site-packages 加回);
  # -B: 不写 __pycache__。HOME 不指向 Termux 家目录。
  env LD_LIBRARY_PATH=$CAP_PREFIX/lib HOME=$BASE TMPDIR=/data/local/tmp \
      CAP_LOG="$CAP_LOGF" CAP_STAMP="$BASE/captcha.refresh" CAP_IDLE="$BASE/captcha.idle" \
      "$CAP_PY" -I -S -B -X utf8 "$M/captcha/capsolve.py" worker "$CAP_MODE" $$ "$CAP_IN" "$CAP_OUT" "$CAP_FLAG" \
      </dev/null >/dev/null 2>>"$CAP_LOGF" &
  CAP_PID=$!
  if [ "$CAP_MODE" = "replay" ]; then
    # 读写方式打开 FIFO 不会阻塞, 也保证 worker 那端永远有对端 (不会读到 EOF)
    exec 7<>"$CAP_IN" 8<>"$CAP_OUT"
  fi
  return 0
}

cap_check() {
  [ -n "$CAP_PID" ] && [ -n "$CAP_IN" ] || return 0
  if ! kill -0 "$CAP_PID" 2>/dev/null; then
    echo "$(date +%m%d-%H%M) CAPTCHA worker gone, continue without solver" >> "$CAP_LOGF"
    cap_stop
    return 0
  fi
  echo check >&7
  CAP_RES=
  # 一次求解最多 3 张图 x (点选+刷新间隔), 150 s 足够; 超时说明 worker 卡死, 当作解不出
  if ! read -t 150 -r CAP_RES <&8; then
    echo "$(date +%m%d-%H%M) CAPTCHA_FAIL timeout" >> "$CAP_LOGF"
    cap_stop
    return 1
  fi
  case "$CAP_RES" in
    none\ *) return 0;;
    fail\ *) echo "$(date +%m%d-%H%M) CAPTCHA_FAIL $CAP_RES" >> "$CAP_LOGF"; return 1;;
    *) echo "$(date +%m%d-%H%M) CAPTCHA $CAP_RES" >> "$CAP_LOGF"; return 0;;
  esac
}

cap_stop() {
  if [ -n "$CAP_PID" ]; then
    kill "$CAP_PID" 2>/dev/null
    CAP_PID=
  fi
  if [ -n "$CAP_IN" ] && [ "$CAP_IN" != "-" ]; then
    exec 7>&- 8>&-
    rm -f "$CAP_IN" "$CAP_OUT" 2>/dev/null
  fi
  CAP_IN=; CAP_OUT=
  rm -f "$CAP_FLAG" "$BASE/captcha.idle" 2>/dev/null
}
