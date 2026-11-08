# Diary features — 2026-10-22

Approved behavior for high display refresh, copying an entry body, and deleting an archived volume. Notebook JSON stays schema 4. These features do not renumber on migration, do not edit historical prose, and do not add a second writable volume.

## Architecture

The notebook remains one immutable `Notebook` in `lib/notebook.dart`, stored by atomic replacement of `notebook.json`. The current volume is the only writable volume. Archives stay read-only for fulfill, revise, and rename. `NotebookPage` in `lib/main.dart` owns load, expiry, persist, the open archive selection, and reminder sync. `VolumePicker` only returns a `VolumeSelection`. Android display mode is chosen in `MainActivity` and is not visible to the notebook model.

Entry identity stays `id` plus `parentId`. Those strings are not rewritten when a volume number changes. Reminder payloads are derived at sync time from the current volume number and entry id; archives never schedule reminders.

## High refresh

On Android API 30 and later, `MainActivity.onCreate` reads `display.supportedModes`, keeps only modes with the active mode's physical width and height and a strictly higher refresh rate, and sets `preferredDisplayModeId` to the eligible mode with the highest refresh rate. If several eligible modes share that rate, the first maximum returned by `maxByOrNull` is used. If no mode qualifies, no preference is set. Below API 30 the call returns immediately. A null display, a null window, or any platform failure is swallowed by `runCatching`; startup continues without a new mode preference, and Android remains responsible for the actual selected mode.

This is a window preference, not a promise of 120 Hz. Power policy, user settings, and multi-window can ignore it. iOS is unchanged. No notebook field, notification, or frame-scheduling API is involved.

## Copy

Every paragraph, including read-only archive paragraphs, shows a compact copy control with tooltip `复制正文`. It writes only `entry.text` through `Clipboard.setData`. It does not copy the date, status, annotation, volume title, or sibling entries, and it does not change the notebook.

After a successful write, if the paragraph is still mounted, the page shows `正文已复制。` and hides any current snackbar first. If the element is gone, it does not show the snackbar. The control stays available while a fulfill/revise drag is armed; copy does not fulfill or revise.

## Archive deletion

Only an existing archive can be deleted. `Notebook.deleteArchivedVolume` throws `StateError` (`只能删除已封存的卷`) for the writable volume number or any number that is not an archive. The original notebook is left unchanged.

On success the matching archive is removed. Every remaining archive whose number is greater than the deleted number, and the current volume when its number is greater, decreases by one. Earlier archives keep their numbers. Order, names, reasons, `invalidatedAt`, `archivedAt`, `failedEntryIds`, sort order, and entry objects (including ids and parent links) are preserved. The result is contiguous when the input volumes were contiguous. Schema version stays 4.

In `翻阅卷册`, each archived row has `删除`. The writable row does not. Confirmation is an alert titled `删除封存卷`, naming the volume and stating that its records are permanently deleted and later volume numbers shift forward. Cancel closes only the alert. Confirm closes the sheet with `VolumeSelection.delete`.

`NotebookPage` applies the delete only if the page is still mounted, not busy, and expiry did not already roll the book forward. Persist uses the existing atomic write and passes the removed number so selection updates in the same `setState` as the new book:

- The open selection is the deleted volume: return to the current volume and the pending filter.
- The open selection is a later archive: decrement that selection and keep its filter.
- The open selection is an earlier archive: keep both selection and filter.
- The current volume is open: reset its filter to pending, matching other current-volume number changes.

A successful save shows `这一卷已删除，其后卷号已前移。` and refreshes reminders so payloads use the new current volume number. Entry ids inside those payloads stay the same.

## Failure handling

- High refresh: if no mode qualifies or a platform failure is caught, no new mode preference is applied; the failure does not block `FlutterActivity`, and Android remains responsible for the actual selected mode.
- Copy: there is no notebook write to roll back. The snackbar is skipped when the widget is unmounted after the clipboard call.
- Delete confirmation cancel, sheet dismiss, or an expiry rollover before the action is applied: no archive is removed.
- Delete of the current volume or a missing archive: `StateError`, snackbar `只能删除已封存的卷。`, book unchanged.
- Persist failure, including delete: the previous file remains, the in-memory book is not replaced, and the notice is `落笔未能保存，请重试。` Reminder sync is not started from that failed save.
- Reminder sync failure after a successful delete is separate from the save, using the existing reminder error flag. The deleted notebook stays saved.

## Tests

- `test/journal_page_test.dart`: the copy control writes the entry body and shows `正文已复制。`
- `test/volume_management_test.dart`: deleting volume 1 shifts later volumes and the current volume without rewriting ids; deleting a middle archive keeps the earlier missed-deadline record and shifts the later archive; the writable volume and an unknown volume throw.
- `test/volume_picker_test.dart`: delete requires confirmation, cancel leaves the sheet open with no selection, and confirm returns `VolumeAction.delete` for that archive.
- `flutter analyze` and `flutter test` cover the Dart changes. `cd android && ./gradlew :app:compileDebugKotlin` covers the refresh-rate Kotlin. `flutter test integration_test -d emulator-5554` remains the device check for existing notebook flows; it needs that emulator and is not the proof of display-mode selection.
