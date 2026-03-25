run:
	@pkill -x Dropbar 2>/dev/null || true
	@swift run

kill:
	@pkill -x Dropbar 2>/dev/null; echo "killed"

build:
	@swift build

test:
	@swift test

clean:
	@swift package clean
