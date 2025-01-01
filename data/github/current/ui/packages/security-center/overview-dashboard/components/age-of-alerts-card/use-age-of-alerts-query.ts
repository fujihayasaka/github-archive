import {useQueries, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'
import {calculateTrend} from '../../../common/utils/trend-data'
import {getQueriesByFilterValue} from '../../utils/query-parser'

export interface AgeOfAlertsResult {
  count: number
  value: number
  alertCount: number
}

export interface UseAgeOfAlertsQueryParams {
  query: string
  startDate: string
  endDate: string
}

export type AgeOfAlertsData = {
  count: number
  isSuccess: boolean
  isPending: boolean
  isError: boolean
}

export function getTrend(currentPeriodData: AgeOfAlertsData, previousPeriodData: AgeOfAlertsData): number {
  if (currentPeriodData.isSuccess && previousPeriodData.isSuccess) {
    return calculateTrend(currentPeriodData.count, previousPeriodData.count)
  }
  return 0
}

export function resultsReducer(queries: Array<UseQueryResult<AgeOfAlertsResult>>): AgeOfAlertsData {
  const isSuccess = queries.every(query => query.isSuccess)
  const isPending = queries.some(query => query.isPending)
  const isError = queries.some(query => query.isError)

  if (!isSuccess) {
    return {count: 0, isSuccess, isPending, isError}
  }

  const results = queries.map(query => query.data)

  const totalAge = results.reduce((acc, result) => acc + result.value * result.alertCount, 0)
  const alertCount = results.reduce((acc, result) => acc + result.alertCount, 0)
  const totalCount = alertCount === 0 ? 0 : Math.round(totalAge / alertCount)

  return {count: totalCount, isSuccess, isPending, isError}
}

export function useAgeOfAlertsQuery({query, startDate, endDate}: UseAgeOfAlertsQueryParams): AgeOfAlertsData {
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
      const path = paths.ageOfAlertsPath({
        startDate,
        endDate,
        ...params,
      })

      return {
        queryKey: [path, endDate],
        queryFn: (): Promise<AgeOfAlertsResult> => {
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
