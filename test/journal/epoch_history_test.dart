import 'dart:convert';

import 'package:diary008/journal/epoch_history.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-4c71';

EpochHistory history({List<String> epochs = const ['ep-01', 'ep-02']}) =>
    EpochHistory(notebookId: _notebook, epochs: epochs);

void main() {
  group('ledger construction', () {
    test('preserves the explicit order and exposes the newest epoch', () {
      final ledger = history(epochs: const ['ep-01', 'ep-02', 'ep-03']);
      expect(ledger.epochs, ['ep-01', 'ep-02', 'ep-03']);
      expect(ledger.latest, 'ep-03');
      expect(ledger.length, 3);
      expect(ledger.notebookId, _notebook);
    });

    test('an initial epoch is explicit and never inferred', () {
      final ledger = EpochHistory.start(
        notebookId: _notebook,
        initialEpochId: 'ep-a1',
      );
      expect(ledger.epochs, ['ep-a1']);
      expect(ledger.latest, 'ep-a1');
    });

    test('an empty ledger is rejected, so no notebook has zero epochs', () {
      expect(
        () => EpochHistory(notebookId: _notebook, epochs: const []),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('duplicate epochs are rejected rather than collapsed', () {
      expect(
        () => history(epochs: const ['ep-01', 'ep-01']),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => history(epochs: const ['ep-01', 'ep-02', 'ep-01']),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('the epochs list is unmodifiable', () {
      final ledger = history();
      expect(() => ledger.epochs.add('ep-09'), throwsUnsupportedError);
    });

    test('the ledger rejects invalid and numeric-only identifiers', () {
      expect(
        () => EpochHistory(notebookId: _notebook, epochs: const ['9']),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => EpochHistory(notebookId: _notebook, epochs: const ['ep 01']),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => EpochHistory(notebookId: '4', epochs: const ['ep-01']),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('append', () {
    test('returns a new ledger and leaves the original untouched', () {
      final original = history(epochs: const ['ep-01']);
      final appended = original.append('ep-02');
      expect(original.epochs, ['ep-01']);
      expect(appended.epochs, ['ep-01', 'ep-02']);
      expect(appended.latest, 'ep-02');
      expect(appended.notebookId, _notebook);
    });

    test('rejects an epoch already recorded anywhere in the ledger', () {
      final original = history(epochs: const ['ep-01', 'ep-02']);
      expect(
        () => original.append('ep-01'),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => original.append('ep-02'),
        throwsA(isA<JournalFormatException>()),
      );
      expect(original.epochs, ['ep-01', 'ep-02']);
    });

    test('rejects an invalid fresh epoch', () {
      expect(
        () => history().append('77'),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('three successive appends keep every epoch in order', () {
      var ledger = EpochHistory.start(
        notebookId: _notebook,
        initialEpochId: 'ep-a',
      );
      ledger = ledger.append('ep-b').append('ep-c').append('ep-d');
      expect(ledger.epochs, ['ep-a', 'ep-b', 'ep-c', 'ep-d']);
    });
  });

  group('append-only extension', () {
    test('an equal ledger is an extension of itself', () {
      final ledger = history();
      expect(ledger.isAppendOnlyExtensionOf(history()), isTrue);
    });

    test('a longer ledger that keeps the prefix is an extension', () {
      final prior = history(epochs: const ['ep-01', 'ep-02']);
      final next = history(epochs: const ['ep-01', 'ep-02', 'ep-03']);
      expect(next.isAppendOnlyExtensionOf(prior), isTrue);
    });

    test('a strict prefix of the prior ledger is not an extension', () {
      final prior = history(epochs: const ['ep-01', 'ep-02', 'ep-03']);
      final truncated = history(epochs: const ['ep-01', 'ep-02']);
      // Refused as a value, not as a range error on the missing tail.
      expect(truncated.isAppendOnlyExtensionOf(prior), isFalse);
    });

    test('dropping the oldest epoch is not an extension', () {
      final prior = history(epochs: const ['ep-01', 'ep-02', 'ep-03']);
      final next = history(epochs: const ['ep-02', 'ep-03']);
      expect(next.isAppendOnlyExtensionOf(prior), isFalse);
    });

    test('dropping a middle epoch is not an extension', () {
      final prior = history(epochs: const ['ep-01', 'ep-02', 'ep-03']);
      final next = history(epochs: const ['ep-01', 'ep-03']);
      expect(next.isAppendOnlyExtensionOf(prior), isFalse);
    });

    test('reordering epochs is not an extension', () {
      final prior = history(epochs: const ['ep-01', 'ep-02']);
      final next = history(epochs: const ['ep-02', 'ep-01']);
      expect(next.isAppendOnlyExtensionOf(prior), isFalse);
    });

    test('replacing an epoch with a different one is not an extension', () {
      final prior = history(epochs: const ['ep-01', 'ep-02']);
      final next = history(epochs: const ['ep-01', 'ep-09']);
      expect(next.isAppendOnlyExtensionOf(prior), isFalse);
    });

    test('a ledger for another notebook is never an extension', () {
      final prior = history();
      final next = EpochHistory(
        notebookId: 'nb-other',
        epochs: const ['ep-01', 'ep-02', 'ep-03'],
      );
      expect(next.isAppendOnlyExtensionOf(prior), isFalse);
    });
  });

  group('document encoding', () {
    test('round trips exactly and carries no timestamps', () {
      final ledger = history(epochs: const ['ep-01', 'ep-02']);
      final json = ledger.toJson();
      expect(json.keys.toSet(), {
        'schemaVersion',
        'format',
        'notebookId',
        'epochs',
      });
      final decoded = EpochHistory.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(decoded.epochs, ledger.epochs);
      expect(decoded.notebookId, ledger.notebookId);
      expect(decoded.encode(), ledger.encode());
    });

    test('rejects an unsupported schema version', () {
      final json = Map<String, Object?>.from(history().toJson());
      json['schemaVersion'] = 2;
      expect(
        () => EpochHistory.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects a missing discriminator and a wrong one', () {
      final missing = Map<String, Object?>.from(history().toJson())
        ..remove('format');
      expect(
        () => EpochHistory.fromJson(missing),
        throwsA(isA<JournalFormatException>()),
      );
      final wrong = Map<String, Object?>.from(history().toJson())
        ..['format'] = 'something.else';
      expect(
        () => EpochHistory.fromJson(wrong),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects an unknown key without echoing it', () {
      final json = Map<String, Object?>.from(history().toJson())
        ..['createdAt'] = '2026-11-19T00:00:00Z';
      JournalFormatException? caught;
      try {
        EpochHistory.fromJson(json);
      } on JournalFormatException catch (error) {
        caught = error;
      }
      expect(caught, isNotNull);
      expect(caught!.message, isNot(contains('createdAt')));
      expect(caught.field, isNot(contains('createdAt')));
    });

    test('rejects a stored duplicate ledger', () {
      final json = Map<String, Object?>.from(history().toJson())
        ..['epochs'] = ['ep-01', 'ep-01'];
      expect(
        () => EpochHistory.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects a stored empty ledger', () {
      final json = Map<String, Object?>.from(history().toJson())
        ..['epochs'] = <String>[];
      expect(
        () => EpochHistory.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects non-object, non-list, and non-string epochs', () {
      expect(
        () => EpochHistory.fromJson('not an object'),
        throwsA(isA<JournalFormatException>()),
      );
      final notList = Map<String, Object?>.from(history().toJson())
        ..['epochs'] = 'ep-01';
      expect(
        () => EpochHistory.fromJson(notList),
        throwsA(isA<JournalFormatException>()),
      );
      final notString = Map<String, Object?>.from(history().toJson())
        ..['epochs'] = [42];
      expect(
        () => EpochHistory.fromJson(notString),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('never echoes a malformed epoch value in the error', () {
      final json = Map<String, Object?>.from(history().toJson())
        ..['epochs'] = ['secret diary words'];
      JournalFormatException? caught;
      try {
        EpochHistory.fromJson(json);
      } on JournalFormatException catch (error) {
        caught = error;
      }
      expect(caught, isNotNull);
      expect(caught!.toString(), isNot(contains('secret')));
    });
  });
}
