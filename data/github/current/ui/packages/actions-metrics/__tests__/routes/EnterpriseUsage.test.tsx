import {act, screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {UsageTestUtils} from '../test-utils/views/usage/test-utils'
import {MockDataService} from '../test-utils/common/services/data-service.mock'
import {Services} from '../../common/services/services'
import {registerServices} from '../../common/services/service-registrations'
import type {IMetricsService} from '../../common/services/metrics-service'
import {TestUtils} from '../test-utils/utils/test-utils'
import {ScopeType} from '../../common/models/enums'
import {EnterpriseUsage} from '../../routes/EnterpriseUsage'

jest.setTimeout(5_000)

describe('Actions Metrics Enterprise Usage', () => {
  beforeAll(() => {
    registerServices()
    UsageTestUtils.registerDataServiceMock()
  })
  it('only tries to fetch twice (usage data + cards data)', async () => {
    const fetchSpy = jest.spyOn(MockDataService.prototype, 'verifiedFetchJSONWrapper')

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(() => {
      render(<EnterpriseUsage />, {routePayload: TestUtils.getMockPayload(ScopeType.Enterprise)})
    })

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledTimes(2)
    })
  })
  it('renders items in table', async () => {
    render(<EnterpriseUsage />, {routePayload: TestUtils.getMockPayload(ScopeType.Enterprise)})

    await waitFor(() => {
      expect(screen.getByText('org-1/repository-1')).toBeInTheDocument()
    })
  })
  it('renders correct # of items', async () => {
    render(<EnterpriseUsage />, {routePayload: TestUtils.getMockPayload(ScopeType.Enterprise)})
    const orgUsageService = Services.get<IMetricsService>('IMetricsService')

    const pageSize = orgUsageService.getMetricsView().value.virtualPageSize
    await waitFor(() => {
      expect(screen.getAllByText('repository-', {exact: false})).toHaveLength(pageSize)
    })
  })
})
