# Repository notes

- Run Android integration tests only on disposable devices. Use `integration_test/support/notebook_test_helpers.dart` to snapshot on-device files before writing fixtures and restore them in `finally`. Preserve reminder scheduling barriers around file restoration.
- The four downloadable TTFs are pinned font binaries and test fixtures even though they are not bundled in `pubspec.yaml`. Keep their license texts packaged.
- `android/app/src/main/res/raw/keep.xml` keeps the notification icon discoverable by resource name in shrunk release builds.
