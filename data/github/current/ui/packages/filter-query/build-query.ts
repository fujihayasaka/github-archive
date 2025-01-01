/**
 * Appends the given terms to the filter query.
 * @param query The base filter query string.
 * @param terms The new terms to append, in the form `{ key1: 'value', key2: ['value1', 'value2'] }
 * @returns The filter query with the new terms appended.
 */
export function appendToQuery(query: string, terms: Record<string, string | string[]>) {
  const formattedTerms = Object.entries(terms)
    .map(([key, val]) => {
      const values = Array.isArray(val) ? val : [val]
      return `${key}:${values.map(quoteIfIncludesWhitespace).join(',')}`
    })
    .join(' ')

  return [query, formattedTerms].filter(Boolean).join(' ')
}

function quoteIfIncludesWhitespace(value: string): string {
  return value.includes(' ') ? `"${value}"` : value
}
