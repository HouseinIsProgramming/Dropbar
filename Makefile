run:
	@pkill -x Dropbar 2>/dev/null || true
	@swift run

kill:
	@pkill -x Dropbar 2>/dev/null; echo "killed"

build:
	@swift build

test:
	@swift test

install: release
	@cp .build/release/Dropbar /usr/local/bin/Dropbar
	@echo "Installed to /usr/local/bin/Dropbar"

release:
	@swift build -c release
	@echo "Built .build/release/Dropbar"

clean:
	@swift package clean
