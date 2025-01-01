import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'

export interface Repository {
  id: number
  repository: string
  ownerType: string
  total: number
  critical: number
  high: number
  medium: number
  low: number
  url: string
}

interface RepositoriesResult {
  repositories: Repository[]
}

export interface UseRepositoriesQueryParams {
  query: string
  startDate: string
  endDate: string
}

export default function useRepositoriesQuery({
  query,
  startDate,
  endDate,
}: UseRepositoriesQueryParams): UseQueryResult<RepositoriesResult> {
  const paths = usePaths()
  const path = paths.repositoriesPath({
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
