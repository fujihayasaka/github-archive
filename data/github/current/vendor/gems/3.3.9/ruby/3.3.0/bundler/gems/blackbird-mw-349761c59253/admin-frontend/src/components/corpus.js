export const EpochMode = {
  LegacyHybrid: "LEGACY_HYBRID",
  Lexical: "LEXICAL",
  Embeddings: "EMBEDDINGS",
  EmbeddingsGraph: "EMBEDDINGS_GRAPH",
  Hybrid: "HYBRID"
}

// Returns the canonical greek-letter/color name for a corpus.
export function corpusDisplayName(corpus) {
  return `${corpus.cluster_name}/${corpus.corpus_name.toLowerCase()}`;
}
