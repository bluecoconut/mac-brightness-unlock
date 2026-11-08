.PHONY: app build test test-hardware release clean

app:
	./scripts/build.sh

build: app

test-hardware:
	./scripts/test-hardware.sh

test:
	./scripts/test.sh

release: app
	cd build && ditto -c -k --sequesterRsrc --keepParent "Brightness Unlock.app" "Brightness-Unlock.zip"
	cd build && shasum -a 256 Brightness-Unlock.zip > Brightness-Unlock.zip.sha256

clean:
	rm -rf build
