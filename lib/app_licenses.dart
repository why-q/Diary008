import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerAppFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Ma Shan Zheng',
    ], await rootBundle.loadString('assets/fonts/MaShanZheng-OFL.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Cormorant Garamond',
    ], await rootBundle.loadString('assets/fonts/CormorantGaramond-OFL.txt'));
  });
}
