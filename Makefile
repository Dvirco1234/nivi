WHISPER_TAG ?= v1.7.2  # bump freely; anything >= v1.7.0 supports large-v3-turbo
VENDOR := vendor/whisper.cpp

# Stable self-signed identity keeps TCC grants (Accessibility, Input Monitoring,
# Microphone) across rebuilds. macOS keys those grants to the signing identity, so
# ad-hoc signing ("-") mints a new identity every build and silently revokes them —
# auto-paste degrades to clipboard-only and Esc-to-cancel stops working. That failure
# is invisible at build time, so a missing cert is a hard error rather than a silent
# fallback. Run `make cert` once to create it, or ALLOW_ADHOC=1 to opt in knowingly.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -o 'Dictato Self-Signed' | head -1)
ifeq ($(SIGN_ID),)
ifeq ($(ALLOW_ADHOC),1)
SIGN_ID := -
else
$(error No "Dictato Self-Signed" identity found. Run `make cert` first — ad-hoc signing revokes Accessibility/Input Monitoring on every rebuild. Override with ALLOW_ADHOC=1 if you accept re-granting permissions.)
endif
endif

.PHONY: vendor build release test app dev run clean icon dmg cert install perms

vendor:
	@if [ ! -d $(VENDOR) ]; then \
		git clone --depth 1 --branch $(WHISPER_TAG) https://github.com/ggml-org/whisper.cpp $(VENDOR); \
	fi
	cmake -S $(VENDOR) -B $(VENDOR)/build \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=OFF \
		-DGGML_METAL=ON \
		-DGGML_METAL_EMBED_LIBRARY=ON \
		-DWHISPER_BUILD_TESTS=OFF \
		-DWHISPER_BUILD_EXAMPLES=OFF \
		-DWHISPER_BUILD_SERVER=OFF
	cmake --build $(VENDOR)/build -j
	mkdir -p vendor/lib Sources/CWhisper/include
	find $(VENDOR)/build -name '*.a' -exec cp {} vendor/lib/ \;
	cp $(VENDOR)/include/whisper.h Sources/CWhisper/include/
	cp $(VENDOR)/ggml/include/*.h Sources/CWhisper/include/

build:
	swift build

release:
	swift build -c release

test:
	swift test

APP := build/Dictato.app

# Assembles $(APP) around whichever binary is passed in as BIN, then signs it.
# `swift build` alone only refreshes .build/<config>/Dictato — the bundle keeps the
# binary it was assembled with, so launching build/Dictato.app after a bare
# `swift build` silently runs stale code. Always go through a target that re-copies.
define assemble_app
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(1) $(APP)/Contents/MacOS/Dictato
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/Dictato.icns $(APP)/Contents/Resources/Dictato.icns
	cp Resources/DictatoLogo.png $(APP)/Contents/Resources/DictatoLogo.png
	cp Resources/DictatoLogoEn.png $(APP)/Contents/Resources/DictatoLogoEn.png
	cp Resources/MenuBarAleph.png $(APP)/Contents/Resources/MenuBarAleph.png
	cp Resources/MenuBarLatinA.png $(APP)/Contents/Resources/MenuBarLatinA.png
	codesign --force --sign "$(SIGN_ID)" $(APP)
	@echo "Built $(APP) from $(1) (signed: $(SIGN_ID))"
endef

app: release
	$(call assemble_app,.build/release/Dictato)

# Fast iteration loop: debug build, bundle refreshed, signed with the stable identity,
# installed to /Applications, relaunched. Installing matters because Dock/Spotlight
# open /Applications/Dictato.app — quitting a build/ preview and reopening from the
# Dock otherwise launches the previous version and looks like "my change did nothing".
dev: build
	$(call assemble_app,.build/debug/Dictato)
	@osascript -e 'quit app "Dictato"' 2>/dev/null || true
	@sleep 1
	rm -rf /Applications/Dictato.app
	cp -R $(APP) /Applications/Dictato.app
	@open -a Dictato
	@echo "Installed + relaunched /Applications/Dictato.app (debug)"

# Prints the TCC grants Dictato depends on. Accessibility covers auto-paste and the
# global modifier-tap monitors; Input Monitoring is a separate grant that global
# keyDown (Esc-to-cancel) needs. A wrong signing identity shows up here first.
perms:
	@echo "Signing identity of /Applications/Dictato.app:"
	@codesign -dvvv /Applications/Dictato.app 2>&1 | grep -E "Authority|Identifier" || echo "  (not installed)"
	@echo "Grants are per-identity; check System Settings > Privacy & Security for:"
	@echo "  Accessibility     -> auto-paste + modifier-tap hotkeys"
	@echo "  Input Monitoring  -> Esc-to-cancel (global keyDown)"
	@echo "  Microphone        -> recording"
	@echo "Startup state is logged; see: grep 'Permissions —' ~/Library/Logs/Dictato/dictato.log | tail -1"

cert:
	bash Tools/make-signing-cert.sh

icon:
	bash Tools/make-iconset.sh

dmg: app
	rm -rf build/dmg build/Dictato.dmg
	mkdir -p build/dmg
	cp -R $(APP) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname Dictato -srcfolder build/dmg -ov -format UDZO build/Dictato.dmg
	rm -rf build/dmg
	@echo "Built build/Dictato.dmg"

install: app
	rm -rf /Applications/Dictato.app
	cp -R $(APP) /Applications/Dictato.app
	@echo "Installed /Applications/Dictato.app"

run: app
	open $(APP)

clean:
	rm -rf .build build
