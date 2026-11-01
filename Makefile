VERSION := $(shell cat VERSION)
BUNDLE_ID := ch.oetiker.OpenWell
# Signs with the first Developer ID Application certificate in the keychain, else ad hoc
# ("-"). An ad hoc signature changes with every build, and macOS then refuses the
# Accessibility permission granted to the previous build; a certificate keeps it across
# builds. A release is notarized with the credentials stored by:
# xcrun notarytool store-credentials OpenWell
SIGN_IDENTITY ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | \
	sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1),-)
NOTARY_PROFILE ?= OpenWell
UNIVERSAL := --arch arm64 --arch x86_64
SIGN_FLAGS := --force --options runtime $(if $(filter -,$(SIGN_IDENTITY)),--timestamp=none,--timestamp)
override SWIFTFLAGS += -c release
SOURCES := Package.swift $(shell find Sources -type f)
APP := build/OpenWell.app
ZIP := build/OpenWell-$(VERSION).zip

.PHONY: all app install test zip notarize cask icon clean

all: app

app: $(APP)

$(APP): $(SOURCES) App/Info.plist OpenWell.icns VERSION
	swift build $(SWIFTFLAGS) $(UNIVERSAL) --product OpenWell
	rm -rf $@ && mkdir -p $@/Contents/MacOS $@/Contents/Resources
	cp "$$(swift build $(SWIFTFLAGS) $(UNIVERSAL) --show-bin-path)/OpenWell" $@/Contents/MacOS/OpenWell
	sed -e 's/@VERSION@/$(VERSION)/g' App/Info.plist > $@/Contents/Info.plist
	cp OpenWell.icns $@/Contents/Resources/
	codesign $(SIGN_FLAGS) --sign "$(SIGN_IDENTITY)" $@

# An ad hoc signature changes with every build. macOS then keeps the Accessibility
# entry of the old build, which shows as allowed while the new one gets no access, and
# removing it by hand while the app runs drops OpenWell from the list for good. The
# reset makes the first start ask again and add the new build to the list.
install: $(APP)
	osascript -e 'quit app id "$(BUNDLE_ID)"' || true
	$(if $(filter -,$(SIGN_IDENTITY)),tccutil reset Accessibility $(BUNDLE_ID))
	rm -rf /Applications/OpenWell.app
	ditto $(APP) /Applications/OpenWell.app
	open /Applications/OpenWell.app

test:
	swift test $(filter-out -c release,$(SWIFTFLAGS))

zip: $(ZIP)

$(ZIP): $(APP)
	rm -f $@
	ditto -c -k --keepParent $(APP) $@

notarize: $(ZIP)
	xcrun notarytool submit $(ZIP) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP)
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)

# Points the cask at the zip for VERSION, run after notarize
cask: $(ZIP)
	sed -i '' -e 's/^  version ".*"/  version "$(VERSION)"/' \
		-e "s/^  sha256 \".*\"/  sha256 \"$$(shasum -a 256 $(ZIP) | cut -d' ' -f1)\"/" Casks/openwell.rb

icon:
	swift scripts/make-icon.swift

clean:
	rm -rf .build build
