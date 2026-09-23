enum TagKind { symptom, medication }

/// A reusable symptom or medication label, with how often it has been used.
class TagUsage {
  const TagUsage({required this.name, required this.kind, required this.count});

  final String name;
  final TagKind kind;
  final int count;
}
