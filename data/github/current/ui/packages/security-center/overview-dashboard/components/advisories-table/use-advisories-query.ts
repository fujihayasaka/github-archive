import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'

export interface Advisory {
  summary: string
  cveId: string | undefined
  ghsaId: string
  ecosystem: string
  openAlerts: number
  severity: string
}

interface AdvisoriesResult {
  advisories: Advisory[]
}

export interface UseAdvisoriesQueryParams {
  query: string
  startDate: string
  endDate: string
}

export default function useAdvisoriesQuery({
  query,
  startDate,
  endDate,
}: UseAdvisoriesQueryParams): UseQueryResult<AdvisoriesResult> {
  const paths = usePaths()
  const path = paths.advisoriesPath({
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
