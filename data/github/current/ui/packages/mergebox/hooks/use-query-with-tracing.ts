import {
  useQuery,
  useSuspenseQuery,
  type DefaultError,
  type QueryKey,
  type UseQueryResult,
  type UseSuspenseQueryResult,
} from '@tanstack/react-query'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {reactFetch} from '@github-ui/verified-fetch'
import {reportTraceData} from '@github-ui/internal-api-insights'

const UNAUTHORIZED_STATUS_CODE = 401

async function fetchWithTracing<TQueryFnData = unknown, TQueryKey extends QueryKey = QueryKey>(
  apiURL: string,
  queryKey: TQueryKey,
): Promise<TQueryFnData> {
  const result = await reactFetch(apiURL)
  if (result.status === UNAUTHORIZED_STATUS_CODE) {
    const previousData = queryClient.getQueryData<TQueryFnData>(queryKey)
    if (!previousData) throw new Error(`HTTP ${result.status}: Unable to fetch data`)
    // When a user's SSO session expired, try to return the previous data rather than throwing an error to maintain parity with the Rails experience.
    return previousData
  }
  if (!result.ok) throw new Error(`HTTP ${result.status}`)
  const json = await result.json()
  reportTraceData(json)
  return json
}

/**
 * Light wrapper around TanStack's useQuery that adds tracing and error handling for expired SSO sessions
 * @param queryKey A reference for the query
 * @param apiURL The URL to fetch data from
 * @param throwOnError optional param to disable suspense's default behavior of throwing errors to the error boundary
 */
export function useQueryWithTracing<
  TQueryFnData = unknown,
  TError = DefaultError,
  TData = TQueryFnData,
  TQueryKey extends QueryKey = QueryKey,
>({
  queryKey,
  apiURL,
  throwOnError,
}: {
  queryKey: TQueryKey
  apiURL: string
  throwOnError: undefined | boolean
}): UseQueryResult<TData, TError> {
  return useQuery<TQueryFnData, TError, TData, TQueryKey>({
    queryKey,
    throwOnError,
    queryFn: async () => {
      return fetchWithTracing<TQueryFnData, TQueryKey>(apiURL, queryKey)
    },
  })
}

/**
 * Light wrapper around TanStack's useSuspenseQuery that adds tracing and error handling for expired SSO sessions.
 * @param queryKey A reference for the query
 * @param apiURL The URL to fetch data from
 */
export function useSuspenseQueryWithTracing<
  TQueryFnData = unknown,
  TError = DefaultError,
  TData = TQueryFnData,
  TQueryKey extends QueryKey = QueryKey,
>({queryKey, apiURL}: {queryKey: TQueryKey; apiURL: string}): UseSuspenseQueryResult<TData, TError> {
  return useSuspenseQuery<TQueryFnData, TError, TData, TQueryKey>({
    queryKey,
    queryFn: async () => {
      return fetchWithTracing<TQueryFnData, TQueryKey>(apiURL, queryKey)
    },
  })
}
