#!/bin/bash
# Spotify 代理启动器
#
# 用 CEF 的 --proxy-server 参数启动 Spotify，让 Spotify 的流量走本地 Clash 代理，
# 既不需要开 TUN 模式，也不占用 macOS 系统代理。
#
# 参数只在启动时生效，所以必须保证每次都是本脚本拉起 Spotify：
#   - Spotify 未运行                      -> 带参数启动
#   - 在运行，已带参数，代理通，也确实连着代理 -> 只激活窗口
#   - 在运行，但没带参数（或端口变了）        -> 退出后用参数重启
#   - 在运行，已带参数，但代理不通            -> 不重启（重启也没用），提示先修好 Clash
#   - 在运行，已带参数，代理也通，但没连着代理 -> 退出后用参数重启
#     防御性的：连接真断了的时候重启能救回来。但它治不了「歌全变灰」——
#     实测灰屏时 Spotify 一直连着代理、代理也通，重启也修不好。详见 README。
#
# 直接运行即可（./launcher.sh），也可由同目录的 .app 调用。详见 README.md。

set -uo pipefail

CLASH_DIR="${CLASH_DIR:-$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev}"
VERGE_YAML="$CLASH_DIR/verge.yaml"

# 代理连通性探测用的地址。必须挑一个会走代理（非中国）的域名，
# 否则探到的是直连，测不出代理本身通不通。
PROBE_URL="https://apresolve.spotify.com/"

# 从 Clash Verge 配置读取 mixed-port；读不到返回 1
read_mixed_port() {
  local port
  port=$(grep -E '^verge_mixed_port:' "$VERGE_YAML" 2>/dev/null | head -n1 | awk '{print $2}' | tr -d "\"'")
  case "$port" in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$port"
}

# Spotify 主进程的完整命令行；未运行则输出空
spotify_command() {
  local pid
  pid=$(pgrep -x Spotify 2>/dev/null | head -n1)
  [ -n "$pid" ] || return 0
  ps -o command= -p "$pid" 2>/dev/null
}

# 把 ps 的 etime（[[dd-]hh:]mm:ss）换算成秒
elapsed_seconds() {
  printf '%s\n' "$1" | tr -d ' ' | awk -F'[-:]' '
    NF == 4 { print $1*86400 + $2*3600 + $3*60 + $4; next }
    NF == 3 { print $1*3600 + $2*60 + $3; next }
    NF == 2 { print $1*60 + $2 }
  '
}

# Spotify 是否真的连着代理端口；$1 = 代理端口
# 判断不了的情况一律当作「连着」，免得无谓地重启。
spotify_connected() {
  local pid net started conns
  pid=$(pgrep -x Spotify 2>/dev/null | head -n1)
  [ -n "$pid" ] || return 0

  # 刚起来这一分钟里可能还没建连，不判断
  started=$(elapsed_seconds "$(ps -o etime= -p "$pid" 2>/dev/null)")
  if [ -n "$started" ] && [ "$started" -lt 60 ]; then
    return 0
  fi

  # 出网连接属于 Spotify 的网络服务子进程，不在主进程上
  net=$(pgrep -P "$pid" -f 'utility-sub-type=network.mojom.NetworkService' 2>/dev/null | head -n1)
  [ -n "$net" ] || return 0

  # 不用管道接 grep：grep -q 提前退出会给 lsof 发 SIGPIPE，
  # 在 pipefail 下整个管道会返回非 0，把「连着」误判成「没连着」。
  conns=$(lsof -nP -a -p "$net" -iTCP 2>/dev/null)
  case "$conns" in
    *"->127.0.0.1:$1 (ESTABLISHED)"*) return 0 ;;
  esac
  return 1
}

# 从命令行里取出 --proxy-server 的值；没有则输出空
proxy_arg_of() {
  printf '%s\n' "$1" | tr ' ' '\n' | grep -m1 '^--proxy-server=' | cut -d= -f2-
}

