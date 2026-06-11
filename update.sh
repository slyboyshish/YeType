#!/bin/bash
# YeType: собрать, переподписать стабильным сертификатом, обновить in-place.
# Стабильная подпись = разрешения (Accessibility/Input/Screen) НЕ слетают между сборками.
set -e
cd "$(dirname "$0")"
CERT="Apple Development: viber33e.88@gmail.com (W9PHGU8Q2H)"
APP=build/Build/Products/Debug/YeType.app
DEST=/Applications/YeType.app

echo "▶ Сборка..."
xcodebuild -project YeType.xcodeproj -scheme "YeType" -configuration Debug -derivedDataPath ./build -jobs 4 \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build > /tmp/yetype_update.log 2>&1
grep -q "BUILD SUCCEEDED" /tmp/yetype_update.log || { echo "✗ сборка упала"; tail -20 /tmp/yetype_update.log; exit 1; }

echo "▶ Переподпись стабильным сертификатом..."
find "$APP/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null | while read i; do
  codesign --force --sign "$CERT" --timestamp=none "$i" 2>/dev/null
done
codesign --force --deep --sign "$CERT" --options runtime --timestamp=none "$APP" >/dev/null 2>&1

echo "▶ Обновление приложения (in-place, разрешения сохраняются)..."
osascript -e 'quit app "YeType"' 2>/dev/null; sleep 1; pkill -9 -f YeType 2>/dev/null || true; sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "✓ Готово — YeType обновлён и запущен."
