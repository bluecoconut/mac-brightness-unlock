# Publishing Brightness Unlock

Suggested GitHub repository name: `mac-brightness-unlock`.

Suggested description:

> Brightness Unlock unlocks native SDR brightness up to 1,000 nits on compatible MacBook Pro and Apple XDR displays, with independent menu bar controls.

Suggested topics: `macos`, `macbook-pro`, `brightness`, `brightness-control`, `xdr`, `mini-led`, `studio-display`, `menu-bar`, `objective-c`.

## First push

Create an empty GitHub repository without initializing a README, license, or gitignore. From this checkout, use the new repository URL:

```sh
git remote add origin <new-repository-url>
git push -u origin main
```

The first push triggers the build workflow. Confirm its tests and build pass before publishing the first release.

## Publish a downloadable release

The current app version is `2.0.0`. The tag must match `CFBundleShortVersionString` in `Resources/Info.plist`; the workflow rejects mismatched tags.

```sh
git tag -a v2.0.0 -m 'Brightness Unlock 2.0.0: independent native brightness controls'
git push origin v2.0.0
```

The workflow creates a GitHub Release with `Brightness-Unlock.zip` and `Brightness-Unlock.zip.sha256`. GitHub also provides source archives. Subsequent `v*` tags follow the same process after updating the app version and incrementing `CFBundleVersion`.

## Local validation

```sh
make test
make release
lipo -archs 'build/Brightness Unlock.app/Contents/MacOS/BrightnessUnlock'  # expect x86_64 and arm64
codesign --verify --deep --strict 'build/Brightness Unlock.app'
(cd build && shasum -a 256 -c Brightness-Unlock.zip.sha256)
```

The standard tests use fake displays and never change hardware settings. `make test-hardware` is an explicit, separate test for the documented two-display setup; it changes brightness and leaves both screens boosted. Do not run it in CI.

GitHub Actions needs its normal `GITHUB_TOKEN` with the workflow’s declared contents-write permission to publish releases. No signing certificate or additional repository secret is required for the current ad-hoc-signed builds.
