# Flutter Notebook Implementation Plan

**Goal:** 在 Android 模拟器运行古朴的连续日记原型，支持新增、期限、滑动履行与修订，以及整卷逾期重置。

**Architecture:** Flutter MaterialApp 仅提供导航与日期弹窗；笔记正文使用独立纸张主题。Notebook 模型负责期限与历史，JSON 文件通过 path_provider 保存；页面订阅生命周期并在前台检查逾期。无后端、自然语言解析或 Web 目标；本地通知及短时后台重排见已批准扩展。

**Tech Stack:** Flutter 3.47.7, Dart 3.13.5, Android API 36, path_provider, Flutter localization.

## Global Constraints
- 正文为统一字号的连续段落，无标题、编号、分割线、任务卡片。
- 日期在右下方，不加“有效至”。
- 左滑达到阈值并松手确认履行；右滑打开解释或新断言。滑动露出对应文字；已处理条目禁止手势。
- 解释和新断言提交成功后才划掉旧正文；取消不更改原记录。
- 解释没有期限；新断言必须有未来截止日期。旧正文与新内容保留关联。
- 所选日期当日结束为截止；未处理断言逾期后完整封存旧卷，再进入新空白卷。无后台服务，后台到期在下次恢复时处理；归档迁移细则见扩展设计。
- 日期快捷项为三天、一周、一个月、一年、三年；月年按日历计算并截到月末。
- 新增入口为自绘羽毛笔；不得使用 check/X 图标。
- 中文采用可商用楷体风格字体，英文采用古典衬线字体；字体随包发布。

## Task 1: Environment and Android shell
- Install Flutter, Android Studio and command-line tools via Homebrew.
- Install API 36, build tools, platform tools and arm64 Google APIs image.
- Create Diary008_API_36 emulator and Android-only project in repository root.
- Configure ANDROID_HOME and JAVA_HOME in ~/.zprofile.

## Task 2: Domain and persistence
Files: lib/notebook.dart, test/notebook_test.dart.
- Test expiry boundary (deadline day inclusive), completed/explained entries surviving expiry, replacement entering new deadline, canceled edits leaving original pending, calendar month/year clamping, JSON history round trip.
- Implement Entry status and linked supplements with serialization; reconciliation archives the full invalidated volume and opens a new blank volume, preserving all earlier archives.
- Persist JSON in application documents directory after mutations and expiry.

## Task 3: Journal surface
Files: lib/main.dart, lib/journal_theme.dart, lib/entry_editor.dart, lib/journal_page.dart, assets/fonts/.
- Warm paper and ink; bundle licensed Chinese Kai and English serif fonts.
- Empty first launch; feather opens long-text editor with calendar and date shortcuts.
- Direction-locked horizontal drag on individual paragraphs; vertical scrolling remains possible. Partial drag springs back; left threshold commits fulfilment; right opens editor. Revealed labels on opposite physical edge.
- Editor supports explanation without date and replacement with date. Save is atomic; empty content rejected.
- Resume/timer checks for expiry, atomically archives the full old volume and starts a new blank volume, with a rollover notice and read-only access to old volumes.

## Task 4: Android verification
- flutter test, flutter analyze, flutter build apk --debug.
- Install and launch on emulator; exercise new entry, date selector, left swipe, right explanation/replacement, process restart persistence. Capture screenshot of actual Android page.
- Replace generated README with launch/setup and rules, note unsupported background processing and Xcode not configured.

## Approved extension: grouped sorting, filters, and archived volumes

User approved the following archive migration, frozen historical states, group filtering, read-only history and session-only filter choice. Sorting preference persists across launches and rollover.

### Storage and migration
- Continue atomic replacement of the single `notebook.json` file. Add `schemaVersion: 2` and `archives: []`; retain current `volume`, `entries`, and `sortOrder`. New archive records contain `volume`, immutable `entries`, `invalidatedAt`, `archivedAt`, `reason: missedDeadline`, and `failedEntryIds`.
- Legacy JSON without archives is the current volume with an empty archive list, not a reason to renumber it. Preserve its existing volume number, entry IDs, parent links, original writing order and sort preference; missing preference defaults to writing. Previously deleted entries cannot be recovered.
- `invalidatedAt` is the earliest missed deadline boundary (midnight after the due date); `archivedAt` is when the application detects it. Capture failed IDs at invalidation, not at a much later launch, so later deadlines are not falsely marked as failures.
- Reconciliation appends the full old volume and starts volume N+1 atomically, with empty entries and existing sort preference. Repeated reconciliation must not duplicate the archive. On save failure, keep the old notebook visible and do not report successful rollover.

