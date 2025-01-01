import {render} from '@github-ui/react-core/test-utils'
import {SeatBasedUsageContainer} from '../../components/usage/SeatBasedUsageContainer'
import {DEFAULT_FILTERS} from '../../test-utils/mock-data'
import {Products} from '../../constants'
import {screen} from '@testing-library/react'
import {mockClientEnv} from '@github-ui/client-env/mock'

describe('SeatBasedUsageContainer', () => {
  test('Renders the seat based products', async () => {
    render(
      <SeatBasedUsageContainer
        filters={DEFAULT_FILTERS}
        isCopilotStandalone={false}
        productName={Products.copilot}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    await expect(screen.findByText('Copilot usage')).resolves.toBeInTheDocument()
    await expect(screen.findByText('Billable licenses')).resolves.toBeInTheDocument()
    const premiumRequest = screen.queryByText('Copilot premium requests')
    expect(premiumRequest).toBeNull()
  })

  test('Renders the copilot premium sku tile when flag is enabled', async () => {
    mockClientEnv({
      featureFlags: ['billingplatform_copilot_premium_sku'],
    })
    render(
      <SeatBasedUsageContainer
        filters={DEFAULT_FILTERS}
        isCopilotStandalone={false}
        productName={Products.copilot}
        codingAgentEnabled={false}
        sparkEnabled={false}
      />,
    )
    await expect(screen.findByText('Copilot usage')).resolves.toBeInTheDocument()
    await expect(screen.findByText('Billable licenses')).resolves.toBeInTheDocument()
    await expect(screen.findByText('Copilot premium requests')).resolves.toBeInTheDocument()
  })
})
