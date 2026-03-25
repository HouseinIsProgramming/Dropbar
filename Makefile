run:
	@pkill -x Dropbar 2>/dev/null || true
	@swift run

build:
	@swift build

test:
	@swift test

clean:
	@swift package clean
