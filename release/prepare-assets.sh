#!/bin/bash
# Run from the project root. Write release notes and optional assets to an empty directory.
set -euo pipefail
tag=$1
out=$2
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.(0|[1-9][0-9]*))?$ ]]
version=$(plutil -extract CFBundleShortVersionString raw Info.plist)
[[ "${tag%%-*}" == "v$version" ]]
mkdir "$out"
awk -v heading="## $tag" '
  /^## / { if (found) exit; found=($0==heading); next }
  found { print; if (NF) content=1 }
  END { if (!content) exit 1 }
' CHANGELOG.md > "$out/notes.md"
if [[ "$tag" != *-* ]]; then
    exit 0
fi
make build
app=build/Fonia.app
codesign --verify --strict "$app"
signature=$(codesign -dv "$app" 2>&1)
grep -qx 'Signature=adhoc' <<<"$signature"
arch=$(lipo -archs "$app/Contents/MacOS/Fonia")
[[ "$arch" == arm64 || "$arch" == x86_64 ]]
minimum=$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")
zip="Fonia-$tag-macOS-$arch-adhoc.zip"
ditto --norsrc -c -k --keepParent "$app" "$out/$zip"
(cd "$out" && shasum -a 256 "$zip" > "$zip.sha256")
digest=$(cut -d' ' -f1 "$out/$zip.sha256")
cat >> "$out/notes.md" <<EOF

### Instalação no macOS

Baixe \`$zip\` nos assets desta release. Requer macOS $minimum ou superior e arquitetura \`$arch\`. Descompacte o ZIP e arraste **Fonia.app** para **Aplicativos**.

Esta é uma pré-release com assinatura ad hoc, sem Developer ID nem notarização da Apple. O Gatekeeper pode bloquear a primeira abertura.

SHA-256 do ZIP: \`$digest\`. Para conferir o download, coloque o ZIP e o arquivo de checksum na mesma pasta e execute \`shasum -a 256 -c $zip.sha256\`.
EOF
