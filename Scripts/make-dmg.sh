#!/bin/zsh
# Packages dist/SourceSort.app into dist/SourceSort.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d dist/SourceSort.app ]] || Scripts/build-app.sh

STAGE=$(mktemp -d)
trap 'rm -rf $STAGE' EXIT
cp -R dist/SourceSort.app $STAGE/
ln -s /Applications $STAGE/Applications

rm -f dist/SourceSort.dmg
hdiutil create -volname SourceSort -srcfolder $STAGE -fs HFS+ -format UDZO -ov dist/SourceSort.dmg
hdiutil verify dist/SourceSort.dmg
echo "Built dist/SourceSort.dmg"
