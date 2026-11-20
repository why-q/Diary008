/// Experimental version 2 document: a version 1 envelope plus its epoch ledger.
///
/// Version 1 envelopes are unchanged and remain the default format for every
/// existing store; nothing here is read or written by them. A version 2
/// document is created only by a caller that explicitly asks for it, and it is
/// rejected by the version 1 decoder, so the two formats can never be confused.
///
/// The ledger is not decoration. A V2 document asserts two things that a V1
/// document cannot: which epochs this notebook has ever been issued, and that
/// the journal inside this document runs under the newest of them. Both are
/// checked on construction and on decode. A V2 document whose history is
/// missing, malformed, empty, duplicated, or out of step with its journal is
/// refused rather than repaired, so an existing notebook is never given an
/// invented history.
///
/// Replacement is append-only: [advance] carries the stored ledger verbatim
/// unless a caller supplies a longer one that keeps every earlier epoch in
/// order, and it never allows the journal epoch to move without the ledger
/// recording that epoch first. That single rule is what stops an ordinary
/// write from dropping history.
library;

import 'dart:convert';

import '../notebook.dart';
import 'epoch_history.dart';
import 'journal.dart';
import 'journal_values.dart';
import 'notebook_envelope.dart';

/// Protocol revision of the V2 document understood by this build.
const int epochEnvelopeSchemaVersion = 2;

/// Document discriminator, distinct from the V1 envelope's.
const String epochEnvelopeFormatName = 'diary008.notebook-envelope.v2';

/// One version 1 envelope plus the ledger of every epoch issued to its notebook.
final class EpochHistoryEnvelope {
  EpochHistoryEnvelope({required this.envelope, required this.history}) {
    if (history.notebookId != envelope.journal.notebookId) {
      throw const EnvelopeFormatException(
        'epoch history belongs to another notebook',
        field: 'history.notebookId',
      );
    }
    if (history.latest != envelope.journal.epochId) {
      // The ledger must prove the epoch the journal actually runs under; a
      // ledger that stops earlier, or has advanced further, cannot.
      throw const EnvelopeFormatException(
        'the journal epoch must be the newest epoch in the history',
        field: 'history.epochs',
      );
    }
  }

  final NotebookEnvelope envelope;
  final EpochHistory history;

  JournalScope get scope => envelope.scope;

  Map<String, Object?> toJson() => {
    'schemaVersion': epochEnvelopeSchemaVersion,
    'format': epochEnvelopeFormatName,
    'history': history.toJson(),
    'envelope': envelope.toJson(),
  };

  /// Stable encoding. Key order is fixed, so equal content encodes equally.
  String encode() => jsonEncode(toJson());

  bool hasSameContentAs(EpochHistoryEnvelope other) =>
      encode() == other.encode();

  /// Parses and fully validates a stored V2 document.
  static EpochHistoryEnvelope decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const EnvelopeFormatException('envelope is not valid JSON');
    }
    return fromJson(raw);
  }

  static EpochHistoryEnvelope fromJson(Object? value) {
    try {
      return _decode(value);
    } on EnvelopeFormatException {
      rethrow;
    } on JournalFormatException catch (error) {
      throw EnvelopeFormatException(error.message, field: error.field);
    } on FormatException {
      throw const EnvelopeFormatException('envelope is malformed');
    } catch (_) {
      // Never surface stored content in an error; messages name fields only.
      throw const EnvelopeFormatException('envelope is malformed');
    }
  }

  static EpochHistoryEnvelope _decode(Object? value) {
    final json = requireJsonObject(value, field: 'envelope');
    requireExactKeys(json, const {
      'schemaVersion',
      'format',
      'history',
      'envelope',
    }, field: 'envelope');
    final version = json['schemaVersion'];
    if (version is! int) {
      throw const EnvelopeFormatException(
        'schemaVersion must be an integer',
        field: 'envelope.schemaVersion',
      );
    }
    if (version != epochEnvelopeSchemaVersion) {
      throw EnvelopeFormatException(
        'unsupported envelope schema version $version',
        field: 'envelope.schemaVersion',
      );
    }
    if (json['format'] != epochEnvelopeFormatName) {
      throw const EnvelopeFormatException(
        'envelope format discriminator is missing or wrong',
        field: 'envelope.format',
      );
    }
    return EpochHistoryEnvelope(
      envelope: NotebookEnvelope.fromJson(json['envelope']),
      history: EpochHistory.fromJson(json['history']),
    );
  }

  /// The document a replacement would store, or a refusal.
  ///
  /// [history] is omitted for an ordinary write, which carries the stored
  /// ledger verbatim. It is supplied only when the caller is adopting a fresh
  /// epoch, and then it must be an append-only extension of this ledger, so no
  /// earlier epoch can be dropped, replaced, or reordered.
  EpochHistoryEnvelope advance({
    required int revision,
    required Notebook notebook,
    required Journal journal,
    EpochHistory? history,
  }) {
    final nextHistory = history ?? this.history;
    if (!nextHistory.isAppendOnlyExtensionOf(this.history)) {
      throw const EnvelopeFormatException(
        'a replacement must keep every previously recorded epoch in order',
        field: 'history.epochs',
      );
    }
    return EpochHistoryEnvelope(
      envelope: NotebookEnvelope(
        revision: revision,
        notebook: notebook,
        journal: journal,
      ),
      history: nextHistory,
    );
  }
}
