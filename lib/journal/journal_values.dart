/// Shared value types and validation for the offline entry journal protocol.
///
/// Everything here is pure Dart: no `dart:io`, no Flutter, and no ambient
/// clock. Instants must be supplied explicitly and are always UTC; calendar
/// dates travel as [CivilDate] so no local time zone can shift them.
library;

/// Protocol revision understood by this build.
const int journalSchemaVersion = 1;

/// Raised when stored or incoming journal data is malformed or unsupported.
class JournalFormatException implements Exception {
  const JournalFormatException(this.message, {this.field});

  final String message;
  final String? field;

  @override
  String toString() => field == null
      ? 'JournalFormatException: $message'
      : 'JournalFormatException($field): $message';
}

/// A calendar date without a time zone or an instant.
///
/// Civil dates are the only dates the protocol accepts, because a diary "day"
/// cannot be derived from a UTC instant without knowing a time zone.
class CivilDate implements Comparable<CivilDate> {
  const CivilDate._(this.year, this.month, this.day);

  factory CivilDate(int year, int month, int day) {
    if (year < 1 || year > 9999) {
      throw const JournalFormatException(
        'year must be between 1 and 9999',
        field: 'civilDate',
      );
    }
    final probe = DateTime.utc(year, month, day);
    if (probe.year != year || probe.month != month || probe.day != day) {
      throw const JournalFormatException(
        'not a valid calendar date',
        field: 'civilDate',
      );
    }
    return CivilDate._(year, month, day);
  }

  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  factory CivilDate.parse(Object? value) {
    if (value is! String) {
      throw const JournalFormatException(
        'civil date must be a string',
        field: 'civilDate',
      );
    }
    final match = _pattern.firstMatch(value);
    if (match == null) {
      throw const JournalFormatException(
        'civil date must use YYYY-MM-DD',
        field: 'civilDate',
      );
    }
    return CivilDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int year;
  final int month;
  final int day;

  String get text =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(CivilDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => text;
}

final RegExp _utcInstantPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$',
);

/// Parses an explicit UTC instant written with a trailing `Z`.
///
/// Numeric offsets such as `+08:00` are rejected: accepting them would let a
/// wall clock decide which instant an operation carries.
DateTime parseUtcInstant(Object? value, {String field = 'instant'}) {
  if (value is! String) {
    throw JournalFormatException('instant must be a string', field: field);
  }
  final match = _utcInstantPattern.firstMatch(value);
  if (match == null) {
    throw JournalFormatException(
      'instant must be UTC in YYYY-MM-DDTHH:MM:SS[.ffffff]Z form',
      field: field,
    );
  }
  final micros = match.group(7) == null
      ? 0
      : int.parse(match.group(7)!.padRight(6, '0'));
  final instant = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
    0,
    micros,
  );
  if (instant.year != int.parse(match.group(1)!) ||
      instant.month != int.parse(match.group(2)!) ||
      instant.day != int.parse(match.group(3)!) ||
      instant.hour != int.parse(match.group(4)!) ||
      instant.minute != int.parse(match.group(5)!) ||
      instant.second != int.parse(match.group(6)!)) {
    throw JournalFormatException(
      'instant is not a valid UTC timestamp',
      field: field,
    );
  }
  return instant;
}

/// Formats an explicit UTC instant with a trailing `Z`.
String formatUtcInstant(DateTime value, {String field = 'instant'}) {
  if (!value.isUtc) {
    throw JournalFormatException(
      'instant must be UTC; convert before recording',
      field: field,
    );
  }
  return value.toIso8601String();
}

final RegExp _opaqueIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

/// Checks an opaque identifier.
///
/// Identifiers are short ASCII tokens. All-digit values are rejected so a
/// mutable volume ordinal, a count, or a timestamp can never pose as identity,
/// and the token character set keeps diary text out of the identifier space.
String requireOpaqueId(Object? value, {required String field}) {
  if (value is! String) {
    throw JournalFormatException('$field must be a string', field: field);
  }
  if (!_opaqueIdPattern.hasMatch(value)) {
    throw JournalFormatException(
      '$field must be 1-128 characters from A-Z a-z 0-9 . _ : - and must '
      'start with a letter or digit',
      field: field,
    );
  }
  if (!value.contains(RegExp(r'[A-Za-z]'))) {
    throw JournalFormatException(
      '$field must not be numeric only; use a stable opaque identifier',
      field: field,
    );
  }
  return value;
}

/// Maximum accepted entry text length, in UTF-16 code units.
const int journalMaxTextLength = 100000;

/// Checks user text carried by an operation.
///
/// Empty or whitespace-only text is rejected: this protocol records creation
/// and revision only, so there is no text-free operation to admit.
String requireJournalText(Object? value, {String field = 'text'}) {
  if (value is! String) {
    throw JournalFormatException('$field must be a string', field: field);
  }
  if (value.trim().isEmpty) {
    throw JournalFormatException('$field must not be empty', field: field);
  }
  if (value.length > journalMaxTextLength) {
    throw JournalFormatException(
      '$field must be at most $journalMaxTextLength code units',
      field: field,
    );
  }
  return value;
}

/// Requires a decoded JSON object with string keys.
Map<String, Object?> requireJsonObject(Object? value, {required String field}) {
  if (value is! Map) {
    throw JournalFormatException('$field must be an object', field: field);
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw JournalFormatException('$field keys must be strings', field: field);
    }
    result[key] = entry.value;
  }
  return result;
}

/// Rejects a JSON object whose keys are not exactly [allowed].
void requireExactKeys(
  Map<String, Object?> json,
  Set<String> allowed, {
  required String field,
}) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw JournalFormatException(
        'unknown key',
        field: field.isEmpty ? key : '$field.$key',
      );
    }
  }
  for (final key in allowed) {
    if (!json.containsKey(key)) {
      throw JournalFormatException(
        'missing required key',
        field: field.isEmpty ? key : '$field.$key',
      );
    }
  }
}

/// Reads a required key from a decoded JSON object.
Object? requireJsonValue(
  Map<String, Object?> json,
  String key, {
  required String field,
}) {
  if (!json.containsKey(key)) {
    throw JournalFormatException(
      'missing required key',
      field: field.isEmpty ? key : '$field.$key',
    );
  }
  return json[key];
}