# 该做什么：
#   $1 = Spotify 命令行（空表示未运行）
#   $2 = 期望的 --proxy-server 值
#   $3 = 代理是否可用（1/0）
#   $4 = Spotify 是否已连上代理（1/0）
decide_action() {
  if [ -z "$1" ]; then
    printf 'start\n'
  elif [ "$(proxy_arg_of "$1")" != "$2" ]; then
    printf 'restart\n'
  elif [ "$3" != 1 ]; then
    printf 'blocked\n'
  elif [ "$4" = 1 ]; then
    printf 'activate\n'
  else
    printf 'restart\n'
  fi
}

# 通过代理真的发一次请求；通了返回 0
# 只看端口有没有人在监听是不够的：节点挂了的时候 mihomo 照样监听、
# 照样接受连接，然后在往上连的时候失败。
proxy_works() {
  curl -s -o /dev/null --max-time 5 -x "$1" "$PROBE_URL" >/dev/null 2>&1
}

# 启动后确认参数真的生效了 —— open --args 对已在运行的实例会被静默忽略
wait_for_proxy() {
  local have i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    have=$(proxy_arg_of "$(spotify_command)")
    [ "$have" = "$1" ] && return 0
    sleep 1
  done
  return 1
}

# 提示信息：终端里跑就打印，从 .app 里跑就弹窗
notify() {
  if [ -t 1 ]; then
    printf '%s\n' "$1" >&2
  else
    osascript -e "display dialog \"$1\" buttons {\"好\"} default button 1 with icon caution with title \"Spotify 代理启动器\"" >/dev/null 2>&1
  fi
}

# 让用户确认是否继续；返回 0 表示继续
confirm() {
  if [ -t 1 ]; then
    printf '%s [y/N] ' "$1" >&2
    read -r ans
    [ "$ans" = y ] || [ "$ans" = Y ]
  else
    osascript -e "display dialog \"$1\" buttons {\"取消\", \"仍然启动\"} default button \"取消\" with icon caution with title \"Spotify 代理启动器\"" 2>/dev/null | grep -q '仍然启动'
  fi
}

# 退出 Spotify；正常退出失败则 SIGTERM，仍失败返回 1
quit_spotify() {
  osascript -e 'tell application "Spotify" to quit' >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8; do
    pgrep -x Spotify >/dev/null || return 0
    sleep 1
  done
  pkill -x Spotify >/dev/null 2>&1
  for _ in 1 2 3; do
    pgrep -x Spotify >/dev/null || return 0
    sleep 1
  done
  return 1
}

main() {
  local port url action proxy_ok connected
  if ! port=$(read_mixed_port); then
    notify "读不到 Clash Verge 的 mixed-port（${VERGE_YAML}）。请确认 Clash Verge 已安装并至少启动过一次。"
    exit 1
  fi
  url="http://127.0.0.1:$port"

  proxy_ok=0
  proxy_works "$url" && proxy_ok=1

  connected=0
  spotify_connected "$port" && connected=1

  action=$(decide_action "$(spotify_command)" "$url" "$proxy_ok" "$connected")

  if [ "$action" = activate ]; then
    open -a Spotify
    return 0
  fi

  if [ "$action" = blocked ]; then
    notify "Spotify 在运行，但代理 $url 不通，它现在连不上网。请先把 Clash Verge 弄通，再点一次启动器。"
    exit 1
  fi

  if [ "$proxy_ok" -eq 0 ]; then
    confirm "代理 $url 不通（Clash Verge 没在运行，或者节点连不上）。现在启动 Spotify 会完全连不上网。" || exit 0
  fi

  if [ "$action" = restart ] && ! quit_spotify; then
    notify "Spotify 没有退出，请手动退出后再点一次启动器。"
    exit 1
  fi

  open -a Spotify --args "--proxy-server=$url"

  if ! wait_for_proxy "$url"; then
    notify "Spotify 已经起来了，但 --proxy-server 参数没生效，代理没有启用。请手动退出 Spotify 后再点一次启动器。"
    exit 1
  fi
}

if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi