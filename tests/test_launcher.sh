#!/bin/bash
# launcher.sh 里纯逻辑部分的测试：端口读取、三态判断、端口探测。
# 不触碰真实 Clash 配置，也不启动/退出 Spotify。

set -uo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export CLASH_DIR="$TMP"
# shellcheck source=../launcher.sh
. ./launcher.sh

fail=0
check() { # $1=说明 $2=期望 $3=实际
  if [ "$2" = "$3" ]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1 (期望 '$2'，实际 '$3')"
    fail=$((fail + 1))
  fi
}

echo "read_mixed_port:"
printf 'verge_mixed_port: 59062\n' >"$TMP/verge.yaml"
check "普通配置" "59062" "$(read_mixed_port)"

printf 'verge_mixed_port: "7890"\n' >"$TMP/verge.yaml"
check "带引号" "7890" "$(read_mixed_port)"

printf 'enable_tun_mode: false\n' >"$TMP/verge.yaml"
read_mixed_port >/dev/null 2>&1
check "配置里没有该键" "1" "$?"

printf 'verge_mixed_port: abc\n' >"$TMP/verge.yaml"
read_mixed_port >/dev/null 2>&1
check "值不是数字" "1" "$?"

rm -f "$TMP/verge.yaml"
read_mixed_port >/dev/null 2>&1
check "配置文件不存在" "1" "$?"

echo "proxy_arg_of:"
check "有代理参数" "http://127.0.0.1:59062" "$(proxy_arg_of '/Applications/Spotify.app/Contents/MacOS/Spotify --proxy-server=http://127.0.0.1:59062')"
check "没有代理参数" "" "$(proxy_arg_of '/Applications/Spotify.app/Contents/MacOS/Spotify')"

echo "decide_action:"
URL="http://127.0.0.1:59062"
check "未运行" "start" "$(decide_action '' "$URL")"
check "已带参数" "activate" "$(decide_action "/Applications/Spotify.app/Contents/MacOS/Spotify --proxy-server=$URL" "$URL")"
check "在运行但没带参数" "restart" "$(decide_action '/Applications/Spotify.app/Contents/MacOS/Spotify' "$URL")"
check "在运行但端口是旧的" "restart" "$(decide_action '/Applications/Spotify.app/Contents/MacOS/Spotify --proxy-server=http://127.0.0.1:7890' "$URL")"
# 新端口是旧端口的前缀时不能误判成「已生效」，否则 Spotify 会一直用死掉的旧端口
check "新端口是旧端口的前缀" "restart" "$(decide_action '/Applications/Spotify.app/Contents/MacOS/Spotify --proxy-server=http://127.0.0.1:59062' 'http://127.0.0.1:5906')"
check "参数后面还有别的参数" "activate" "$(decide_action "/Applications/Spotify.app/Contents/MacOS/Spotify --proxy-server=$URL --foo=bar" "$URL")"

echo "port_open:"
# 自己起一个监听，不依赖本机是否在跑 Clash
nc -l 127.0.0.1 59987 >/dev/null 2>&1 &
listener=$!
sleep 1
port_open 59987 >/dev/null 2>&1
check "有监听的端口" "0" "$?"
kill "$listener" 2>/dev/null
wait "$listener" 2>/dev/null
port_open 59987 >/dev/null 2>&1
check "无人监听的端口" "1" "$?"

if [ "$fail" -gt 0 ]; then
  echo "失败 $fail 项"
  exit 1
fi
echo "全部通过"