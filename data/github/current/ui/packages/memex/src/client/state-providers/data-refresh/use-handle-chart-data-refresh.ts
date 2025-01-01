import {useQueryClient} from '@tanstack/react-query'
import {useCallback} from 'react'

import {chartSeriesQueryKey} from '../charts/query-keys'

export const useHandleChartDataRefresh = () => {
  const queryClient = useQueryClient()

  const handleRefresh = useCallback(() => {
    queryClient.invalidateQueries({queryKey: ['memex', chartSeriesQueryKey]})
  }, [queryClient])

  return {handleRefresh}
}
