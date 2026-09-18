#!/bin/bash
# 临时诊断工具：抓「Spotify 歌全变灰」发生时的现场。
#
# 背景：这台机器在电池上每 ~16 分钟 DarkWake 一次，唤醒瞬间到代理节点的路由不通，
# Spotify 走代理的连接会成批失败。但实测它自己会重连（13:53 那次 1 秒就接上了），
# 所以「为什么界面一直灰着」还没解释清楚。这个脚本持续记录三层状态，
# 等下次复现时就有现场可查。
#
# 用法：
#   tools/spotify-proxy-watch.sh &
#   kill "$(cat /tmp/spotify-proxy-watch.pid)"      # 停止
#
# 日志：~/Library/Logs/spotify-proxy-watch.log
#   - 只在 Spotify 运行时才探测（15 秒一次）；没在跑就 60 秒一次且不探测，省电。
#   - 只在「状态有变化」和「睡眠唤醒后」记录，另有 ~5 分钟一次的心跳。
#
# 记录字段（每行一份快照，key=value）：
#   ts       采样时刻
#   why      为什么记这一行：START / WAKE / CHANGE / HEARTBEAT / STOP
#   gap      距上次采样的秒数（明显大于间隔就说明中间睡了）
#   proxy    通过代理发一次请求的结果：ok(耗时)/fail(http码,耗时)
#   sp_pid   Spotify 主进程 pid
#   sp_up    Spotify 已运行秒数
#   sp_arg   命令行里的 --proxy-server 是否等于当前端口（yes/no）
#   sp_conn  Spotify 网络子进程到代理端口的 ESTABLISHED 连接数
#   mx_sp    mihomo 眼里 Spotify 相关连接数
#   if       默认路由网卡 + 它的 IPv4

set -uo pipefail

CLASH_DIR="${CLASH_DIR:-$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev}"
VERGE_YAML="$CLASH_DIR/verge.yaml"
MIHOMO_SOCK="/tmp/verge/verge-mihomo.sock"
PROBE_URL="https://apresolve.spotify.com/"

LOG="$HOME/Library/Logs/spotify-proxy-watch.log"
PIDFILE="/tmp/spotify-proxy-watch.pid"
MAX_LOG_BYTES=2000000

read_mixed_port() {
  local port
  port=$(grep -E '^verge_mixed_port:' "$VERGE_YAML" 2>/dev/null | head -n1 | awk '{print $2}' | tr -d "\"'")
  case "$port" in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$port"
}

# 秒数：把 ps 的 etime（[[dd-]hh:]mm:ss）换算成秒
elapsed_seconds() {
  printf '%s\n' "$1" | tr -d ' ' | awk -F'[-:]' '
    NF == 4 { print $1*86400 + $2*3600 + $3*60 + $4; next }
    NF == 3 { print $1*3600 + $2*60 + $3; next }
    NF == 2 { print $1*60 + $2 }
  '
}

spotify_pid() { pgrep -x Spotify 2>/dev/null | head -n1; }

# Spotify 网络服务子进程的 pid
spotify_net_pid() {
  local pid
  pid=$(spotify_pid)
  [ -n "$pid" ] || return 0
  pgrep -P "$pid" -f 'utility-sub-type=network.mojom.NetworkService' 2>/dev/null | head -n1
}

# 通过代理真的发一次请求：输出 "ok(0.72s)" 或 "fail(000,4.00s)"
proxy_probe() { # $1 = 代理 URL
  local out rc
  out=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 4 -x "$1" "$PROBE_URL" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf 'ok(%ss)\n' "${out##* }"
  else
    printf 'fail(%s,%ss)\n' "${out%% *}" "${out##* }"
  fi
}

# Spotify 网络子进程到代理端口的 ESTABLISHED 连接数
sp_conn() { # $1 = 端口
  local net conns n
  net=$(spotify_net_pid)
  [ -n "$net" ] || { printf 'n/a\n'; return; }
  conns=$(lsof -nP -a -p "$net" -iTCP 2>/dev/null)
  n=0
  while [ -n "$conns" ]; do
    case "$conns" in
      *"->127.0.0.1:$1 (ESTABLISHED)"*) n=$((n + 1)) ;;
    esac
    case "$conns" in
      *$'\n'*) conns=${conns#*$'\n'} ;;
      *) conns="" ;;
    esac
  done
  printf '%s\n' "$n"
}