### Groups, sorting, and filters
- A root assertion and its full parent-linked revision chain form one group. Supplements remain in chronological writing order at the group tail. Root groups keep writing order by default.
- Optional deadline order puts groups with a pending assertion first, ordered by the current assertion's due date, using root writing order to break ties. Completed/explained groups follow in root writing order. Preference persists locally and survives rollover.
- Filters: all; not-yet-due; fulfilled; unfulfilled. A matching member includes its entire group; each group appears once per view. Filtering does not move or mutate entries and is independent of sorting.
- Revised originals count as unfulfilled; explicit explanations need no due date. A group with a revised original and an unexpired replacement matches both unfulfilled and not-yet-due. Fulfilled matches confirmed entries. In archives, failedEntryIds additionally match unfulfilled.
- Archived not-yet-due means pending at invalidation, not still actionable today; pending entries with later deadlines are sealed by the volume failure, not themselves failed. Historical views explain that their states are frozen at invalidation. Historical views default to all; current-volume entry points now default to pending under the approved volume-management extension below. Filter choice remains session-only.

### Historical reading
- The volume label opens a selector for current and archived volumes. An archived view shows the invalidation reason and archive time while preserving plain journal paragraphs.
- Archives are immutable: no feather/new entry, horizontal fulfill/revise gestures or accessibility mutation actions. Sorting and filtering are available for reading only. Current volume expiry must still reconcile even while an archive is selected.

### Acceptance and verification
- Model tests cover legacy migration without renumbering, complete immutable archive snapshots, earliest-deadline failure attribution, tied deadlines, offline late detection, no duplicate rollover, chained group membership across filters, stable sort and preference persistence.
- Android scenarios cover sort selection and restart, filter cross-membership without splitting a group, expired volume rollover, switching back to the original full history, disabled mutation controls on archives, and return to the editable new volume.
- Re-run analyze, all unit tests, Android E2E, build/install the ordinary APK, and inspect the actual Android surface after implementation. Update README rules and replace the obsolete destructive-reset wording.

## Approved extension: device-local reminders

- Automatically read the device time zone and target local 09:00, including DST. Time/time-zone broadcasts replan future nodes; skip past nodes and deduplicate dates per assertion. Keep calendar dates stable across travel.
- Lifetimes of at most 7 calendar days get the due-day reminder only. Longer lifetimes use offsets 1, 3, 7, 14, 30, 60, 90, 180, 270 days from persisted `createdOn`, filtered to the due date, plus the due day. Lifetimes over 30 days also get due-minus-7 days. This is a product cadence inspired by spaced repetition, not a scientific guarantee.
- Pure `lib/reminder_plan.dart` receives an explicit location and computes plans only for current pending assertions. Construct earliest next-midnight cutoff in that same location; an already-expired volume produces none. Replacements use their own creation calendar date; explanations and archives produce none.
- Schema 3 persists UTC instants (`createdAt`, archive times) separately from `YYYY-MM-DD` civil dates (`createdOn`, `due`). `lib/notebook_storage.dart` owns atomic read/write and one-time legacy migration, used by actual main `_load/_persist`. Legacy no-offset instants assume the first migration device zone; background reads never migrate or rewrite the notebook.
- `lib/reminder_service.dart` uses flutter_local_notifications 22.3.2 and timezone 0.11.2. Use inexactAllowWhileIdle, not exact-alarm privileges. Native time/time-zone/boot/update receivers enqueue a short JobScheduler job using the foreground engine or a headless entry point. Success removes the job; failure requests OS backoff. Android may delay broadcasts, jobs and delivery.
- Serialize native synchronization after load/resume and successful mutations. Stable positive IDs include volume, entry ID and civil reminder date, with collision resolution. Payload also records target instant and zone so travel updates scheduling without changing node identity. Cancel obsolete requests and fulfilled/revised/archived active notices. Report scheduling errors separately from save failures.
- A plain settings entry explains local nine oclock and cadence, shows scheduling status, requests permission only from a user action, and opens system notification settings. No exact-timing guarantee and no lockscreen assertion body.
- Tap targets identify an existing record by volume and entry ID; scheduling metadata also carries the target instant and zone, never assertion text. Locate the current or archived entry, clear the view filter and scroll to it; never recreate deleted records or enable archive editing. Capture cold-start launch details and foreground taps.
- Verify UTC/civil-date legacy migration, DST/local-nine behavior, stable dates and IDs across travel, local midnight cutoff, deduplication, replacements and cancellation. Exercise actual device-zone changes in foreground, confirmed process death with headless scheduling, cold restart and reboot restoration. Verify injected failure/backoff and successful retry removes the job. Run full Android regression, update README, build/install the ordinary APK, and commit.
- Final smoke caught a real `No response to onStartJob` ANR. Acknowledge start/stop callbacks before Flutter initialization, channel dispatch or engine teardown. Assign every broadcast job a generation in JobInfo extras so an old stop callback cannot clear a replacement's state or engine. Validate rapid replacement broadcasts and confirmed-dead-process execution in a new UTC-epoch log window; retain historical ANR evidence and remove temporary trace logging before the final build.

