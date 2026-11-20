/// Append-only record of the epochs a notebook's documents have used.
///
/// The journal protocol binds every operation to a `(notebookId, epochId)`
/// pair, but a [Journal] only ever sees the epoch in front of it. A ledger is
/// an ordered list of opaque identifiers that remembers the epochs already
/// seen, with no timestamps, no counters, no derived dates, and no diary
/// content.
///
/// It records epochs that were *written*, not epochs proven to have been
/// *issued*. Issuance proof needs a barrier check in front of the write, which
/// no shipped path performs, so `contains` is not by itself evidence that an
/// epoch was ever legitimately issued.
///
/// The order is the order in which the epochs were recorded. It is
/// significant, because the document is only ever allowed to grow by
/// appending: dropping, replacing, or reordering an epoch would silently
/// forget history that operations on disk still refer to.
/// [isAppendOnlyExtensionOf] is the check a writer must pass before a stored
/// ledger may be replaced.
///
/// This library is pure Dart: no `dart:io`, no Flutter, and no clock. It does
/// not decide whether an epoch is allowed to exist; it only records and
/// compares identifiers that a caller already chose.
library;

import 'dart:convert';

import 'journal_values.dart';

/// Protocol revision of the epoch ledger document understood by this build.
const int epochHistorySchemaVersion = 1;

/// Document discriminator, so a ledger is never mistaken for a journal or an
/// envelope.
const String epochHistoryFormatName = 'diary008.epoch-history';

/// One notebook's immutable, ordered set of issued epochs.
///
/// Construction rejects an empty list, a duplicate identifier, and any
/// identifier that the journal protocol would refuse, so a ledger can never
/// hold an epoch that no operation could legitimately carry. The initial epoch
/// is supplied explicitly; nothing here infers one from a notebook, a
/// timestamp, or the current journal.
final class EpochHistory {
  EpochHistory({required this.notebookId, required List<String> epochs})
    : epochs = List.unmodifiable(epochs) {
    _requireValidNotebook(notebookId);
    if (epochs.isEmpty) {
      throw const JournalFormatException(
        'an epoch history must record at least one epoch',
        field: 'epochHistory.epochs',
      );
    }
    final seen = <String>{};
    for (final epochId in epochs) {
      _requireValidEpoch(epochId);
      if (!seen.add(epochId)) {
        throw const JournalFormatException(
          'epoch identifiers must be unique; an epoch cannot be issued twice',
          field: 'epochHistory.epochs',
        );
      }
    }
  }

  /// A ledger that starts with one explicitly chosen initial epoch.
  factory EpochHistory.start({
    required String notebookId,
    required String initialEpochId,
  }) => EpochHistory(notebookId: notebookId, epochs: [initialEpochId]);

  /// Builds a ledger from a stored document, rejecting unknown versions.
  factory EpochHistory.fromJson(Object? value) {
    final json = requireJsonObject(value, field: 'epochHistory');
    requireExactKeys(json, const {
      'schemaVersion',
      'format',
      'notebookId',
      'epochs',
    }, field: 'epochHistory');
    final version = json['schemaVersion'];
    if (version is! int) {
      throw const JournalFormatException(
        'schemaVersion must be an integer',
        field: 'epochHistory.schemaVersion',
      );
    }
    if (version != epochHistorySchemaVersion) {
      throw JournalFormatException(
        'unsupported epoch history schema version $version',
        field: 'epochHistory.schemaVersion',
      );
    }
    if (json['format'] != epochHistoryFormatName) {
      throw const JournalFormatException(
        'epoch history format discriminator is missing or wrong',
        field: 'epochHistory.format',
      );
    }
    final stored = json['epochs'];
    if (stored is! List) {
      throw const JournalFormatException(
        'epochs must be a list',
        field: 'epochHistory.epochs',
      );
    }
    return EpochHistory(
      notebookId: requireOpaqueId(json['notebookId'], field: 'notebookId'),
      epochs: [
        for (final value in stored)
          if (value is String)
            value
          else
            // The stored value is content, so it is never echoed back.
            throw const JournalFormatException(
              'epoch identifiers must be strings',
              field: 'epochHistory.epochs',
            ),
      ],
    );
  }

  final String notebookId;

  /// Issued epochs in issuance order; the last one is the current epoch.
  final List<String> epochs;

  int get length => epochs.length;

  /// The newest recorded epoch, which is the one a journal may run under.
  String get latest => epochs.last;

  bool contains(String epochId) => epochs.contains(epochId);

  /// Appends [epochId] and returns a new ledger.
  ///
  /// The receiver is left untouched, so a refused or abandoned write cannot
  /// disturb the ledger a caller is still holding.
  EpochHistory append(String epochId) {
    _requireValidEpoch(epochId);
    if (contains(epochId)) {
      throw const JournalFormatException(
        'epoch identifier was already recorded; an epoch cannot be reused',
        field: 'epochHistory.epochs',
      );
    }
    return EpochHistory(notebookId: notebookId, epochs: [...epochs, epochId]);
  }

  /// Whether this ledger keeps every epoch of [prior] in the same order.
  ///
  /// A ledger for another notebook, a shorter ledger, a replaced epoch, and a
  /// reordered ledger are all refused. This is the only permitted relationship
  /// between a stored ledger and its replacement.
  bool isAppendOnlyExtensionOf(EpochHistory prior) {
    if (prior.notebookId != notebookId) return false;
    if (epochs.length < prior.epochs.length) return false;
    for (var index = 0; index < prior.epochs.length; index++) {
      if (epochs[index] != prior.epochs[index]) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': epochHistorySchemaVersion,
    'format': epochHistoryFormatName,
    'notebookId': notebookId,
    'epochs': epochs,
  };

  /// Stable encoding. Key order is fixed, so equal content encodes equally.
  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is EpochHistory &&
      other.notebookId == notebookId &&
      other.encode() == encode();

  @override
  int get hashCode => Object.hash(notebookId, encode());

  @override
  String toString() => 'EpochHistory($notebookId, ${epochs.length} epochs)';
}

void _requireValidNotebook(String notebookId) =>
    requireOpaqueId(notebookId, field: 'notebookId');

void _requireValidEpoch(String epochId) =>
    requireOpaqueId(epochId, field: 'epochId');
