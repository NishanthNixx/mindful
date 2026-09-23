import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Timeline filter. Every field is optional; an empty filter matches all.
@immutable
class EntryFilter {
  const EntryFilter({
    this.from,
    this.to,
    this.minMood,
    this.maxMood,
    this.tags = const {},
  });

  /// Inclusive lower bound.
  final DateTime? from;

  /// Exclusive upper bound.
  final DateTime? to;
  final int? minMood;
  final int? maxMood;

  /// Entry must carry at least one of these symptom/medication names.
  final Set<String> tags;

  bool get isEmpty =>
      from == null &&
      to == null &&
      minMood == null &&
      maxMood == null &&
      tags.isEmpty;

  EntryFilter copyWith({
    DateTime? Function()? from,
    DateTime? Function()? to,
    int? Function()? minMood,
    int? Function()? maxMood,
    Set<String>? tags,
  }) {
    return EntryFilter(
      from: from != null ? from() : this.from,
      to: to != null ? to() : this.to,
      minMood: minMood != null ? minMood() : this.minMood,
      maxMood: maxMood != null ? maxMood() : this.maxMood,
      tags: tags ?? this.tags,
    );
  }

  static const _setEq = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is EntryFilter &&
      other.from == from &&
      other.to == to &&
      other.minMood == minMood &&
      other.maxMood == maxMood &&
      _setEq.equals(other.tags, tags);

  @override
  int get hashCode =>
      Object.hash(from, to, minMood, maxMood, _setEq.hash(tags));
}
