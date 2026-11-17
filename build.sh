#!/bin/bash
# build.sh — 编译并打包 MikuPet.app
# 为什么必须打包成 .app：
#   1) 裸可执行文件没有 bundle identifier，UNUserNotificationCenter 会直接崩
#   2) LSUIElement 只有写进 Info.plist 才能真正不占 Dock
#   3) 桌面上放一个 .app 才能双击打开 / 拖到 Dock
set -e
cd "$(dirname "$0")"

APP=MikuPet.app
BIN=$APP/Contents/MacOS/MikuPet
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library \
  main.swift PetView/PetView.swift \
  Core/ChatClient.swift Core/NASStatus.swift Core/Actions.swift \
  Core/TaskTimer.swift Core/ReminderParser.swift Core/SystemPrompt.swift \
  UI/PetPanel.swift \
  -o "$BIN" -framework AppKit -framework QuartzCore -framework UserNotifications

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 素材打进 bundle（运行时会优先用 bundle 内的，取不到才回落到工作区绝对路径）
mkdir -p "$APP/Contents/Resources/assets"
cp assets/*.png "$APP/Contents/Resources/assets/"

# ad-hoc 签名：不加的话 macOS 26 上可能被 Gatekeeper 拦
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(codesign 失败，继续)"

echo "built $APP"
ls -la "$BIN" | awk '{print "binary:", $5, "bytes"}'
