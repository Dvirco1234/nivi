WHISPER_TAG ?= v1.7.2  # bump freely; anything >= v1.7.0 supports large-v3-turbo
VENDOR := vendor/whisper.cpp

.PHONY: vendor build release test app run clean

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
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Dictato $(APP)/Contents/MacOS/Dictato
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)
	@echo "Built $(APP)"

run: app
	open $(APP)

clean:
	rm -rf .build build
