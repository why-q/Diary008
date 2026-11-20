import 'package:diary008/journal/epoch_history.dart';
import 'package:diary008/journal/epoch_history_envelope.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-4c71';
const _epoch = 'ep-02';
final _now = DateTime.utc(2026, 11, 19, 9, 15, 3);

JournalCreateEntry createOp({
  String operationId = 'op-1',
  int sequence = 1,
  String entryId = 'entry-1',
  String epochId = _epoch,
}) => JournalCreateEntry(
  notebookId: _notebook,
  epochId: epochId,
  actorId: 'dev-alpha',
  sequence: sequence,
  operationId: operationId,
  recordedAt: _now,
  entryId: entryId,
  text: 'synthetic fixture text',
  createdOn: CivilDate.parse('2026-11-19'),
);

Notebook notebookWithEntry({String text = 'synthetic fixture text'}) =>
    Notebook(
      volume: 1,
      volumeName: '第一卷',
      entries: [
        JournalEntry(
          id: 'entry-1',
          text: text,
          createdAt: _now,
          createdOn: DateTime.utc(2026, 11, 19),
          due: DateTime.utc(2026, 11, 30),
          status: EntryStatus.pending,
        ),
      ],
    );

Journal journalWithOperation() {
  final journal = Journal(notebookId: _notebook, epochId: _epoch);
  journal.admit(createOp());
  return journal;
}

EpochHistory history({List<String> epochs = const ['ep-01', _epoch]}) =>
    EpochHistory(notebookId: _notebook, epochs: epochs);

EpochHistoryEnvelope v2({
  int revision = 1,
  Notebook? notebook,
  Journal? journal,
  EpochHistory? epochs,
}) => EpochHistoryEnvelope(
  envelope: NotebookEnvelope(
    revision: revision,
    notebook: notebook ?? Notebook.empty(),
    journal: journal ?? Journal(notebookId: _notebook, epochId: _epoch),
  ),
  history: epochs ?? history(),
);

