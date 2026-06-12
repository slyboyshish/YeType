#!/bin/bash
# Выпуск новой версии YeType: собирает DMG, подписывает ключом Sparkle,
# обновляет appcast.xml (ленту обновлений) и публикует релиз на GitHub.
# После этого у всех, у кого стоит YeType, всплывёт «доступно обновление».
#
# Использование:  ./release.sh <версия>     напр.  ./release.sh 1.1
set -e

# Версия: если не передали аргумент — авто-инкремент последней цифры текущей
# (1.0 -> 1.1 -> 1.2 ...), чтобы можно было просто запускать ./release.sh без номера.
if [ -z "$1" ]; then
  CUR=$(plutil -extract CFBundleShortVersionString raw YeTypeInfo.plist)
  VERSION="${CUR%.*}.$(( ${CUR##*.} + 1 ))"
else
  VERSION="$1"
fi
REPO="slyboyshish/YeType"
CERT="Apple Development: viber33e.88@gmail.com (W9PHGU8Q2H)"
BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/YeType-release-build"
APP="$BUILD_DIR/Build/Products/Release/YeType.app"
STAGE="/tmp/yetype-dmg-stage"
DMG_NAME="YeType-$VERSION.dmg"
DMG="$HOME/Desktop/$DMG_NAME"

# Номер сборки для Sparkle (CFBundleVersion) — целое, монотонно растущее.
# Берём версию без точек: 1.0 -> 10, 1.1 -> 11, 2.0 -> 20.
BUILD_NUMBER=$(echo "$VERSION" | tr -d '.')

echo "▶ Версия $VERSION (build $BUILD_NUMBER)"
plutil -replace CFBundleShortVersionString -string "$VERSION" YeTypeInfo.plist
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" YeTypeInfo.plist

echo "▶ Сборка Release..."
xcodegen generate >/dev/null 2>&1 || true
xcodebuild -project YeType.xcodeproj -scheme "YeType" -configuration Release \
  -derivedDataPath "$BUILD_DIR" build CODE_SIGNING_ALLOWED=NO >/dev/null

echo "▶ Подпись приложения..."
codesign --force --deep --sign "$CERT" --options runtime "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"

echo "▶ Сборка DMG..."
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/ЧИТАТЬ — как открыть.txt" << 'TXT'
1. Перетащи YeType в папку Applications (рядом).
2. Открой Терминал, вставь и нажми Enter (уберёт блокировку macOS):
     xattr -dr com.apple.quarantine /Applications/YeType.app
3. Запусти YeType. Дай доступ: Настройки → Конфиденциальность → Универсальный доступ → включи YeType.
4. При первом запуске приложение само скачает языковую модель (~2-3 ГБ, нужен интернет).

Дальше обновления будут приходить сами — внутри приложения «Проверить обновления».
TXT
hdiutil create -volname "YeType" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "▶ Подпись DMG ключом Sparkle..."
SIGNATURE=$("$BIN/sign_update" "$DMG")   # -> sparkle:edSignature="..." length="..."

echo "▶ Генерация appcast.xml..."
URL="https://github.com/$REPO/releases/download/v$VERSION/$DMG_NAME"
cat > appcast.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>YeType</title>
    <item>
      <title>$VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <pubDate>$(date -R)</pubDate>
      <enclosure url="$URL" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF

echo "▶ Публикация релиза на GitHub..."
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "v$VERSION" "$DMG" --repo "$REPO" --clobber
else
  gh release create "v$VERSION" "$DMG" --repo "$REPO" \
    --title "YeType $VERSION" --notes "YeType $VERSION"
fi

echo "▶ Пуш ленты обновлений..."
git add appcast.xml YeTypeInfo.plist
git commit -q -m "Release $VERSION" || echo "(нет изменений для коммита)"
git push origin main

echo ""
echo "✓ Готово. Версия $VERSION опубликована."
echo "  DMG:    $DMG"
echo "  Релиз:  https://github.com/$REPO/releases/tag/v$VERSION"
echo "  У друзей в приложении всплывёт обновление (или «Проверить обновления»)."
