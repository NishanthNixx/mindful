/// Turns text into a vector for local retrieval.
abstract interface class Embedder {
  int get dimensions;

  Future<List<double>> embed(String text);
}
