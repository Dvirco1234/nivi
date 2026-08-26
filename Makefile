# ---------------------------------------------------------------------------
# Identity: the one place the app's name and bundle id live.
#
# APP_NAME drives the bundle name, the executable name, the icon name inside the
# bundle, the DMG file name, the volume name, the signing identity and the
# appcast. BUNDLE_ID drives CFBundleIdentifier, which is what macOS and Sparkle
# use to tell one app from another.
#
# Renaming the app later means editing these two lines, running `make cert` to
# mint a matching signing identity, and renaming a handful of resource files.
# See docs/release-pipeline.md for the full checklist.
# ---------------------------------------------------------------------------
APP_NAME  := Dictato
BUNDLE_ID := com.dvir.dictato

# The version and the build counter. See version.mk.
include version.mk

# ---------------------------------------------------------------------------
# Where updates are published.
#
# The source repo is private. Sparkle fetches the appcast and the DMG over plain
# HTTPS with no login, so a private repo cannot serve them. A separate PUBLIC
# repo holds only the appcast (served by GitHub Pages) and the DMG files (served
# as GitHub Release assets). The source stays private.
# ---------------------------------------------------------------------------
RELEASES_OWNER := Dvirco1234
RELEASES_REPO  := dictato-releases
RELEASES_SLUG  := $(RELEASES_OWNER)/$(RELEASES_REPO)
PAGES_URL      := https://$(shell echo $(RELEASES_OWNER) | tr 'A-Z' 'a-z').github.io/$(RELEASES_REPO)
APPCAST_URL    := $(PAGES_URL)/appcast.xml

# Public half of the EdDSA key pair Sparkle uses to check that an update really
# came from us. Safe to commit. The private half lives in the login keychain and
# must never be committed — see docs/release-pipeline.md.
SPARKLE_PUBLIC_KEY := nlugNRszrCHntDKWTBdlmIfGYuq7TbiE/c2tNG9D40Q=

SPARKLE_BIN := .build/artifacts/sparkle/Sparkle/bin

WHISPER_TAG ?= v1.7.2  # bump freely; anything >= v1.7.0 supports large-v3-turbo
VENDOR := vendor/whisper.cpp

# Stable self-signed identity keeps TCC grants (Accessibility, Input Monitoring,
# Microphone) across rebuilds. macOS keys those grants to the signing identity, so
# ad-hoc signing ("-") mints a new identity every build and silently revokes them —
# auto-paste degrades to clipboard-only and Esc-to-cancel stops working. That failure
# is invisible at build time, so a missing cert is a hard error rather than a silent
# fallback. Run `make cert` once to create it, or ALLOW_ADHOC=1 to opt in knowingly.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -o '$(APP_NAME) Self-Signed' | head -1)
ifeq ($(SIGN_ID),)
ifeq ($(ALLOW_ADHOC),1)
SIGN_ID := -
else
$(error No "$(APP_NAME) Self-Signed" identity found. Run `make cert` first — ad-hoc signing revokes Accessibility/Input Monitoring on every rebuild. Override with ALLOW_ADHOC=1 if you accept re-granting permissions.)
endif
endif

.PHONY: vendor build release-build test app dev run clean icon dmg cert install perms \
        dist appcast notarize release publish version check-clean

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
	swift build -c debug

release-build:
	swift build -c release

test:
	swift test

APP  := build/$(APP_NAME).app
DIST := dist

