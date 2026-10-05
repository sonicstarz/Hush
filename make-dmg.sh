#!/bin/zsh
# Builds Hush.app and packages it into build/Hush.dmg (drag-to-Applications layout).
set -e
cd "$(dirname "$0")"
./build.sh
STAGE=build/dmg
rm -rf $STAGE build/Hush.dmg && mkdir -p $STAGE
cp -R build/Hush.app $STAGE/
ln -s /Applications $STAGE/Applications
hdiutil create -volname Hush -srcfolder $STAGE -ov -format UDZO build/Hush.dmg
rm -rf $STAGE
echo "Created build/Hush.dmg"