# mihomo 眼里的 Spotify 连接数
mihomo_sp() {
  [ -S "$MIHOMO_SOCK" ] || { printf 'n/a\n'; return; }
  curl -s --unix-socket "$MIHOMO_SOCK" http://localhost/connections 2>/dev/null \
    | grep -oi '"host":"[^"]*spotify[^"]*"' | wc -l | tr -d ' '
}

# 默认路由网卡 + 它的 IPv4
default_iface() {
  local dev ip
  dev=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
  [ -n "$dev" ] || { printf 'none\n'; return; }
  ip=$(ipconfig getifaddr "$dev" 2>/dev/null)
  printf '%s/%s\n' "$dev" "${ip:-no-ip}"
}

snapshot() { # $1 = why  $2 = gap
  local url port probe spid up arg net
  port=$(read_mixed_port) || port="?"
  url="http://127.0.0.1:$port"
  probe=$(proxy_probe "$url")

  spid=$(spotify_pid)
  if [ -n "$spid" ]; then
    up=$(elapsed_seconds "$(ps -o etime= -p "$spid" 2>/dev/null)")
    if [ "$(printf '%s\n' "$(ps -o command= -p "$spid" 2>/dev/null)" | tr ' ' '\n' | grep -m1 '^--proxy-server=' | cut -d= -f2-)" = "$url" ]; then
      arg=yes
    else
      arg=no
    fi
  else
    up="-"; arg="-"
  fi

  printf '%s why=%s gap=%ss proxy=%s sp_pid=%s sp_up=%ss sp_arg=%s sp_conn=%s mx_sp=%s if=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$probe" "${spid:--}" "${up:--}" "$arg" \
    "$(sp_conn "$port")" "$(mihomo_sp)" "$(default_iface)" >>"$LOG"
}

main() {
  echo $$ >"$PIDFILE"
  : >"$LOG"
  echo "--- 监视开始 (pid $$)，日志 $LOG ---" >>"$LOG"

  local last now gap prev_sig sig i probe spid primed
  last=$(date +%s)
  prev_sig=""
  primed=0
  i=0
  snapshot START 0

  while :; do
    # 日志太大就重开一份，免得无限增长
    if [ -f "$LOG" ] && [ "$(wc -c <"$LOG")" -gt "$MAX_LOG_BYTES" ]; then
      mv "$LOG" "$LOG.1"
      echo "--- 日志轮转 ---" >"$LOG"
    fi

    spid=$(spotify_pid)
    if [ -n "$spid" ]; then
      sleep 15
    else
      sleep 60
    fi

    now=$(date +%s)
    gap=$((now - last))
    last=$now
    i=$((i + 1))

    # 没在跑 Spotify 就不频繁探测：只在唤醒后、或每 ~20 次采样记一次心跳，
    # 免得日志长时间完全静默，分不清「Spotify 没跑」还是「监视器死了」
    if [ -z "$spid" ] && [ "$gap" -le 90 ] && [ "$i" -lt 20 ]; then
      continue
    fi

    probe=$(proxy_probe "http://127.0.0.1:$(read_mixed_port || echo '?')")
    # 签名只看两件真正有意义的事：代理通不通、Spotify 还连不连着。
    # 连接数和探测耗时本身一直在小幅抖动，拿它们做变化判据会把日志淹掉。
    case "$probe" in
      ok*) pflag=ok ;;
      *) pflag=fail ;;
    esac
    case "$(sp_conn "$(read_mixed_port || echo '?')")" in
      0) cflag=0 ;;
      *) cflag=1 ;;
    esac
    sig="$pflag|$cflag"

    if [ "$gap" -gt 90 ]; then
      snapshot WAKE "$gap"
      prev_sig="$sig"
      primed=1
      i=0
    elif [ "$primed" -eq 0 ]; then
      # 第一圈只把基准状态存下来：START 那行已经记过当前状态了，
      # 不回填 prev_sig 的话这一圈必然和空串不等，必然记一次假的 CHANGE
      prev_sig="$sig"
      primed=1
    elif [ "$sig" != "$prev_sig" ]; then
      snapshot CHANGE "$gap"
      prev_sig="$sig"
      i=0
    elif [ "$i" -ge 20 ]; then
      snapshot HEARTBEAT "$gap"
      i=0
    fi
  done
}

if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi