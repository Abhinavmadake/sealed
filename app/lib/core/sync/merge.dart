class MergeResult {
  MergeResult(this.merged, this.conflicts);

  final Map<String, dynamic> merged;
  final List<String> conflicts;

  bool get clean => conflicts.isEmpty;
}

/// Field-level three-way merge. A field changed on only one side takes that side's value;
/// a field changed differently on both sides is a conflict and keeps the local value for now.
MergeResult threeWayMerge(
  Map<String, dynamic>? base,
  Map<String, dynamic> mine,
  Map<String, dynamic> theirs, {
  List<String> fields = const [],
  String modifiedField = 'modified',
}) {
  final merged = <String, dynamic>{...theirs, ...mine};
  final conflicts = <String>[];
  final keys = {...fields, ...mine.keys, ...theirs.keys}..remove(modifiedField);
  for (final key in keys) {
    final m = mine[key];
    final t = theirs[key];
    final b = base?[key];
    if (m == t) {
      merged[key] = m;
    } else if (base != null && m == b) {
      merged[key] = t;
    } else if (base != null && t == b) {
      merged[key] = m;
    } else {
      merged[key] = m;
      conflicts.add(key);
    }
  }
  final stamps = [mine[modifiedField], theirs[modifiedField]].whereType<String>().toList()..sort();
  if (stamps.isNotEmpty) merged[modifiedField] = stamps.last;
  return MergeResult(merged, conflicts);
}
