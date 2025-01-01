import {useEffect, useState} from 'react'

export function useDebouncedFilterQuery<T>(query: T | null) {
  const [debouncedQuery, setDebouncedQuery] = useState<T | null>(null)

  // When the query changes to or from null, update immediately so we show or hide the menu responsively
  if ((debouncedQuery === null && query !== null) || (debouncedQuery !== null && query === null))
    setDebouncedQuery(query)

  // Otherwise update after typing ends (will be a noop if the previous call already updated the value)
  useEffect(() => {
    const timeout = setTimeout(() => setDebouncedQuery(query), 200)
    return () => clearTimeout(timeout)
  }, [query])

  return debouncedQuery
}
