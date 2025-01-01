import type {QueryKey, QueryClient} from '@github-ui/react-query'
import {reportTraceData} from '@github-ui/internal-api-insights'
import {
  AuthSessionExpiredError,
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

const UNAUTHORIZED_STATUS_CODE = 401

// This is a wrapper around reactFetch that reports trace data and correctly handles SSO expiration states.
export async function fetchWithTracing<TQueryFnData = unknown, TQueryKey extends QueryKey = QueryKey>(
  apiURL: string,
  queryKey: TQueryKey,
  queryClient: QueryClient,
): Promise<TQueryFnData> {
  const response = await fetchWithErrorHandling(apiURL)

  if (response.status === UNAUTHORIZED_STATUS_CODE) {
    const previousData = queryClient.getQueryData<TQueryFnData>(queryKey)
    if (!previousData) throw new AuthSessionExpiredError()
    // When a user's SSO session expired, try to return the previous data rather than throwing an error to maintain parity with the Rails experience.
    return previousData
  }

  const json = await parseJSONWithBetterErrors(response)
  reportTraceData(json)
  throwErrorsIfBadResponse(response)
  return json
}