# Assembles $(APP) around whichever binary is passed in as BIN, then signs it.
# `swift build` alone only refreshes .build/<config>/$(APP_NAME) — the bundle keeps
# the binary it was assembled with, so launching build/$(APP_NAME).app after a bare
# `swift build` silently runs stale code. Always go through a target that re-copies.
#
# $(dir $(1)) is the build configuration directory, which is also where SwiftPM
# leaves Sparkle.framework, so debug and release each pick up their own copy.
define assemble_app
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(APP)/Contents/Frameworks
	cp $(1) $(APP)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/Dictato.icns $(APP)/Contents/Resources/$(APP_NAME).icns
	cp Resources/*.png $(APP)/Contents/Resources/
	cp -R $(dir $(1))Sparkle.framework $(APP)/Contents/Frameworks/
	$(call stamp_plist,$(APP)/Contents/Info.plist)
	$(call sign_bundle,$(APP))
	@echo "Built $(APP)  v$(VERSION) ($(BUILD_NUMBER))  signed: $(SIGN_ID)"
endef

# Writes the identity, the version and the update settings into the bundle's
# Info.plist. Resources/Info.plist holds placeholders only; this is what makes the
# sidebar footer, the DMG name, the git tag and the appcast agree without anyone
# editing a version in two places.
define stamp_plist
	plutil -replace CFBundleExecutable         -string  "$(APP_NAME)"           $(1)
	plutil -replace CFBundleName               -string  "$(APP_NAME)"           $(1)
	plutil -replace CFBundleIdentifier         -string  "$(BUNDLE_ID)"          $(1)
	plutil -replace CFBundleIconFile           -string  "$(APP_NAME)"           $(1)
	plutil -replace CFBundleShortVersionString -string  "$(VERSION)"            $(1)
	plutil -replace CFBundleVersion            -string  "$(BUILD_NUMBER)"       $(1)
	plutil -replace SUFeedURL                  -string  "$(APPCAST_URL)"        $(1)
	plutil -replace SUPublicEDKey              -string  "$(SPARKLE_PUBLIC_KEY)" $(1)
endef

# Sparkle puts helper programs inside its framework, and macOS checks nested code
# from the inside out. Sign the innermost pieces first; signing the app last would
# otherwise be invalidated by touching anything below it.
# --preserve-metadata=entitlements keeps the sandbox entitlements Sparkle ships on
# its XPC services; re-signing without that flag strips them.
define sign_bundle
	@F=$(1)/Contents/Frameworks/Sparkle.framework/Versions/B; \
	for x in $$F/XPCServices/*.xpc; do \
		codesign --force --sign "$(SIGN_ID)" --preserve-metadata=entitlements "$$x"; \
	done; \
	codesign --force --sign "$(SIGN_ID)" "$$F/Autoupdate"; \
	codesign --force --sign "$(SIGN_ID)" "$$F/Updater.app"; \
	codesign --force --sign "$(SIGN_ID)" $(1)/Contents/Frameworks/Sparkle.framework
	codesign --force --sign "$(SIGN_ID)" $(1)
endef

app: release-build
	$(call assemble_app,.build/release/$(APP_NAME))

# Fast iteration loop: debug build, bundle refreshed, signed with the stable identity,
# installed to /Applications, relaunched. Installing matters because Dock/Spotlight
# open /Applications/$(APP_NAME).app — quitting a build/ preview and reopening from the
# Dock otherwise launches the previous version and looks like "my change did nothing".
dev: build
	$(call assemble_app,.build/debug/$(APP_NAME))
	@osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null || true
	@sleep 1
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/$(APP_NAME).app
	@open -a $(APP_NAME)
	@echo "Installed + relaunched /Applications/$(APP_NAME).app (debug)"

# Prints the TCC grants $(APP_NAME) depends on. Accessibility covers auto-paste and the
# global modifier-tap monitors; Input Monitoring is a separate grant that global
# keyDown (Esc-to-cancel) needs. A wrong signing identity shows up here first.
perms:
	@echo "Signing identity of /Applications/$(APP_NAME).app:"
	@codesign -dvvv /Applications/$(APP_NAME).app 2>&1 | grep -E "Authority|Identifier" || echo "  (not installed)"
	@echo "Grants are per-identity; check System Settings > Privacy & Security for:"
	@echo "  Accessibility     -> auto-paste + modifier-tap hotkeys"
	@echo "  Input Monitoring  -> Esc-to-cancel (global keyDown)"
	@echo "  Microphone        -> recording"
	@echo "Startup state is logged; see: grep 'Permissions —' ~/Library/Logs/$(APP_NAME)/dictato.log | tail -1"

cert:
	bash Tools/make-signing-cert.sh

icon:
	bash Tools/make-iconset.sh

version:
	@echo "$(APP_NAME) $(VERSION) (build $(BUILD_NUMBER))  id=$(BUNDLE_ID)"
	@echo "appcast: $(APPCAST_URL)"

install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/$(APP_NAME).app
	@echo "Installed /Applications/$(APP_NAME).app"

run: app
	open $(APP)

# ---------------------------------------------------------------------------
# Release
# ---------------------------------------------------------------------------

DMG := $(DIST)/$(APP_NAME)-$(VERSION).dmg

# The one file a stranger downloads: the app plus a shortcut to /Applications to
# drag it onto.
dmg: app
	@APP_NAME="$(APP_NAME)" VERSION="$(VERSION)" APP_BUNDLE="$(APP)" \
	 OUT="$(DMG)" SIGN_ID="$(SIGN_ID)" bash Tools/make-dmg.sh

# Notarizing is Apple checking the app and telling every Mac it is safe to open.
# It needs an Apple Developer account. Without credentials this prints why it was
# skipped and carries on, so a self-signed release still works.
notarize:
	@APP_BUNDLE="$(APP)" DMG="$(DMG)" SIGN_ID="$(SIGN_ID)" bash Tools/notarize.sh

# Adds this version to the update feed Sparkle reads, with its size and its
# EdDSA signature.
appcast:
	@APP_NAME="$(APP_NAME)" VERSION="$(VERSION)" DMG="$(DMG)" \
	 APPCAST_DIR="$(DIST)/appcast" APPCAST_URL="$(APPCAST_URL)" \
	 DOWNLOAD_PREFIX="https://github.com/$(RELEASES_SLUG)/releases/download/v$(VERSION)/" \
	 SPARKLE_BIN="$(SPARKLE_BIN)" bash Tools/make-appcast.sh

# Everything a release needs, built locally. No git, no network, nothing published.
# Run this to check a release before committing to it.
dist: dmg notarize appcast
	@echo ""
	@echo "Ready: $(DMG)"
	@echo "Feed:  $(DIST)/appcast/appcast.xml"

# Uploads the DMG to the public releases repo and pushes the updated feed.
publish:
	@APP_NAME="$(APP_NAME)" VERSION="$(VERSION)" DMG="$(DMG)" \
	 RELEASES_SLUG="$(RELEASES_SLUG)" APPCAST_DIR="$(DIST)/appcast" \
	 PAGES_URL="$(PAGES_URL)" bash Tools/publish-release.sh

check-clean:
	@git diff --quiet && git diff --cached --quiet || \
		{ echo "Working tree is not clean. Commit or stash first."; exit 1; }

# The one command. `make release VERSION=0.2.0`
#
# Writes the new version down, builds and signs the app, packs the DMG, notarizes
# it if credentials are present, updates the update feed, commits, tags, and
# publishes to the public releases repo.
NEXT_BUILD := $(shell expr $(BUILD_NUMBER) + 1)
release: check-clean
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || \
		{ echo "VERSION must look like 1.2.3, got '$(VERSION)'"; exit 1; }
	@git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null && \
		{ echo "Tag v$(VERSION) already exists. Pick a new version."; exit 1; } || true
	@printf '%s\n' \
		'# The one place the version lives.' \
		'#' \
		'# VERSION is what people see: "0.1.0". CFBundleShortVersionString, the DMG file' \
		'# name, the git tag and the appcast entry all come from here.' \
		'#' \
		'# BUILD_NUMBER is a plain counter that only ever goes up. Sparkle compares builds' \
		'# with it, so it must never repeat and never go backwards, even if VERSION does.' \
		'# `make release` bumps it by one on every release. Do not edit it by hand.' \
		'#' \
		'# `make release VERSION=0.2.0` rewrites this file. You can also edit VERSION here' \
		'# and run `make release` with no argument.' \
		'VERSION := $(VERSION)' \
		'BUILD_NUMBER := $(NEXT_BUILD)' > version.mk
	@$(MAKE) --no-print-directory dist VERSION=$(VERSION) BUILD_NUMBER=$(NEXT_BUILD)
	git add version.mk
	git commit -m "release: v$(VERSION) (build $(NEXT_BUILD))"
	git tag -a "v$(VERSION)" -m "$(APP_NAME) $(VERSION)"
	@$(MAKE) --no-print-directory publish VERSION=$(VERSION)
	git push origin HEAD "v$(VERSION)"
	@echo ""
	@echo "Released $(APP_NAME) $(VERSION). Download page: $(PAGES_URL)"

clean:
	rm -rf .build build
