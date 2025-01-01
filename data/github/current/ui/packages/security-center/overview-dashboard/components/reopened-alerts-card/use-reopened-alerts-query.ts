import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQueries} from '../../../common/hooks/use-config-query'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'
import {calculateTrend} from '../../../common/utils/trend-data'
import {getQueriesByFilterValue} from '../../utils/query-parser'

export interface ReopenedAlertsResult {
  count: number
}

export interface UseReopenedAlertsQueryParams {
  query: string
  startDate: string
  endDate: string
}

export type ReopenedAlertsData = {
  count: number
  isSuccess: boolean
  isPending: boolean
  isError: boolean
}

export function getTrend(currentPeriodData: ReopenedAlertsData, previousPeriodData: ReopenedAlertsData): number {
  if (currentPeriodData.isSuccess && previousPeriodData.isSuccess) {
    return calculateTrend(currentPeriodData.count, previousPeriodData.count)
  }
  return 0
}

export function resultsReducer(queries: Array<UseQueryResult<ReopenedAlertsResult>>): ReopenedAlertsData {
  const isSuccess = queries.every(query => query.isSuccess)
  const isPending = queries.some(query => query.isPending)
  const isError = queries.some(query => query.isError)

  if (!isSuccess) {
    return {count: 0, isSuccess, isPending, isError}
  }

  const results = queries.map(query => query.data)
  const totalCount = results.reduce((acc, result) => acc + result.count, 0)

  return {count: totalCount, isSuccess, isPending, isError}
}

export function useReopenedAlertsQuery({query, startDate, endDate}: UseReopenedAlertsQueryParams): ReopenedAlertsData {
  const sliceParams = []
  // parallelize by tool
  const perToolQueries = getQueriesByFilterValue(query, 'tool', [
    'secret-scanning',
    'dependabot',
    'codeql',
    'third-party',
  ])
  for (const perToolQuery of perToolQueries) {
    sliceParams.push({query: perToolQuery})
  }

  const paths = usePaths()

  const dataQueries = useQueries({
    queries: sliceParams.map(params => {
      const path = paths.reopenedAlertsPath({
        startDate,
        endDate,
        ...params,
      })

      return {
        queryKey: [path, endDate],
        queryFn: (): Promise<ReopenedAlertsResult> => {
          if (dateIsMoreThanTwoYearsAgo(endDate)) {
            return Promise.reject(new Error('Data is only available for the last 2 years'))
          }

          return fetchJson(path)
        },
      }
    }),
  })

  return resultsReducer(dataQueries)
}
