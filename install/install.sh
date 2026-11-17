#!/bin/bash
# install.sh — 把桌宠装成 launchd 托管的常驻程序。
#
# 为什么需要它：桌宠原来是「谁开谁负责」的普通进程，从终端/脚本里启动的话，
# 那个会话一结束（合盖睡眠、终端关闭、脚本退出）进程就没了，再也没人把它拉起来 ——
# 表现就是「合盖再打开后她不见了」。launchd 托管 + KeepAlive 之后，
# 崩溃、被 kill 都会自动回来。
#
# 用法: bash install/install.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
HOME_DIR="$HOME"
APP_SRC="$REPO/MikuPet.app"
APP_DST="$HOME_DIR/Library/Application Support/MikuPet/MikuPet.app"
LABEL="com.saltcheng.mikupet"

if [ ! -d "$APP_SRC" ]; then
  echo "先跑 bash build.sh 生成 MikuPet.app"
  exit 1
fi

# 换 bundle 前先停掉守护，免得运行中的进程读到半个文件
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

rm -rf "$APP_DST"
mkdir -p "$(dirname "$APP_DST")"
cp -R "$APP_SRC" "$APP_DST"

PLIST_SRC="$HERE/com.saltcheng.mikupet.plist"
PLIST_DST="$HOME_DIR/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME_DIR/Library/LaunchAgents"
sed "s#__HOME__#$HOME_DIR#g" "$PLIST_SRC" > "$PLIST_DST"
chmod 644 "$PLIST_DST"

launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
echo "已安装并启动: $APP_DST"
echo "日志: ~/Library/Logs/MikuPet.out.log"
