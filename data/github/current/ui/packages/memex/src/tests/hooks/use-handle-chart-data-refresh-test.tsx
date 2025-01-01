import {act, renderHook} from '@testing-library/react'

import {useEnabledFeatures} from '../../client/hooks/use-enabled-features'
import {chartSeriesQueryKey} from '../../client/state-providers/charts/query-keys'
import {useHandleChartDataRefresh} from '../../client/state-providers/data-refresh/use-handle-chart-data-refresh'
import {asMockHook} from '../mocks/stub-utilities'
import {createTestQueryClient} from '../test-app-wrapper'
import {createWrapperWithContexts} from '../wrapper-utils'

jest.mock('../../client/state-providers/memex-items/queries/use-paginated-memex-items-query')
jest.mock('../../client/hooks/use-enabled-features')

describe('useHandleChartDataRefresh', () => {
  beforeEach(() => {
    asMockHook(useEnabledFeatures).mockReturnValue({memex_table_without_limits: true})
  })

  it('should invalidate chart queries', () => {
    const queryClient = createTestQueryClient()
    const spy = jest.spyOn(queryClient, 'invalidateQueries')

    const {result} = renderHook(() => useHandleChartDataRefresh(), {
      wrapper: createWrapperWithContexts({
        QueryClient: {
          queryClient,
        },
      }),
    })

    act(() => {
      result.current.handleRefresh()
    })

    expect(spy).toHaveBeenCalledTimes(1)
    expect(spy).toHaveBeenCalledWith({queryKey: ['memex', chartSeriesQueryKey]})
  })
})
