import {useQuery, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {dateIsMoreThanTwoYearsAgo} from '../../../common/utils/date-period'
import {fetchJson} from '../../../common/utils/fetch-json'

export type PreventedAndIntroducedResult = Array<{
  label: string
  data: Array<{
    x: string
    y: number
  }>
}>

interface UsePreventedAndIntroducedChartDataParams {
  query: string
  startDate: string
  endDate: string
}

export function getTotalAlertCountData(result: UseQueryResult<PreventedAndIntroducedResult>): number {
  if (result.isSuccess) {
    if (result.data.length === 0) return 0
    const values = result.data.flatMap(series => series.data)
    return values.reduce((sum: number, currentValue: {x: string; y: number}) => {
      return sum + currentValue.y
    }, 0)
  } else {
    return 0
  }
}

export function usePreventedAndIntroducedChartData({
  query,
  startDate,
  endDate,
}: UsePreventedAndIntroducedChartDataParams): UseQueryResult<PreventedAndIntroducedResult> {
  const paths = usePaths()
  const path = paths.introducedAndPreventedPath({
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
