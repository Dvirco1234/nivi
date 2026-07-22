WHISPER_TAG ?= v1.7.2  # bump freely; anything >= v1.7.0 supports large-v3-turbo
VENDOR := vendor/whisper.cpp

# Stable self-signed identity keeps TCC (Accessibility/Mic) grants across rebuilds.
# Falls back to ad-hoc "-" if the cert is absent (run `make cert` to create it).
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -o 'Dictato Self-Signed' | head -1)
ifeq ($(SIGN_ID),)
SIGN_ID := -
endif

.PHONY: vendor build release test app run clean icon dmg cert install

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

app: release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Dictato $(APP)/Contents/MacOS/Dictato
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/Dictato.icns $(APP)/Contents/Resources/Dictato.icns
	cp Resources/DictatoLogo.png $(APP)/Contents/Resources/DictatoLogo.png
	cp Resources/DictatoLogoEn.png $(APP)/Contents/Resources/DictatoLogoEn.png
	cp Resources/MenuBarAleph.png $(APP)/Contents/Resources/MenuBarAleph.png
	cp Resources/MenuBarLatinA.png $(APP)/Contents/Resources/MenuBarLatinA.png
	codesign --force --sign "$(SIGN_ID)" $(APP)
	@echo "Built $(APP) (signed: $(SIGN_ID))"

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
