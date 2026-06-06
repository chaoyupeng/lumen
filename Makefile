APP_NAME := Lumen
VERSION ?= 0.1.0

.PHONY: build run release clean bundle dmg

build:
	swift build

run:
	swift run

release:
	swift build -c release

bundle:
	bash Scripts/bundle.sh $(VERSION)

dmg: bundle
	bash Scripts/make-dmg.sh $(VERSION)

clean:
	swift package clean
	rm -rf .build dist
