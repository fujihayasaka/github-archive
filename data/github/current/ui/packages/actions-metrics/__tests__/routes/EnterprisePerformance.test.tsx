import {act, screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PerformanceTestUtils} from '../test-utils/views/performance/test-utils'
import {MockDataService} from '../test-utils/common/services/data-service.mock'
import {Services} from '../../common/services/services'
import {registerServices} from '../../common/services/service-registrations'
import type {IMetricsService} from '../../common/services/metrics-service'
import {TestUtils} from '../test-utils/utils/test-utils'
import {ScopeType} from '../../common/models/enums'
import {EnterprisePerformance} from '../../routes/EnterprisePerformance'

jest.setTimeout(5_000)

describe('Actions Metrics Enterprise Performance', () => {
  beforeAll(() => {
    registerServices()
    PerformanceTestUtils.registerDataServiceMock()
  })
  it('only tries to fetch twice (performance data + cards data)', async () => {
    const fetchSpy = jest.spyOn(MockDataService.prototype, 'verifiedFetchJSONWrapper')

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(() => {
      render(<EnterprisePerformance />, {routePayload: TestUtils.getMockPayload(ScopeType.Enterprise)})
    })

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledTimes(2)
    })
  })
  it('renders items in table', async () => {
    render(<EnterprisePerformance />, {routePayload: TestUtils.getMockPayload(ScopeType.Enterprise)})

    await waitFor(() => {
      expect(screen.getByText('org-1/repository-1')).toBeInTheDocument()
    })
  })
  it('renders correct # of items', async () => {
    render(<EnterprisePerformance />, {routePayload: TestUtils.getMockPayload(ScopeType.Enterprise)})
    const orgPerformanceService = Services.get<IMetricsService>('IMetricsService')

    const pageSize = orgPerformanceService.getMetricsView().value.virtualPageSize
    await waitFor(() => {
      expect(screen.getAllByText('repository-', {exact: false})).toHaveLength(pageSize)
    })
  })
})
