#!/bin/bash
# Собирает YeType в DMG для раздачи друзьям.
# Использование: ./release.sh
set -e

CERT="Apple Development: viber33e.88@gmail.com (W9PHGU8Q2H)"
BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/YeType-release-build"
APP="$BUILD_DIR/Build/Products/Release/YeType.app"
STAGE="/tmp/yetype-dmg-stage"
OUT="$HOME/Desktop/YeType.dmg"

echo "▶ Сборка Release..."
xcodegen generate >/dev/null 2>&1 || true
xcodebuild -project YeType.xcodeproj -scheme "YeType" -configuration Release \
  -derivedDataPath "$BUILD_DIR" build CODE_SIGNING_ALLOWED=NO >/dev/null

echo "▶ Подпись..."
codesign --force --deep --sign "$CERT" --options runtime "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"   # запасной ad-hoc, если серта нет

echo "▶ Сборка DMG..."
rm -rf "$STAGE" "$OUT"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"      # перетащи в Applications
# короткая инструкция внутрь образа
cat > "$STAGE/ЧИТАТЬ — как открыть.txt" << 'TXT'
1. Перетащи YeType в папку Applications (рядом).
2. Открой Терминал, вставь и нажми Enter (уберёт блокировку macOS):
     xattr -dr com.apple.quarantine /Applications/YeType.app
3. Запусти YeType. Дай доступ: Настройки → Конфиденциальность → Универсальный доступ → включи YeType.
4. При первом запуске приложение само скачает языковую модель (~2-3 ГБ, нужен интернет).
TXT
hdiutil create -volname "YeType" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"
echo "✓ Готово: $OUT  ($(du -sh "$OUT" | cut -f1))"
