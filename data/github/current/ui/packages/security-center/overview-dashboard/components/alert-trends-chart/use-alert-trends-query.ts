import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQueries} from '../../../common/hooks/use-config-query'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'
import {getQueriesByFilterValue} from '../../utils/query-parser'
import type {GroupingType} from './grouping-type'

export interface AlertTrend {
  x: string
  y: number
}

export interface AlertTrendsResult {
  alertTrends: {[key: string]: AlertTrend[]}
}

export type AlertTrendsData = Map<string, AlertTrend[]>

export interface UseAlertTrendsQueryParams {
  query: string
  startDate: string
  endDate: string
  grouping: GroupingType
  alertState: 'open' | 'closed'
}

export interface SliceQueryParams {
  slice: string
  query: string
}

export function getTotalAlertCountData(periodData: Array<UseQueryResult<AlertTrendsResult>>): number | undefined {
  const isSuccess = periodData.every(result => result.isSuccess)

  if (isSuccess) {
    const toolData = periodData.map(result => result.data.alertTrends)
    const values = toolData.flatMap(data => Object.values(data))
    return values.reduce((sum: number, trend: AlertTrend[]) => {
      const lastDataPoint = trend[trend.length - 1]
      if (!lastDataPoint) return sum + 0

      return sum + lastDataPoint.y
    }, 0)
  } else {
    return 0
  }
}

export function getAlertTrendsData(periodData: Array<UseQueryResult<AlertTrendsResult>>): AlertTrendsData {
  const isSuccess = periodData.every(result => result.isSuccess)

  const alertTrends = new Map<string, AlertTrend[]>()
  if (isSuccess) {
    const toolData = periodData.map(result => result.data.alertTrends)
    for (const tool of toolData) {
      for (const [name, dataPoints] of Object.entries(tool)) {
        if (!alertTrends.has(name)) {
          alertTrends.set(name, [])
        }

        for (const dataPoint of dataPoints) {
          const existingDataPoint = alertTrends.get(name)?.find(alertTrend => alertTrend.x === dataPoint.x)
          if (existingDataPoint) {
            existingDataPoint.y += dataPoint.y
          } else {
            alertTrends.get(name)?.push({...dataPoint})
          }
        }
      }
    }
  }
  return alertTrends
}

export function useAlertTrendsQuery({
  query,
  startDate,
  endDate,
  grouping,
  alertState,
}: UseAlertTrendsQueryParams): Array<UseQueryResult<AlertTrendsResult>> {
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
      const path = paths.alertTrendsPath({
        startDate,
        endDate,
        grouping,
        alertState,
        ...params,
      })

      return {
        queryKey: [path, endDate],
        queryFn: (): Promise<AlertTrendsResult> => {
          if (dateIsMoreThanTwoYearsAgo(endDate)) {
            return Promise.reject(new Error('Data is only available for the last 2 years'))
          }

          return fetchJson(path)
        },
      }
    }),
  })

  return dataQueries
}
