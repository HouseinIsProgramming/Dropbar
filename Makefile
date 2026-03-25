APP = Dropbar.app
BUNDLE = .build/$(APP)
INSTALL_DIR = /Applications

run:
	@pkill -x Dropbar 2>/dev/null || true
	@swift run

kill:
	@pkill -x Dropbar 2>/dev/null; echo "killed"

build:
	@swift build

test:
	@swift test

app: release
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@cp .build/release/Dropbar $(BUNDLE)/Contents/MacOS/Dropbar
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
	@echo "Built $(BUNDLE)"

install: app
	@rm -rf $(INSTALL_DIR)/$(APP)
	@cp -R $(BUNDLE) $(INSTALL_DIR)/$(APP)
	@echo "Installed to $(INSTALL_DIR)/$(APP)"

release:
	@swift build -c release

dist: app
	@cd .build && zip -r Dropbar-v0.1.0.zip $(APP)
	@echo "Built .build/Dropbar-v0.1.0.zip"

clean:
	@swift package clean
	@rm -rf $(BUNDLE)
