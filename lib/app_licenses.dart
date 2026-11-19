import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerAppFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, asset) in const [
      ('Ma Shan Zheng', 'assets/fonts/MaShanZheng-OFL.txt'),
      ('Kalam', 'assets/fonts/Kalam-OFL.txt'),
      ('Noto Serif SC', 'assets/fonts/NotoSerifSC-OFL.txt'),
      ('Noto Sans SC', 'assets/fonts/NotoSansSC-OFL.txt'),
      ('Literata', 'assets/fonts/Literata-OFL.txt'),
      ('Inter', 'assets/fonts/Inter-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString(asset));
    }
  });
}