## Approved design: manual volumes, optional names, and pending-first reading

### Scope and decisions
- User-approved behavior: exactly one writable current volume. Creating a new volume permanently archives the old current volume, even when it contains pending assertions. Archives never resume editing or reminders. This replaces the discussed but rejected multi-active-volume design.
- Keep the existing current-entries-plus-archives structure. Manual closure and missed-deadline invalidation have the same read-only outcome, but different recorded reasons; manual closure must not falsely claim a missed deadline.
- Reuse the existing upper-right volume picker for both actions. An extra home-screen button would clutter the journal, and a long-press-only action would be undiscoverable; the picker is the chosen approach.

### Volume names and interface
- Fixed, monotonically increasing volume numbers display as `卷一`, `卷二`, and so on. An optional suffix displays as `卷一 · 晨间计划`. Users edit only the suffix, never the number or separator.
- Add `新建一卷` and `修改当前卷名` to the volume picker. New-volume entry accepts the optional next-volume name and explicitly warns that the current volume will become permanently read-only and stop reminders. Cancellation has no effect.
- Rename accepts a single-line suffix, trims surrounding whitespace, and treats an empty or whitespace-only value as unnamed. Do not truncate stored names; constrained header text may ellipsize, while the picker retains the readable full title.
- Show the same title on the journal header and picker. Archive titles retain their names permanently; archived names and assertions cannot be edited. Renaming the current volume does not alter its number, entries, deadlines or notification identities.

### Persistence and state transitions
- Add an optional `volumeName` string to both Notebook and NotebookArchive, defaulting to the empty string for old JSON. Every current-volume mutation retains its name. Both manual and automatic rollover archive the old name; an automatically opened next volume starts unnamed.
- Advance notebook schema to 4. Keep all existing IDs, numbering, parent links, writing order, sort preference and UTC/civil-date fields intact. Existing unnamed current and historical volumes remain readable without fabricated names.
- Add `ArchiveReason.manualClosure`. For manual closure, `invalidatedAt` is null, `archivedAt` is the actual closure instant, and `failedEntryIds` is empty. Existing missed-deadline archives retain their invalidation instant and failed IDs. Archived filter evaluation uses invalidatedAt when present and archivedAt otherwise.
- New-volume transition archives all current entries without rewriting their statuses, increments the volume once, creates empty current entries with the requested name, and retains sorting preference and all earlier archives. Empty current volumes can also be archived by an explicit confirmed new-volume action.
- Reconcile actual expiry before accepting a manual transition or rename. If the volume changes or expires while a dialog is open, do not apply its result to a different volume or create an extra empty volume; close the stale operation with a notice.
- Persist the complete transition with the existing atomic notebook-storage helper before displaying success. Failed writes retain the old visible state and reminders. Dialog cancellation never writes.

### Reading defaults and archive presentation
- Initial application state, returning to the current volume, manual rollover and automatic rollover default to `NotebookFilter.pending` (尚未到期). Preserve the user's in-session selection while remaining on the same volume.
- Historical volumes default to all entries. Existing whole-revision-chain selection is unchanged: any matching member includes its entire chain; the pending default does not promise that every displayed member is itself pending.
- Manual archive UI shows `主动封存` and the actual sealing time, without a fictitious invalidation date or overdue explanation. Pending members are `随卷封存`, not falsely `未如期履行`. Missed-deadline UI retains its real failure explanation. All archive mutation controls stay disabled.
- Keep all other filter choices available. A pending-empty view with existing records explains that no assertions currently await fulfillment and that the user can switch to all; do not misrepresent preserved records as deleted.

