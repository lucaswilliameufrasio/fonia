ARCH := $(shell uname -m)
TARGET := $(ARCH)-apple-macos14.4
APP := build/Fonia.app
BIN := $(APP)/Contents/MacOS/Fonia
.PHONY: build
build: $(BIN)

$(BIN): Fonia.swift SourceIdentity.swift Voice.swift VoiceEffects.swift VoiceRoute.swift VirtualMicSetup.swift Audio.m Audio.h Info.plist Makefile
	mkdir -p "$(APP)/Contents/MacOS"
	xcrun clang -target $(TARGET) -fobjc-arc -Wall -Werror -c Audio.m -o build/Audio.o
	xcrun swiftc -target $(TARGET) -O -parse-as-library -import-objc-header Audio.h Fonia.swift SourceIdentity.swift Voice.swift VoiceEffects.swift VoiceRoute.swift VirtualMicSetup.swift build/Audio.o -framework CoreAudio -framework AudioToolbox -o "$(BIN)"
	cp Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

.PHONY: check check-offline
check: check-offline
	build/route-checks

check-offline: build
	plutil -lint Info.plist
	codesign --verify --strict "$(APP)"
	xcrun clang -target $(TARGET) -fobjc-arc -Wall -Werror AudioChecks.m -framework CoreAudio -framework Foundation -framework AudioToolbox -o build/audio-checks
	build/audio-checks
	xcrun swiftc -target $(TARGET) -parse-as-library VoiceEffects.swift VoiceChecks.swift -o build/voice-checks
	build/voice-checks
	xcrun swiftc -target $(TARGET) -parse-as-library -import-objc-header Audio.h SourceIdentity.swift IdentityChecks.swift build/Audio.o -framework CoreAudio -framework AudioToolbox -o build/identity-checks
	build/identity-checks
	xcrun swiftc -target $(TARGET) -parse-as-library -import-objc-header Audio.h VoiceRoute.swift VirtualMicSetup.swift VoiceEffects.swift RouteChecks.swift build/Audio.o -framework CoreAudio -framework AudioToolbox -o build/route-checks
	build/route-checks --offline

.PHONY: release
release:
	/bin/zsh release/notarize.zsh
