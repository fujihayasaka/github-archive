import {useQuery, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'

export interface SastData {
  countOpenAlerts: number
  cwes: string[]
  name: string
  ruleSarifId: string
  severity: string
}

interface SastResult {
  data: SastData[]
}

export interface UseSastQueryParams {
  query: string
  startDate: string
  endDate: string
}

export default function useSastQuery({query, startDate, endDate}: UseSastQueryParams): UseQueryResult<SastResult> {
  const paths = usePaths()
  const path = paths.sastPath({
    query,
    startDate,
    endDate,
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
