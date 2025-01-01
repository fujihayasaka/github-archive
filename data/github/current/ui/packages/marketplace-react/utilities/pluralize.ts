export function pluralize(word: string, count: number, plural?: string) {
  if (count !== 1) {
    return plural ? plural : `${word}s`
  }
  return word
}
