# Repository notes

- Run Android integration tests only on disposable devices. Use `integration_test/support/notebook_test_helpers.dart` to snapshot on-device files before writing fixtures and restore them in `finally`. Preserve reminder scheduling barriers around file restoration.
- The four downloadable TTFs are pinned font binaries and test fixtures even though they are not bundled in `pubspec.yaml`. Keep their license texts packaged.
- `android/app/src/main/res/raw/keep.xml` keeps the notification icon discoverable by resource name in shrunk release builds.

## Testing and delivery

- If the Flutter SDK is missing, install it before running `flutter test`. Don't skip tests because the SDK isn't preinstalled.
- After the tests pass, push the feature branch and enable auto-merge on its pull request into `main`. Don't bypass required checks or reviews.
