APP_NAME := Lumen

.PHONY: build run release clean

build:
	swift build

run:
	swift run

release:
	swift build -c release

clean:
	swift package clean
	rm -rf .build dist

# bundle / dmg targets are added in milestone M7 (Scripts/bundle.sh, Scripts/make-dmg.sh)
