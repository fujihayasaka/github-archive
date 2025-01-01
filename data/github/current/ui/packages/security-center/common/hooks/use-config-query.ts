import {
  type DefaultError,
  type QueriesResults,
  type QueryKey,
  type QueryOptions,
  useQueries as useTanstackQueries,
  useQuery as useTanstackQuery,
  type UseQueryResult,
} from '@github-ui/react-query'

const DEFAULT_QUERY_CONFIG = {
  retry: process.env.NODE_ENV !== 'test' ? 3 : 0,
  refetchOnWindowFocus: false,
  staleTime: 1000 * 60 * 5, // 5 minute stale time before cache invalidation
}

/**
 * Light wrapper around TanStack's useQuery that adds security center specific behaviors
 */
export function useQuery<
  TQueryFnData = unknown,
  TError = DefaultError,
  TData = TQueryFnData,
  TQueryKey extends QueryKey = QueryKey,
>(...args: Parameters<typeof useTanstackQuery<TQueryFnData, TError, TData, TQueryKey>>): UseQueryResult<TData, TError> {
  const [queryOptions, queryClient] = args
  // This is a valid query key but we first have to cast to unknown because although it is of type QueryKey,
  // TQueryKey narrows it down to the type of the given query key, which does not include the string prefix
  const queryKey = ['security-center', ...queryOptions.queryKey] as unknown as TQueryKey

  return useTanstackQuery<TQueryFnData, TError, TData, TQueryKey>(
    {
      ...DEFAULT_QUERY_CONFIG,
      ...queryOptions,
      queryKey,
    },
    queryClient,
  )
}

/**
 * Light wrapper around TanStack's useQueries that adds security center specific behaviors
 */
export function useQueries<T extends unknown[], TCombinedResult = QueriesResults<T>>(
  ...args: Parameters<typeof useTanstackQueries<T, TCombinedResult>>
): TCombinedResult {
  const [queriesOptions, queryClient] = args
  // We need to explicitly cast this type because from the docs it states
  // > The useQueries hook accepts an options object with a queries key whose value is an array with query option
  // > objects identical to the useQuery hook (excluding the context option).
  // Except the query type here allows for nesting T values which is very hard to narrow down
  const mappedQueriesWithKeys = queriesOptions.queries.map(queryOptions => {
    const queryKey = ['security-center', ...((queryOptions as QueryOptions).queryKey ?? [])]
    return {
      ...DEFAULT_QUERY_CONFIG,
      ...(queryOptions as QueryOptions),
      queryKey,
    }
  }) as unknown as (typeof queriesOptions)['queries']

  return useTanstackQueries<T, TCombinedResult>(
    {
      ...queriesOptions,
      queries: mappedQueriesWithKeys,
    },
    queryClient,
  )
}
