// Returns the canonical greek-letter/color name for a corpus.
export function corpusDisplayName(corpus) {
  return `${corpus.cluster_name}/${corpus.corpus_name.toLowerCase()}`;
}

// Capitalizes all words in a string, replacing underscores with spaces. Intended for displaying text to humans.
export function titleize(str) {
  return str
    .replace(/_/g, " ")
    .toLowerCase()
    .split(" ")
    .map(function (word) {
      return word.charAt(0).toUpperCase() + word.slice(1);
    })
    .join(" ");
}

export function friendlyEpochMode(epochMode) {
  if (epochMode.startsWith("EMBEDDINGS_GRAPH")) {
    return titleize(epochMode.replace("EMBEDDINGS_GRAPH", "TEXT3_EMBEDDINGS"));
  }
  if (epochMode.startsWith("HYBRID_GRAPH")) {
    return titleize(epochMode.replace("HYBRID_GRAPH", "HYBRID_TEXT3_LEXICAL"));
  }
  return titleize(epochMode);
}
