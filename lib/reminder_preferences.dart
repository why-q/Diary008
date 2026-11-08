enum ReminderMode { automatic, daily }

class ReminderPreferences {
  const ReminderPreferences({
    this.mode = ReminderMode.automatic,
    this.hour = 9,
    this.minute = 0,
  }) : assert(hour >= 0 && hour <= 23),
       assert(minute >= 0 && minute <= 59);

  final ReminderMode mode;
  final int hour;
  final int minute;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'hour': hour,
    'minute': minute,
  };

  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    final mode = switch (json['mode']) {
      'automatic' => ReminderMode.automatic,
      'daily' => ReminderMode.daily,
      _ => throw const FormatException('提醒模式无效'),
    };
    final hour = json['hour'];
    final minute = json['minute'];
    if (hour is! int ||
        hour < 0 ||
        hour > 23 ||
        minute is! int ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('提醒时间无效');
    }
    return ReminderPreferences(mode: mode, hour: hour, minute: minute);
  }

  ReminderPreferences copyWith({ReminderMode? mode, int? hour, int? minute}) =>
      ReminderPreferences(
        mode: mode ?? this.mode,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderPreferences &&
      other.mode == mode &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(mode, hour, minute);
}