void main() {
  group('document shape', () {
    test('carries version 2, its own discriminator, history, and envelope', () {
      final json = v2().toJson();
      expect(json['schemaVersion'], 2);
      expect(json['format'], 'diary008.notebook-envelope.v2');
      expect(json.keys.toSet(), {
        'schemaVersion',
        'format',
        'history',
        'envelope',
      });
      expect((json['history']! as Map).keys.toSet(), {
        'schemaVersion',
        'format',
        'notebookId',
        'epochs',
      });
    });

    test('round trips exactly through JSON and text', () {
      final document = v2(
        notebook: notebookWithEntry(),
        journal: journalWithOperation(),
      );
      final decoded = EpochHistoryEnvelope.decode(document.encode());
      expect(decoded.history.epochs, ['ep-01', _epoch]);
      expect(decoded.envelope.revision, 1);
      expect(decoded.encode(), document.encode());
    });

    test('has stable content equality', () {
      expect(v2().hasSameContentAs(v2()), isTrue);
      expect(v2(revision: 2).hasSameContentAs(v2()), isFalse);
      expect(
        v2(epochs: history(epochs: const ['ep-00', 'ep-01', _epoch]))
            .hasSameContentAs(v2()),
        isFalse,
      );
    });

    test('exposes the envelope scope', () {
      final document = v2();
      expect(document.scope.notebookId, _notebook);
      expect(document.scope.epochId, _epoch);
    });
  });

  group('history must agree with the journal', () {
    test('rejects a history for another notebook', () {
      expect(
        () => EpochHistoryEnvelope(
          envelope: NotebookEnvelope(
            revision: 1,
            notebook: Notebook.empty(),
            journal: Journal(notebookId: _notebook, epochId: _epoch),
          ),
          history: EpochHistory(
            notebookId: 'nb-other',
            epochs: const ['ep-01', _epoch],
          ),
        ),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('rejects a history whose newest epoch is not the journal epoch', () {
      expect(
        () => v2(epochs: history(epochs: const ['ep-01'])),
        throwsA(isA<EnvelopeFormatException>()),
      );
      expect(
        () => v2(epochs: history(epochs: const ['ep-01', 'ep-09'])),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test(
      'accepts a journal running under the newest epoch of a longer history',
      () {
        final document = v2(
          epochs: history(epochs: const ['ep-00', 'ep-01', _epoch]),
        );
        expect(document.history.epochs, ['ep-00', 'ep-01', _epoch]);
      },
    );
  });

  group('decode fails closed', () {
    test('rejects a missing history rather than assuming one', () {
      final json = Map<String, Object?>.from(v2().toJson())..remove('history');
      expect(
        () => EpochHistoryEnvelope.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('rejects a null or non-object history', () {
      for (final broken in <Object?>[null, 'ep-01', 7, <Object?>[]]) {
        final json = Map<String, Object?>.from(v2().toJson())
          ..['history'] = broken;
        expect(
          () => EpochHistoryEnvelope.fromJson(json),
          throwsA(isA<EnvelopeFormatException>()),
        );
      }
    });

    test('rejects a malformed history document', () {
      final json = Map<String, Object?>.from(v2().toJson())
        ..['history'] = {
          'schemaVersion': 1,
          'format': 'wrong',
          'notebookId': _notebook,
          'epochs': [_epoch],
        };
      expect(
        () => EpochHistoryEnvelope.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('rejects a truncated history instead of repairing it', () {
      final json = Map<String, Object?>.from(v2().toJson())
        ..['history'] = {
          'schemaVersion': 1,
          'format': 'diary008.epoch-history',
          'notebookId': _notebook,
          'epochs': [_epoch],
        };
      // A history holding only the current epoch is structurally valid on its
      // own; the document cannot tell that older epochs existed. It is
      // therefore accepted at decode, and only a comparison with a stored
      // document can detect the loss. See the store tests.
      final decoded = EpochHistoryEnvelope.fromJson(json);
      expect(decoded.history.epochs, [_epoch]);
    });

    test('rejects a duplicate epoch in the stored history', () {
      final json = Map<String, Object?>.from(v2().toJson())
        ..['history'] = {
          'schemaVersion': 1,
          'format': 'diary008.epoch-history',
          'notebookId': _notebook,
          'epochs': ['ep-01', 'ep-01', _epoch],
        };
      expect(
        () => EpochHistoryEnvelope.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test(
      'rejects an unsupported envelope version and a missing discriminator',
      () {
        final versioned = Map<String, Object?>.from(v2().toJson())
          ..['schemaVersion'] = 3;
        expect(
          () => EpochHistoryEnvelope.fromJson(versioned),
          throwsA(isA<EnvelopeFormatException>()),
        );
        final noFormat = Map<String, Object?>.from(v2().toJson())
          ..remove('format');
        expect(
          () => EpochHistoryEnvelope.fromJson(noFormat),
          throwsA(isA<EnvelopeFormatException>()),
        );
      },
    );

    test('rejects an unknown key without echoing it', () {
      final json = Map<String, Object?>.from(v2().toJson())
        ..['extra'] = 'secret diary words';
      EnvelopeFormatException? caught;
      try {
        EpochHistoryEnvelope.fromJson(json);
      } on EnvelopeFormatException catch (error) {
        caught = error;
      }
      expect(caught, isNotNull);
      expect(caught.toString(), isNot(contains('secret')));
    });

    test('rejects malformed JSON text', () {
      expect(
        () => EpochHistoryEnvelope.decode('{not json'),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a nested malformed V1 envelope fails closed too', () {
      final json = Map<String, Object?>.from(v2().toJson());
      final envelope = Map<String, Object?>.from(json['envelope']! as Map)
        ..['schemaVersion'] = 99;
      json['envelope'] = envelope;
      expect(
        () => EpochHistoryEnvelope.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });
  });

  group('version discrimination', () {
    test('the legacy V1 decoder refuses a V2 document', () {
      expect(
        () => NotebookEnvelope.decode(v2().encode()),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('the V2 decoder refuses a V1 document', () {
      final legacy = NotebookEnvelope(
        revision: 1,
        notebook: Notebook.empty(),
        journal: Journal(notebookId: _notebook, epochId: _epoch),
      );
      expect(
        () => EpochHistoryEnvelope.decode(legacy.encode()),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });
  });

  group('advance', () {
    test('carries the stored history verbatim for an ordinary write', () {
      final stored = v2();
      final next = stored.advance(
        revision: 2,
        notebook: notebookWithEntry(),
        journal: journalWithOperation(),
      );
      expect(next.history.epochs, stored.history.epochs);
      expect(next.envelope.revision, 2);
      expect(next.scope, stored.scope);
    });

    test('accepts an explicit append-only extension for a scope change', () {
      final stored = v2();
      final journal = Journal(notebookId: _notebook, epochId: 'ep-03');
      final next = stored.advance(
        revision: 2,
        notebook: Notebook.empty(),
        journal: journal,
        history: stored.history.append('ep-03'),
      );
      expect(next.history.epochs, ['ep-01', _epoch, 'ep-03']);
      expect(next.history.latest, 'ep-03');
      expect(next.scope.epochId, 'ep-03');
    });

    test('refuses a dropped, replaced, or reordered history', () {
      final stored = v2(
        epochs: history(epochs: const ['ep-00', 'ep-01', _epoch]),
      );
      final journal = Journal(notebookId: _notebook, epochId: _epoch);
      for (final broken in [
        history(epochs: const ['ep-01', _epoch]),
        history(epochs: const ['ep-00', 'ep-01', 'ep-03']),
        history(epochs: const [_epoch, 'ep-01']),
      ]) {
        expect(
          () => stored.advance(
            revision: 2,
            notebook: Notebook.empty(),
            journal: journal,
            history: broken,
          ),
          throwsA(isA<EnvelopeFormatException>()),
        );
      }
    });

    test('refuses a history for another notebook', () {
      final stored = v2();
      expect(
        () => stored.advance(
          revision: 2,
          notebook: Notebook.empty(),
          journal: Journal(notebookId: _notebook, epochId: _epoch),
          history: EpochHistory(
            notebookId: 'nb-other',
            epochs: const ['ep-01', _epoch],
          ),
        ),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });
  });

  group('explicitly opt-in', () {
    test('the legacy V1 envelope has no history field at all', () {
      final legacy = NotebookEnvelope(
        revision: 1,
        notebook: Notebook.empty(),
        journal: Journal(notebookId: _notebook, epochId: _epoch),
      );
      expect(legacy.toJson().keys.toSet(), {
        'schemaVersion',
        'format',
        'revision',
        'notebook',
        'journal',
      });
    });
  });
}
