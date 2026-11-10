import 'package:flutter/material.dart';

import 'journal_theme.dart';
import 'notebook.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;
  bool get isEnglish => locale.languageCode == 'en';

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('zh', 'CN'));

  static AppLocalizations forLocale(Locale locale) => AppLocalizations(locale);

  static const delegate = _AppLocalizationsDelegate();

  String get appTitle => isEnglish ? 'Sealed Notebook' : '家族笔记';
  String get systemLanguage => isEnglish ? 'Follow system' : '跟随系统';
  String get simplifiedChinese => isEnglish ? '简体中文' : '简体中文';
  String get english => isEnglish ? 'English' : 'English';
  String get language => isEnglish ? 'Language' : '语言';
  String get sealedNotebook =>
      isEnglish ? 'THE SEALED NOTEBOOK' : 'THE SEALED NOTEBOOK';
  String get settings => isEnglish ? 'Settings' : '设置';
  String get appearance => isEnglish ? 'Appearance' : '外观设置';
  String get appearanceDescription => isEnglish
      ? 'Changes apply immediately. Paper palettes adapt to light and dark mode.'
      : '选择后立即应用并保存。纸张配色会同时适配浅色与深色模式。';
  String get displayMode => isEnglish ? 'Display mode' : '显示模式';
  String get themeSystem => isEnglish ? 'Follow system' : '跟随系统';
  String get themeSystemDescription =>
      isEnglish ? 'Use the device current appearance setting' : '使用设备当前的明暗设置';
  String get themeLight => isEnglish ? 'Light' : '浅色';
  String get themeDark => isEnglish ? 'Dark' : '深色';
  String get paperPalette => isEnglish ? 'Paper palette' : '纸张配色';
  String get antiquePaper => isEnglish ? 'Antique paper' : '古纸';
  String get antiquePaperDescription =>
      isEnglish ? 'Warm aged paper and brown ink' : '温暖的旧纸与棕色墨迹';
  String get plainWhite => isEnglish ? 'Plain white' : '素白';
  String get plainWhiteDescription =>
      isEnglish ? 'Clean white paper and blue-gray ink' : '清爽的白纸与蓝灰墨迹';
  String get cyanPaper => isEnglish ? 'Cyan paper' : '青笺';
  String get cyanPaperDescription =>
      isEnglish ? 'Pale cyan paper and deep teal ink' : '淡青笺纸与深青墨迹';
  String get reload => isEnglish ? 'Reload' : '重新读取';
  String get loading => isEnglish ? 'Loading notebook...' : '正在读取笔记...';
  String get filterRecords => isEnglish ? 'Filter records' : '筛选记录';
  String get sortOrder => isEnglish ? 'Sort order' : '排列方式';
  String get writingOrder => isEnglish ? 'Writing order' : '书写顺序';
  String get dueDateOrder => isEnglish ? 'Due date' : '有效日期';
  String get readOnlyArchived =>
      isEnglish ? 'Archived · read-only' : '本卷已封存 · 只读';
  String get newAssertion => isEnglish ? 'Write a new assertion' : '写下新的断言';
  String get newAssertionTooltip =>
      isEnglish ? 'Write a new assertion' : '写下新的断言';
  String get fulfillOrRevise => isEnglish
      ? 'Confirm before the due date, or leave a revision;\nwhen it expires, this volume is archived and a new page opens.'
      : '请于期限前确认履行，或留下修订；\n逾期，本卷封存，另启新页。';
  String get archivedReadOnlyHint => isEnglish
      ? 'The old volume remains; the past cannot be rewritten.'
      : '旧卷留存，往事不可改写。';
  String get swipeHint =>
      isEnglish ? 'Swipe left to fulfill · right to revise' : '左滑履行 · 右滑修订';
  String get checkReminders =>
      isEnglish ? 'Reminders unavailable · tap to check' : '提醒暂不可用 · 点击检查';
  String get enableReminders => isEnglish ? 'Enable reminders' : '开启提醒';
  String automaticReminderAt(String time) =>
      isEnglish ? 'Automatic reminders · local time $time' : '自动提醒 · 当地时间$time';
  String dailyReminderAt(String time) =>
      isEnglish ? 'Daily reminders · $time' : '每日提醒 · $time';
  String get emptyPage => isEnglish
      ? 'This page is blank,\nwaiting for your words.'
      : '此页尚白，\n故事将由你落笔。';
  String get noPending => isEnglish
      ? 'There are no assertions waiting to be fulfilled.\nChoose “All” to browse existing records.'
      : '此刻暂无待履行的预言。\n切换“全部”可翻阅已有记录。';
  String get noMatchingRecords =>
      isEnglish ? 'There are no matching records here.' : '此处暂无相应的记录。';

  String get loadError => isEnglish
      ? 'The notebook cannot be read right now. Existing content was not overwritten.'
      : '笔记暂时无法读取，原有内容未被覆盖。';
  String get saveFailed => isEnglish
      ? 'The entry could not be saved. Please try again.'
      : '落笔未能保存，请重试。';
  String get volumeExpired => isEnglish
      ? 'This volume is archived and a new blank page is open. Tap the volume number to browse older volumes.'
      : '本卷已封存，新的空白页已开启。点击卷号可翻阅旧卷。';
  String get originalExpired => isEnglish
      ? 'The original volume has expired. Please write again on the new page.'
      : '原卷已经失效，请在新页重新书写。';
  String get dateInPast => isEnglish
      ? 'That date has passed. Please choose another date.'
      : '日期已经过去，请重新选择。';
  String get fulfillTitle => isEnglish ? 'Confirm fulfillment?' : '是否确认已履行？';
  String get fulfillContent => isEnglish
      ? 'This will mark the assertion as fulfilled and cannot be undone.'
      : '确认后将标记为已履行，不能撤销。';
  String get cancel => isEnglish ? 'Cancel' : '取消';
  String get confirmFulfillment => isEnglish ? 'Confirm' : '确认履行';
  String get fulfilledNotice =>
      isEnglish ? 'This assertion has become fact.' : '这一段预言，已成为事实。';
  String get archiveDeleted => isEnglish
      ? 'The volume was deleted; later volume numbers moved up.'
      : '这一卷已删除，其后卷号已前移。';
  String get archiveDeleteOnly =>
      isEnglish ? 'Only archived volumes can be deleted.' : '只能删除已封存的卷。';
  String get volumeStateChanged =>
      isEnglish ? 'The volume changed. Please try again.' : '卷册状态已更新，请重新操作。';
  String get oldVolumeArchived => isEnglish
      ? 'The old volume is archived and a new blank page is open.'
      : '旧卷已封存，新的空白页已开启。';
  String get volumeNameSaved => isEnglish ? 'Volume name saved.' : '卷名已保存。';
  String get notebookNotLoaded => isEnglish
      ? 'The notebook is not loaded, so reminders cannot be checked.'
      : '笔记尚未加载，无法检查提醒。';
  String remindersChecked(int count) => isEnglish
      ? 'Reminders checked: notifications are on and $count future reminder(s) are scheduled.'
      : '提醒状态已检查：通知已开启，已安排 $count 次未来提醒。';
  String get remindersDisabled => isEnglish
      ? 'Reminders checked: system notifications are not enabled or the reminder channel is off.'
      : '提醒状态已检查：系统通知尚未开启，或提醒通道已关闭。';
  String reminderCheckStale(String status) => isEnglish
      ? '$status A later check may have updated the status.'
      : '$status 后续检查可能已更新状态。';
  String get reminderCheckFailure => isEnglish
      ? 'Reminder check failed. Try again or open system notification settings. Your notebook was saved.'
      : '提醒检查失败，请重试；如果持续失败，请打开系统通知设置。笔记内容已保存。';
  String get reminderCheckFailureStale => isEnglish
      ? 'This reminder check failed; a later check may have updated the status. Check again or open system notification settings. Your notebook was saved.'
      : '本次提醒检查失败；后续状态可能已更新。请重新检查或打开系统通知设置；笔记内容已保存。';
  String get permissionFailure => isEnglish
      ? 'Could not enable notifications. Check system notification settings and try again. Your notebook was saved.'
      : '启用通知提醒失败，请检查系统通知设置后重试。笔记内容已保存。';
  String settingsOpened(bool opened) => opened
      ? (isEnglish
            ? 'System notification settings opened. Check reminders again when you return.'
            : '已打开系统通知设置，返回后可重新检查提醒。')
      : (isEnglish
            ? 'Could not open system notification settings. Enable notifications for $appTitle in system settings.'
            : '无法打开系统通知设置；请在系统设置中为 $appTitle 开启通知。');
  String get settingsOpenFailure => isEnglish
      ? 'Could not open system notification settings. Enable notifications for $appTitle in system settings.'
      : '系统通知设置打开失败；请在系统设置中为 $appTitle 开启通知。';
  String get reminderPreferencesFailure => isEnglish
      ? 'Reminder settings cannot be read right now. Please try again later.'
      : '提醒设置暂时无法读取，请稍后重试。';
  String get busyReading => isEnglish
      ? 'The notebook is busy. Please try again shortly.'
      : '正在读写笔记，请稍后重试。';
  String get exportUnavailable => isEnglish
      ? 'The notebook has not loaded successfully, so a backup cannot be exported.'
      : '笔记尚未读取成功，无法导出备份。';
  String get backupChoiceTitle => isEnglish ? 'Choose backup type' : '选择备份方式';
  String get backupChoiceContent => isEnglish
      ? 'Plain-text backups are directly readable; encrypted backups require a password to restore.'
      : '明文备份可直接读取；密码加密备份需要密码才能恢复。';
  String get plainBackup => isEnglish ? 'Plain-text backup' : '明文备份';
  String get encryptedBackup =>
      isEnglish ? 'Password-encrypted backup' : '密码加密备份';
  String get exportCancelled =>
      isEnglish ? 'Backup export cancelled.' : '已取消导出备份。';
  String get backupExported => isEnglish ? 'Backup exported.' : '备份已导出。';
  String get importCancelled =>
      isEnglish ? 'Backup import cancelled.' : '已取消导入备份。';
  String replaceBackupTitle(int volumes) =>
      isEnglish ? 'Replace all records with this backup?' : '用备份替换所有记录？';
  String replaceBackupContent(int volumes, int count) => isEnglish
      ? 'The backup contains ${volumes + 1} volume(s) and $count record(s). All current volumes and records will be replaced and cannot be undone. Cancel and export current data first if needed. After restoring, expired entries in the current volume will be archived using the existing rules; reminders will be recalculated. Diagnostics will remain.'
      : '备份包含 ${volumes + 1} 卷、$count 条记录。当前所有卷和记录将被完整替换，无法撤销。建议先取消并导出当前数据。恢复后按现有规则检查期限，已逾期的当前卷会自动封存；通知将重新计算。诊断日志保留。';
  String get importReminderFailure => isEnglish
      ? 'Backup imported, but reminders could not be updated. Check reminder settings and reopen the app.'
      : '备份已导入；提醒更新未完成，请检查提醒设置并重新打开应用。';
  String get importComplete => isEnglish
      ? 'Backup imported and all records replaced.'
      : '备份已导入，已替换所有记录。';
  String get saving =>
      isEnglish ? 'Saving. Please try again shortly.' : '正在保存，请稍后重试。';
  String get reading => isEnglish
      ? 'Reading notebook. Please try again shortly.'
      : '正在读取笔记，请稍后重试。';
  String get destroyReminderFailure => isEnglish
      ? 'All records were destroyed and diagnostics remain, but reminders could not be cleared. Check reminder settings.'
      : '所有记录已销毁，日志保留；提醒清理失败，请在提醒设置中检查。';
  String get destroyComplete => isEnglish
      ? 'All records were destroyed. A blank volume is ready; diagnostics remain.'
      : '所有记录已销毁，已回到空白卷。诊断日志保留。';
  String get destroyFailure => isEnglish
      ? 'Records could not be destroyed. Please try again.'
      : '记录未能销毁，请重试。';
  String get reminderRecoveryFailure => isEnglish
      ? 'The reminder service could not recover. Close and reopen the app.'
      : '提醒后台恢复失败，请关闭并重新打开应用。';

  String filterName(NotebookFilter filter) => switch (filter) {
    NotebookFilter.all => isEnglish ? 'All' : '全部',
    NotebookFilter.pending => isEnglish ? 'Pending' : '履行中',
    NotebookFilter.fulfilled => isEnglish ? 'Fulfilled' : '已履行',
    NotebookFilter.unfulfilled => isEnglish ? 'Unfulfilled' : '未履行',
  };
  String archiveAnnotation(bool failed) => failed
      ? (isEnglish ? 'Not fulfilled on time' : '未如期履行')
      : (isEnglish ? 'Archived with volume' : '随卷封存');
  String archiveSummaryActive(DateTime date) => isEnglish
      ? 'Archived: ${dateFormat(date)}\nReason: archived manually. Status is fixed at archival.'
      : '封存：${dateFormat(date)}\n缘由：主动封存。状态以封存时为准。';
  String archiveSummaryExpired(DateTime invalidated, DateTime archived) =>
      isEnglish
      ? 'Expired: ${dateFormat(invalidated)}\nArchived: ${dateFormat(archived)}\nReason: assertion was not fulfilled before its due date. Status is fixed at expiration.'
      : '失效：${dateFormat(invalidated)}\n封存：${dateFormat(archived)}\n缘由：预言逾期未履行。状态以失效时为准。';

  String dateFormat(DateTime date) {
    if (!isEnglish) return journalDate(date);
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String volumeTitle(int volume, String name) {
    final suffix = name.trim();
    final prefix = isEnglish
        ? 'Volume $volume'
        : journalVolumeTitle(volume, '');
    return suffix.isEmpty ? prefix : '$prefix · $suffix';
  }

  String get volumePickerTitle => isEnglish ? 'Browse volumes' : '翻阅卷册';
  String writingVolume(String title) =>
      isEnglish ? '$title · Writing' : '$title · 正在书写';
  String archivedVolume(String title) =>
      isEnglish ? '$title · Archived' : '$title · 已封存';
  String get delete => isEnglish ? 'Delete' : '删除';
  String get renameCurrentVolume =>
      isEnglish ? 'Rename current volume' : '修改当前卷名';
  String get createVolume => isEnglish ? 'Start a new volume' : '新建一卷';
  String get deleteArchivedTitle =>
      isEnglish ? 'Delete archived volume' : '删除封存卷';
  String deleteArchivedContent(String title) => isEnglish
      ? 'Records in $title will be permanently deleted and cannot be recovered. Later volume numbers will move up.'
      : '$title中的记录将永久删除，无法恢复。其后各卷的卷号会依次前移。';

  String newVolumeTitle(String fixedTitle, bool creating) => creating
      ? (isEnglish ? 'Start $fixedTitle' : '新建$fixedTitle')
      : (isEnglish ? 'Rename volume' : '修改卷名');
  String sealingVolume(String title) => isEnglish
      ? '$title will be archived permanently, cannot be edited, and will no longer send reminders.'
      : '$title将永久封存，无法继续编辑，也不再提醒。';
  String get volumeNameLabel => isEnglish ? 'Volume name (optional)' : '卷名（选填）';
  String get volumeNameHint =>
      isEnglish ? 'For example: Morning plan' : '例如：晨间计划';
  String volumeNameHelper(String fixedTitle) => isEnglish
      ? 'The volume number is fixed as $fixedTitle; leave blank to show only the number.'
      : '卷号固定为$fixedTitle；留空只显示卷号。';
  String get save => isEnglish ? 'Save' : '保存';
  String get archiveAndCreate => isEnglish ? 'Archive and start' : '封存并新建';

  String get clipboardEmpty => isEnglish
      ? 'There is no text to paste from the clipboard.'
      : '剪贴板中没有可粘贴的文字。';
  String get copiedBody => isEnglish ? 'Body copied.' : '正文已复制。';
  String get dueDateHelp =>
      isEnglish ? 'Set the due date for this assertion' : '为预言落下日期';
  String get setDate => isEnglish ? 'Set' : '落定';
  String get writeFirst => isEnglish ? 'Write some text first.' : '请先写下文字。';
  String get chooseDueDate =>
      isEnglish ? 'Choose a due date for this assertion.' : '请为这段预言选择日期。';
  String get inThreeDays => isEnglish ? 'In three days' : '三天后';
  String get inOneWeek => isEnglish ? 'In one week' : '一周后';
  String get inOneMonth => isEnglish ? 'In one month' : '一个月后';
  String get inOneYear => isEnglish ? 'In one year' : '一年后';
  String get inThreeYears => isEnglish ? 'In three years' : '三年后';
  String get closeEditor => isEnglish ? 'Close' : '搁笔';
  String get continueWriting => isEnglish ? 'Continue' : '续写';
  String get revise => isEnglish ? 'Revise' : '修订';
  String get write => isEnglish ? 'Write' : '落笔';
  String get leaveExplanation => isEnglish ? 'Leave an explanation' : '留下解释';
  String get newAssertionMode => isEnglish ? 'New assertion' : '新的断言';
  String get paste => isEnglish ? 'Paste' : '粘贴';
  String get assertionHint => isEnglish ? 'I will...' : '我会……';
  String get revisionHint =>
      isEnglish ? 'This did not happen because...' : '事情未曾如此发展，是因为……';
  String get chooseDate => isEnglish ? 'Choose date' : '选择日期';
  String get dateDeadlineHint => isEnglish
      ? 'The end of the selected date is the deadline for this assertion.'
      : '所选日期的最后一刻，为这段预言的期限。';

  String get entryActions => isEnglish ? 'Entry actions' : '条目操作';
  String get copyBody => isEnglish ? 'Copy body' : '复制正文';
  String get canSwipe =>
      isEnglish ? 'Swipe left to fulfill, right to revise' : '可向左滑动确认履行，向右滑动修订';
  String get confirmAction => isEnglish ? 'Confirm fulfillment' : '确认履行';
  String get reviseAction => isEnglish ? 'Revise' : '修订';
  String swipeAction(bool left, bool reached) => left
      ? '${reached ? (isEnglish ? 'Release' : '松手') : (isEnglish ? 'Keep swiping left' : '继续左滑')}\n${isEnglish ? 'Confirm' : '确认履行'}'
      : '${reached ? (isEnglish ? 'Release' : '松手') : (isEnglish ? 'Keep swiping right' : '继续右滑')}\n${isEnglish ? 'Leave revision' : '留下修订'}';

  String get dataDiagnostics => isEnglish ? 'Data & diagnostics' : '数据与诊断';
  String get privacyNotice => isEnglish ? 'Privacy notice' : '隐私说明';
  String get openSourceLicenses => isEnglish ? 'Open-source licenses' : '开源许可';
  String get backupDescription => isEnglish
      ? 'Backups include the current volume, all archived volumes, volume names, bodies, explanations, revisions, and sort preference, but not diagnostics. Choose plain text or password encryption when exporting. An encrypted backup cannot be recovered without its password. Files sent to a cloud drive are handled by that provider.'
      : '备份包含当前卷、全部历史卷、卷名、正文、解释、修订记录和排序偏好，不包含诊断日志。导出时可选择明文或密码加密；忘记密码无法恢复加密备份。选择云盘时文件会交由该提供方处理。';
  String get exportBackup => isEnglish ? 'Export backup' : '导出备份';
  String get importBackup => isEnglish ? 'Import backup' : '导入备份';
  String get importDescription => isEnglish
      ? 'Importing completely replaces all current volumes and records; it does not merge. Export current data first if needed. You must still confirm after choosing a file.'
      : '导入将完整替换现有所有卷和记录，不进行合并。建议先导出当前数据；选择文件后仍需确认才能覆盖。';
  String get diagnosticsDescription => isEnglish
      ? 'Diagnostics stay on this device, do not record bodies or volume names, and are never uploaded automatically. When full, the oldest entries are overwritten.'
      : '日志仅保存在本机，不记录正文或卷名，不自动上传。容量达到上限后会覆盖最早的日志。';
  String get exportDiagnostics => isEnglish ? 'Export diagnostics' : '导出日志';
  String get diagnosticsExported =>
      isEnglish ? 'Diagnostics exported.' : '日志已导出。';
  String get exportCancelledShort => isEnglish ? 'Export cancelled.' : '已取消导出。';
  String get clearDiagnosticsTitle =>
      isEnglish ? 'Clear diagnostics?' : '清空日志？';
  String get clearDiagnosticsContent => isEnglish
      ? 'Delete diagnostics on this device. This does not affect the notebook or exported files.'
      : '删除本机诊断日志，不影响笔记，也不会删除已导出的文件。';
  String get confirmClearDiagnostics =>
      isEnglish ? 'Clear diagnostics' : '确认清空日志';
  String get diagnosticsCleared => isEnglish
      ? 'Diagnostics cleared; later operations will continue to be recorded.'
      : '日志已清空；之后的操作会继续记录。';
  String get destroyDescription => isEnglish
      ? 'Destruction permanently removes the current volume, all archived volumes, assertions, explanations, and revisions. Diagnostics remain and exported files are unaffected. This is not secure flash erasure.'
      : '销毁后，当前卷、全部历史卷、断言、解释和修订记录均不可恢复。诊断日志保留，已导出的文件不受影响。这不是闪存安全擦除。';
  String get destroyTitle => isEnglish ? 'Destroy all records?' : '销毁所有记录？';
  String get destroyContent => isEnglish
      ? 'All volumes and records will be permanently deleted, and existing notifications and entry reminders will be cleared. Daily writing reminders remain and will continue for the blank volume. This cannot be undone; diagnostics remain.'
      : '所有卷册和记录将永久删除，并清除已有通知和条目自动提醒。每日写作提醒设置保留，空白卷也会继续提醒。此操作不可撤销，诊断日志会保留。';
  String get confirmDestroy => isEnglish ? 'Destroy records' : '确认销毁记录';
  String get close => isEnglish ? 'Close' : '关闭';
  String get operationFailed => isEnglish
      ? 'Operation did not complete. Please try again.'
      : '操作未完成，请重试。';

  String get reminderSettings => isEnglish ? 'Assertion reminders' : '断言提醒';
  String get notificationChannelName =>
      isEnglish ? 'Notebook reminders' : '笔记提醒';
  String get notificationChannelDescription => isEnglish
      ? 'Reminders to read the notebook on schedule or at a daily time'
      : '按计划或每天固定时间提醒翻阅笔记';
  String get dailyNotificationBody => isEnglish
      ? "It is time to read the notebook and write today's record."
      : '到了约定的时间，翻阅笔记，写下今天的记录。';
  String get assertionNotificationBody => isEnglish
      ? 'There are assertions waiting to be fulfilled. Remember to read the notebook today.'
      : '笔记中有待履行的约定，今天记得翻阅。';
  String get chooseDailyTime =>
      isEnglish ? 'Choose daily reminder time' : '选择每日提醒时间';
  String get confirm => isEnglish ? 'OK' : '确定';
  String get reminderScheduleFailure => isEnglish
      ? 'Reminder scheduling is incomplete. Check again; your notebook was saved.'
      : '提醒排程未完成，请重新检查；笔记内容已保存。';
  String get checkingNotificationStatus =>
      isEnglish ? 'Checking notification status.' : '正在检查通知状态。';
  String scheduledReminders(int count) => isEnglish
      ? 'Notifications are on; $count future reminder(s) scheduled.'
      : '通知已开启，已安排 $count 次未来提醒。';
  String get notificationsOff => isEnglish
      ? 'System notifications are off or the reminder channel has been disabled.'
      : '系统通知尚未开启，或提醒通道已被关闭。';
  String get automatic => isEnglish ? 'Automatic reminders' : '自动提醒';
  String get automaticDescription => isEnglish
      ? 'Remind only for the current volume at 09:00 local time; entries due on the same day are combined. Within seven days, remind only on the due date. Longer deadlines use days 1, 3, 7, 14, 30, 60, 90, 180, and 270, plus the due date; after 30 days, add the final week. Nothing is scheduled after the earliest due date in the volume.'
      : '仅提醒当前卷，按当地上午九点安排；同一天多个条目合并为一次。七天内只在截止当天提醒；更长期限采用第1、3、7、14、30、60、90、180、270天，并保留截止当天；超过30天再加最后一周。卷内最早期限之后不再安排。';
  String get daily => isEnglish ? 'Daily reminders' : '每日提醒';
  String get dailyDescription => isEnglish
      ? 'Remind once each day at the device local time, even when there are no pending records.'
      : '每天按设备当地时间提醒一次，即使当前没有待办记录也会继续提醒。';
  String dailyTime(String time) =>
      isEnglish ? 'Daily reminder time · $time' : '每日提醒时间 · $time';
  String get timezoneNotice => isEnglish
      ? 'Reminders follow the device local time and do not replay missed times. Battery saving or notification permissions may affect delivery; punctual delivery cannot be guaranteed.'
      : '提醒跟随设备当地时间，不补发已过节点。系统省电策略或通知权限可能影响送达，无法保证准点。';
  String get settingsRetry => isEnglish
      ? 'Settings or reminder scheduling did not complete. Check settings again and retry.'
      : '设置或提醒排程未完成，请重新检查设置后重试。';
  String get enableNotifications =>
      isEnglish ? 'Enable notifications' : '启用通知提醒';
  String get recheckReminders => isEnglish ? 'Check reminders again' : '重新检查提醒';
  String get systemNotificationSettings =>
      isEnglish ? 'System notification settings' : '系统通知设置';

  String get passwordEmpty =>
      isEnglish ? 'Password cannot be empty.' : '密码不能为空。';
  String get passwordsDiffer =>
      isEnglish ? 'The two passwords do not match.' : '两次输入的密码不一致。';
  String get decryptionFailure => isEnglish
      ? 'Decryption did not complete. Please try again.'
      : '解密未完成，请重试。';
  String get setBackupPassword => isEnglish ? 'Set backup password' : '设置备份密码';
  String get enterBackupPassword =>
      isEnglish ? 'Enter backup password' : '输入备份密码';
  String get exportPasswordDescription => isEnglish
      ? 'The password is used only for this backup and is not saved. A forgotten password cannot restore the backup; in-app notes remain stored as before.'
      : '密码仅用于本次备份，不会保存。忘记密码将无法恢复备份；应用内笔记仍按原方式存储。';
  String get importPasswordDescription => isEnglish
      ? 'You will still confirm replacing records after decryption. The password is not saved.'
      : '解密成功后仍需确认替换记录。密码不会保存。';
  String get password => isEnglish ? 'Password' : '密码';
  String get confirmPassword => isEnglish ? 'Confirm password' : '再次输入密码';
  String get confirmPasswordAction => isEnglish ? 'Confirm password' : '确认密码';
  String get decryptBackup => isEnglish ? 'Decrypt backup' : '解密备份';
  String get unsupportedEncryptedBackup => isEnglish
      ? 'This encrypted backup format or its parameters are unsupported; existing records were not changed.'
      : '不支持的加密备份格式或参数，现有记录未改变。';
  String get invalidEncryptedBackup => isEnglish
      ? 'The encrypted backup is invalid or incomplete; existing records were not changed.'
      : '加密备份文件无效或不完整，现有记录未改变。';
  String get wrongBackupPassword => isEnglish
      ? 'The password is incorrect or the backup is damaged; existing records were not changed.'
      : '密码错误或备份文件已损坏，现有记录未改变。';
  String get unsupportedBackupVersion => isEnglish
      ? 'This backup version is unsupported. Use a compatible app version.'
      : '不支持的备份版本，请使用兼容版本的应用。';
  String get invalidBackup => isEnglish
      ? 'The backup file is invalid or incomplete; existing records were not changed.'
      : '备份文件无效或不完整，现有记录未改变。';
  String localizeBackupError(String message) {
    if (!isEnglish) return message;
    return switch (message) {
      '密码不能为空。' => passwordEmpty,
      '不支持的加密备份格式或参数，现有记录未改变。' => unsupportedEncryptedBackup,
      '加密备份文件无效或不完整，现有记录未改变。' => invalidEncryptedBackup,
      '密码错误或备份文件已损坏，现有记录未改变。' => wrongBackupPassword,
      '不支持的备份版本，请使用兼容版本的应用。' => unsupportedBackupVersion,
      '备份文件无效或不完整，现有记录未改变。' => invalidBackup,
      '提醒模式无效' => invalidBackup,
      '提醒时间无效' => invalidBackup,
      _ => invalidBackup,
    };
  }

  String get privacyTitleFallback => isEnglish ? 'Privacy notice' : '隐私说明';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations.forLocale(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
