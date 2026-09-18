#!/bin/bash
# launcher.sh 里纯逻辑部分的测试：端口读取、参数提取、四态判断、etime 换算。
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
CMD="/Applications/Spotify.app/Contents/MacOS/Spotify --proxy-server=$URL"
check "未运行" "start" "$(decide_action '' "$URL" 1 1)"
check "未运行、代理也不通" "start" "$(decide_action '' "$URL" 0 1)"
check "已带参数，代理通，连着" "activate" "$(decide_action "$CMD" "$URL" 1 1)"
check "在运行但没带参数" "restart" "$(decide_action '/Applications/Spotify.app/Contents/MacOS/Spotify' "$URL" 1 1)"
check "在运行但端口是旧的" "restart" "$(decide_action '/Applications/Spotify.app/Contents/MacOS/Spotify --proxy-server=http://127.0.0.1:7890' "$URL" 1 1)"
# 新端口是旧端口的前缀时不能误判成「已生效」，否则 Spotify 会一直用死掉的旧端口
check "新端口是旧端口的前缀" "restart" "$(decide_action "$CMD" 'http://127.0.0.1:5906' 1 1)"
check "参数后面还有别的参数" "activate" "$(decide_action "$CMD --foo=bar" "$URL" 1 1)"
# 已带参数但代理不通：重启也连不上，不能重启，只能提示
check "已带参数，代理不通" "blocked" "$(decide_action "$CMD" "$URL" 0 1)"
# 已带参数、代理也通，但 Spotify 没连着代理：睡眠唤醒后歌全灰就是这种，要重启
check "已带参数，代理通，但没连着" "restart" "$(decide_action "$CMD" "$URL" 1 0)"
# 参数不对时优先按参数判断，不受代理状态影响
check "没带参数 + 代理不通" "restart" "$(decide_action '/Applications/Spotify.app/Contents/MacOS/Spotify' "$URL" 0 1)"

echo "elapsed_seconds:"
check "分秒" "83" "$(elapsed_seconds '01:23')"
check "时分秒" "3723" "$(elapsed_seconds '01:02:03')"
check "天时分秒" "93784" "$(elapsed_seconds '1-02:03:04')"
check "带前导空格" "83" "$(elapsed_seconds ' 01:23')"

if [ "$fail" -gt 0 ]; then
  echo "失败 $fail 项"
  exit 1
fi
echo "全部通过"