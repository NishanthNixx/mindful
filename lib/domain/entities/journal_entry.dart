import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// A single journal entry. Pure domain object — no persistence concerns.
@immutable
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.createdAt,
    required this.mood,
    this.sleepHours,
    this.note = '',
    this.symptoms = const [],
    this.medications = const [],
    this.fromVoice = false,
  }) : assert(mood >= minMood && mood <= maxMood, 'mood must be 1-5');

  static const int minMood = 1;
  static const maxMood = 5;

  final String id;
  final DateTime createdAt;

  /// 1 (very low) to 5 (very good).
  final int mood;
  final double? sleepHours;
  final String note;
  final List<String> symptoms;
  final List<String> medications;

  /// True when the note started as an on-device speech transcript.
  final bool fromVoice;

  JournalEntry copyWith({
    DateTime? createdAt,
    int? mood,
    double? Function()? sleepHours,
    String? note,
    List<String>? symptoms,
    List<String>? medications,
    bool? fromVoice,
  }) {
    return JournalEntry(
      id: id,
      createdAt: createdAt ?? this.createdAt,
      mood: mood ?? this.mood,
      sleepHours: sleepHours != null ? sleepHours() : this.sleepHours,
      note: note ?? this.note,
      symptoms: symptoms ?? this.symptoms,
      medications: medications ?? this.medications,
      fromVoice: fromVoice ?? this.fromVoice,
    );
  }

  static const _listEq = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is JournalEntry &&
      other.id == id &&
      other.createdAt == createdAt &&
      other.mood == mood &&
      other.sleepHours == sleepHours &&
      other.note == note &&
      _listEq.equals(other.symptoms, symptoms) &&
      _listEq.equals(other.medications, medications) &&
      other.fromVoice == fromVoice;

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    mood,
    sleepHours,
    note,
    _listEq.hash(symptoms),
    _listEq.hash(medications),
    fromVoice,
  );
}
