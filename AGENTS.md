# Device development workflow

After implementing app changes, run `bash scripts/run-ios-device.sh` to build
incrementally in Debug, update the connected iPhone, and launch the app for review.
Keep the stable derived-data directory so subsequent builds reuse compiled work.
Do not clean, archive/export, or uninstall the app for everyday iteration.
Preserve the device's library and other app data. Regenerate the project with
XcodeGen when adding, removing, or renaming source files, before running the script.

The signing key already trusts Xcode and codesign. Never store keychain passwords
in scripts, logs, or project files. Report a locked keychain or locked/disconnected
phone honestly; do not claim launch succeeded unless the command confirms it.
