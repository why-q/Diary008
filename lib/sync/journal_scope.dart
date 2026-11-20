/// Scope of one notebook epoch for a sync exchange request.
///
/// A scope is explicit data. It is never inferred from entry text, entry
/// identifiers, volume ordinals, or arrival order. Both identifiers use the
/// same opaque-token rules as the journal protocol, so a request can only
/// address a scope that protocol could have produced.
library;

import '../journal/journal_operation.dart';
import '../journal/journal_values.dart';

/// The `(notebookId, epochId)` pair one exchange request is limited to.
class JournalScope {
  JournalScope({required String notebookId, required String epochId})
    : notebookId = requireOpaqueId(notebookId, field: 'notebookId'),
      epochId = requireOpaqueId(epochId, field: 'epochId');

  final String notebookId;
  final String epochId;

  /// Whether [operation] claims exactly this notebook and epoch.
  bool contains(JournalOperation operation) =>
      operation.notebookId == notebookId && operation.epochId == epochId;

  @override
  bool operator ==(Object other) =>
      other is JournalScope &&
      other.notebookId == notebookId &&
      other.epochId == epochId;

  @override
  int get hashCode => Object.hash(notebookId, epochId);

  @override
  String toString() => 'JournalScope($notebookId/$epochId)';
}
