SCHEME := Calenminder
SIMULATOR_NAME := iPhone 17 Pro

.PHONY: generate build test clean

generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project Calenminder.xcodeproj \
		-scheme $(SCHEME) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)" \
		| xcbeautify || xcodebuild build \
		-project Calenminder.xcodeproj \
		-scheme $(SCHEME) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)"

test: generate
	xcodebuild test \
		-project Calenminder.xcodeproj \
		-scheme $(SCHEME) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)"

clean:
	rm -rf DerivedData
