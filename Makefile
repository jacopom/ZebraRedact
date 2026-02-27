XCODE   := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SCHEME  := ZebraRedact
ARCHIVE := build/ZebraRedact.xcarchive
EXPORT  := build/export
DMG     := build/ZebraRedact.dmg

.PHONY: build archive export dmg clean

## Run a debug build (quick sanity check)
build:
	$(XCODE) xcodebuild -scheme $(SCHEME) -configuration Debug build

## Create a Release archive
archive:
	mkdir -p build
	$(XCODE) xcodebuild \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  archive \
	  -archivePath $(ARCHIVE)

## Copy the .app directly from the xcarchive (avoids exportArchive signing requirements)
export: archive
	mkdir -p $(EXPORT)
	cp -R $(ARCHIVE)/Products/Applications/ZebraRedact.app $(EXPORT)/

## Package the .app into a drag-to-install DMG
## Requires: brew install create-dmg
dmg: export
	create-dmg \
	  --volname "ZebraRedact" \
	  --volicon "Assets/icon_1024.png" \
	  --window-pos 200 120 \
	  --window-size 660 400 \
	  --icon-size 128 \
	  --icon "ZebraRedact.app" 160 185 \
	  --hide-extension "ZebraRedact.app" \
	  --app-drop-link 500 185 \
	  "$(DMG)" "$(EXPORT)"
	@echo "DMG ready: $(DMG)"

## Remove all build artefacts
clean:
	rm -rf build/