### Reminder boundary
- Reminder planning continues to use current entries only, regardless of the volume currently being read. After a successful new-volume save, run the existing serialized synchronization to remove old-volume scheduled requests and active notifications. An empty new volume has no reminders until an assertion is added.
- Renaming a volume does not replan notifications. Notification clicks on a retained archived entry may open it read-only, but cannot reactivate the volume or recreate a record.
- Preserve the established device-local nine-oclock, DST, job-generation and UTC/civil-date behavior; no new background lifecycle or parallel writable-volume subsystem.

### Acceptance and verification
- Model regression: manual closure preserves complete linked history and name, records the correct reason without failed IDs, increments once, preserves prior archives and sorting, rejects editing archived entries, and stops old-volume plans. Expired current volumes follow expiry handling rather than fabricated manual closure.
- Name regression: legacy JSON defaults unnamed; rename survives writing, fulfillment, revision, sorting, persistence and both rollover paths; old archive names remain unchanged and clearing the current suffix restores the fixed title.
- Android regression: new-volume cancellation is inert; confirmation seals the old volume and cancels its reminders; old content/name remain read-only; names persist across restart; current pending-first defaults and archived-all defaults work without splitting revision chains.
- Run analyzer, unit tests, existing Android interaction regressions, and a normal debug APK. Exercise the new volume/name dialogs on the actual emulator, inspect pending requests/native alarms across manual closure, and restore any preexisting notebook and device settings after smoke verification.

### Implementation sequence: approved volume management

1. Domain and migration — modify `lib/notebook.dart`; add `test/volume_management_test.dart`. Introduce `Notebook.withVolumeName(String)`, `Notebook.startNewVolume(String, DateTime)`, `volumeName` on current/archive records, `ArchiveReason.manualClosure`, nullable archive invalidatedAt, and schema 4. Carry the current name through every existing immutable mutation. Archive filtering passes `invalidatedAt ?? archivedAt`; manual snapshots have no failed IDs. Preserve expiry handling by rejecting manual creation once the current volume expires. Add failing tests for complete manual snapshots, archival edit rejection, name retention across all mutations and both rollover paths, legacy unnamed JSON, nullable-date round trips, grouped historical filters, and no plans for sealed entries. Run `flutter test test/volume_management_test.dart` before implementation (expected missing-API failure) and after implementation (expected pass).
2. Volume UI — modify `lib/volume_picker.dart`, `lib/journal_theme.dart`, `lib/main.dart`; add `lib/volume_name_dialog.dart`. Add `journalVolumeTitle(int, String)` for consistent fixed-number/suffix titles. Return a typed picker action for view, new or rename instead of overloading integer volume selection. The reusable name dialog owns/disposes its controller, trims its single-line optional suffix, warns before destructive new-volume confirmation, and returns null on cancellation. UI captures the original current volume, rechecks it and expiry after the dialog, and only changes selected volume/filter after a successful atomic save. Long header titles are constrained and ellipsized; archived titles remain readable in the picker. Manual archives show actual sealing time and reason, never a fabricated expiry date. Rename uses `_persist(..., updateReminders: false)`; new-volume creation uses ordinary reminder synchronization.
3. Reading defaults — modify `lib/main.dart` and existing interaction tests. Initialize current view with pending; reset to pending on rollover and selection of current volume, and to all on historical selection. Keep manual filter changes in the same volume and existing whole-chain membership. Keep notification-click navigation's all-filter override so an archived or completed target remains locatable. Use a pending-empty message that distinguishes existing hidden content from a genuinely blank volume.
4. Consumer regression — extend `integration_test/archive_filter_flow_test.dart` with cancellation, current rename/clear, confirmed new-volume creation, historical read-only reason/name, pending-first current versus all-history defaults, grouped replacement visibility and disk reload. Update existing `integration_test/notebook_flow_test.dart` and archive tests for approved current defaults and Chinese volume titles without asserting incidental copy. Run `flutter analyze`, `flutter test`, and `flutter test integration_test -d emulator-5554`; expected no diagnostics or failed cases.
5. Android smoke and delivery — build/install ordinary `flutter build apk --debug` after instrumentation tests. Save the original emulator notebook and settings first; use a named test volume with a future assertion, observe pending/native alarms, confirm manual new-volume creation, and verify old-volume alarms and active notices are removed. Exercise dialogs, archive read-only state, default pending and stored titles on the actual surface; capture screenshots. Restore original data/settings, update README with behavior and only executed evidence, then commit the complete feature. Do not modify the already-verified native time-zone/job implementation.
