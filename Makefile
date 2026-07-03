SCHEME := Calenminder
SIMULATOR_NAME := iPhone 17 Pro

# EventKit integration suites hit the simulator's real system Calendars/
# Reminders store (DW-3.2, DW-3.3). Per docs/code-standards.md Testing
# Patterns they stay out of the default `make test` run and are run
# separately, serially, via `make test-integration`.
INTEGRATION_SUITES := CalenminderTests/EventKitEventStoreIntegrationTests CalenminderTests/ReminderTaskStoreIntegrationTests CalenminderTests/AgendaServiceIntegrationTests
SKIP_INTEGRATION := $(foreach s,$(INTEGRATION_SUITES),-skip-testing:$(s))
ONLY_INTEGRATION := $(foreach s,$(INTEGRATION_SUITES),-only-testing:$(s))

.PHONY: generate build test test-integration test-all clean

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
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)" \
		$(SKIP_INTEGRATION)

# Simulator-only, real-system-store tests. Grant access first, e.g.:
#   xcrun simctl privacy <udid> grant calendar com.enzonaut.calenminder.tests
#   xcrun simctl privacy <udid> grant reminders com.enzonaut.calenminder.tests
test-integration: generate
	xcodebuild test \
		-project Calenminder.xcodeproj \
		-scheme $(SCHEME) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)" \
		$(ONLY_INTEGRATION)

test-all: generate
	xcodebuild test \
		-project Calenminder.xcodeproj \
		-scheme $(SCHEME) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)"

clean:
	rm -rf DerivedData
