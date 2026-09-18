#!/bin/bash
# 生成启动器 App。
# 用法: ./build.sh [安装目录]   默认 /Applications，无写权限时退到 ~/Applications

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Spotify (代理).app"
DEST="${1:-/Applications}"

if [ ! -d "$DEST" ] || [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  echo "目标目录不可写，改装到 $DEST"
fi

APP="$DEST/$APP_NAME"
rm -rf "$APP"
osacompile -o "$APP" launcher.applescript
mkdir -p "$APP/Contents/Resources"
cp launcher.sh "$APP/Contents/Resources/launcher.sh"
chmod +x "$APP/Contents/Resources/launcher.sh"

# 图标：没有就现生成一份（需要 python3 + Pillow，读本机 Spotify 的图标作底图）
ICON="icon/SpotifyProxy.icns"
if [ ! -f "$ICON" ]; then
  python3 icon/make_icon.py >/dev/null || echo "警告: 图标生成失败，改用 App 默认图标"
fi
if [ -f "$ICON" ]; then
  cp "$ICON" "$APP/Contents/Resources/applet.icns"
  # CFBundleIconName 指向资源目录里的图标，优先级高于 CFBundleIconFile，
  # 不删掉的话上面这行拷贝不会生效。
  plutil -remove CFBundleIconName "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# osacompile 会先签名，之后拷进去的文件会让签名失效，所以重新做一次 ad-hoc 签名。
# 不重签的话 App 平时也能跑，但一旦带上 quarantine 属性（AirDrop/下载/压缩包解压）
# 就会被 Gatekeeper 判定为「已损坏」。
codesign --force -s - "$APP" >/dev/null 2>&1 || echo "警告: 重新签名失败（App 通常仍可使用）"

touch "$APP"  # 让 Finder / Dock 重新读取图标
echo "已生成: $APP"