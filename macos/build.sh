#!/usr/bin/env bash
# Сборка VPNBypass.app: приложение + встроенный helper-демон, подпись.
#
#   ./build.sh                          # подпись ad-hoc (-), helper может не зарегистрироваться
#   SIGN_ID="Apple Development: Имя (TEAMID)" ./build.sh
#
# Нужен Xcode (swift build + codesign). Результат: build/VPNBypass.app
set -euo pipefail

cd "$(dirname "$0")"
SIGN_ID="${SIGN_ID:--}"
APP="build/VPNBypass.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons" "$APP/Contents/Resources"
cp "$BIN/VPNBypass" "$APP/Contents/MacOS/VPNBypass"
cp "$BIN/VPNBypassHelper" "$APP/Contents/MacOS/VPNBypassHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" # пересоздать: swift Resources/make-icon.swift Resources/AppIcon.icns
cp Resources/com.vpnbypass.helper.plist "$APP/Contents/Library/LaunchDaemons/"

# Идентификаторы подписи должны совпадать с требованиями XPC (Constants.swift).
codesign --force --options runtime --sign "$SIGN_ID" \
  --identifier com.vpnbypass.helper "$APP/Contents/MacOS/VPNBypassHelper"
codesign --force --options runtime --sign "$SIGN_ID" \
  --identifier com.vpnbypass.app "$APP"

echo "Готово: $APP"
echo "Скопируйте в /Applications, запустите и нажмите «Установить helper»."
