import {useQueries, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'
import {getQueriesByFilterValue} from '../../utils/query-parser'
import type {AlertActivityChartData, AlertActivityData, AlertActivityResult} from './fetch-types'

export interface UseAlertActivityQueryParams {
  query: string
  startDate: string
  endDate: string
}

export function getAlertActivityData(fetchData: Array<UseQueryResult<AlertActivityResult>>): AlertActivityData {
  const isSuccess = fetchData.every(result => result.isSuccess)
  if (isSuccess) {
    // Iterate over each result and accumulate it in perToolData array of type AlertActivityChartData
    // Each result json will contain same array of elements
    // {date: 'Sep 25', endDate: 'Sep 28', closed: 0, opened: 0}
    // So we need to combine the dates into 1 array and sum the closed and open values

    // Combine fetchData's sub-arrays into 1 array
    const allToolsData = fetchData.flatMap(r => r.data.data)

    // We may have multiple entries with the same date because of results from different feature queries.
    // Accumulate into a separate array, and combine any duplicates:
    const combinedData = allToolsData.reduce((acc: AlertActivityChartData[], cur: AlertActivityChartData) => {
      const date = cur.date
      const existing = acc.find(d => d.date === date)
      if (existing) {
        existing.closed += cur.closed
        existing.opened += cur.opened
      } else {
        // Set up a new element, which will also contain endDate
        acc.push({...cur})
      }
      return acc
    }, [])

    // Sum all closed and open values, and if the sum is 0, then set no data to true.
    const sumClosed = combinedData.reduce((acc: number, cur: AlertActivityChartData) => acc + cur.closed, 0)
    const sumOpened = combinedData.reduce((acc: number, cur: AlertActivityChartData) => acc + cur.opened, 0)
    const sum = sumClosed + sumOpened

    return {data: combinedData, sum}
  }
  return {data: [], sum: 0}
}

export function useAlertActivityQuery({
  query,
  startDate,
  endDate,
}: UseAlertActivityQueryParams): Array<UseQueryResult<AlertActivityResult>> {
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
      const path = paths.alertActivityPath({
        startDate,
        endDate,
        ...params,
      })

      return {
        queryKey: [path, endDate],
        queryFn: (): Promise<AlertActivityResult> => {
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
