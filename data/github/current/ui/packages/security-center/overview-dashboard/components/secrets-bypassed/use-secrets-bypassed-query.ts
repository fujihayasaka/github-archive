import {useQuery, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'

export interface UseSecretsBypassedQueryParams {
  query: string
  startDate: string
  endDate: string
}

export interface CountsResponse {
  totalBlocksCount: number
  successfulBlocksCount: number
  bypassedAlertsCount: number
}

export interface NoDataResponse {
  noData: string
}

export type SecretsBypassedResponse = NoDataResponse | CountsResponse

export default function useSecretsBypassedQuery({
  query,
  startDate,
  endDate,
}: UseSecretsBypassedQueryParams): UseQueryResult<SecretsBypassedResponse> {
  const paths = usePaths()
  const path = paths.secretsBypassedPath({
    startDate,
    endDate,
    query,
  })

  return useQuery({
    queryKey: [path, endDate],
    queryFn: () => {
      if (dateIsMoreThanTwoYearsAgo(endDate)) {
        return Promise.reject(new Error('Data is only available for the last 2 years'))
      }

      return fetchJson(path)
    },
  })
}
