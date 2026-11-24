#!/bin/zsh
set -eu
cd "${0:A:h}/.."
: "${SIGN_IDENTITY:?Defina SIGN_IDENTITY com o nome completo Developer ID Application}"
: "${NOTARY_PROFILE:?Defina NOTARY_PROFILE com o nome de um perfil notarytool do Chaveiro}"
[[ "$SIGN_IDENTITY" == "Developer ID Application: "* ]] || { print -u2 'Identidade de distribuição esperada.'; exit 1; }
/usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\"" || { print -u2 'Identidade de distribuição não disponível no Chaveiro.'; exit 1; }
make check
stage=$(mktemp -d "$PWD/build/release.XXXXXXXX")
app="$stage/Fonia.app"
ditto build/Fonia.app "$app"
codesign --force --timestamp --options runtime --entitlements release/audio.entitlements --sign "$SIGN_IDENTITY" "$app"
codesign --verify --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$stage/submission.zip"
xcrun notarytool submit "$stage/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist > "$stage/notary.plist"
[[ "$(plutil -extract status raw "$stage/notary.plist")" == Accepted ]] || { print -u2 "Notarização não aceita: $stage/notary.plist"; exit 1; }
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute -vv "$app"
ditto -c -k --keepParent "$app" "$stage/Fonia-macOS.zip"
shasum -a 256 "$stage/Fonia-macOS.zip"
