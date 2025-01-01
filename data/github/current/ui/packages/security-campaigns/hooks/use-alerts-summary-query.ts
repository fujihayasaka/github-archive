import {useQuery, type UndefinedInitialDataOptions, type UseQueryResult} from '@github-ui/react-query'
import type {Repository} from '../types/repository'
import {fetchJson} from '../utils/fetch-json'

interface UseAlertsSummaryQueryParams {
  query?: string
}

export type AlertsSummaryResponseItem = {
  repository: Repository
  alertCount: number
  issuesEnabled?: boolean
}

export type AlertsSummaryResponse = {
  repositories: AlertsSummaryResponseItem[]
}

export function useAlertsSummaryQuery(
  path: string,
  params: UseAlertsSummaryQueryParams,
  options: Omit<UndefinedInitialDataOptions<AlertsSummaryResponse>, 'queryKey' | 'queryFn'> = {},
): UseQueryResult<AlertsSummaryResponse> {
  return useQuery({
    queryKey: ['alerts-summary', path, params],
    queryFn: () => {
      const url = new URL(path, window.location.origin)
      url.searchParams.set('query', params.query ?? '')
      // Do not include the hostname since we're always on the same domain
      return fetchJson<AlertsSummaryResponse>(`${url.pathname}?${url.searchParams.toString()}`)
    },
    ...options,
  })
}
