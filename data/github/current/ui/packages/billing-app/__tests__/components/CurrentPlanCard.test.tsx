import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {ORGANIZATION_CUSTOMER} from '../../test-utils/mock-data'

import {CurrentPlanCard} from '../../components/usage'

const TEST_PATH = '/test-path'

describe('CurrentPlanCard', () => {
  test('Renders the "Current plan" tile', async () => {
    render(<CurrentPlanCard customer={ORGANIZATION_CUSTOMER} changeDurationPath={TEST_PATH} />)

    const header = await screen.findByText('Current plan - GitHub Team')
    expect(header).toBeTruthy()

    await waitFor(() => expect(screen.getByTestId('bill-section')).toHaveTextContent('$900.00per year'))

    await waitFor(() =>
      expect(screen.getByTestId('licenses-section')).toHaveTextContent('100 licenses -$9.00 per user/year'),
    )
  })

  test('Renders the current bill cycle correctly', async () => {
    ORGANIZATION_CUSTOMER.planDuration = 'month'
    ORGANIZATION_CUSTOMER.seats = 10
    ORGANIZATION_CUSTOMER.pricePerSeat = 5
    ORGANIZATION_CUSTOMER.paymentAmount = 500
    ORGANIZATION_CUSTOMER.plan = 'team'

    render(<CurrentPlanCard customer={ORGANIZATION_CUSTOMER} changeDurationPath={TEST_PATH} />)

    await waitFor(() => expect(screen.getByTestId('bill-section')).toHaveTextContent('$500.00per month'))

    await waitFor(() =>
      expect(screen.getByTestId('licenses-section')).toHaveTextContent('10 licenses -$5.00 per user/month'),
    )
  })

  test('Renders different text for free organizations', async () => {
    ORGANIZATION_CUSTOMER.planDuration = 'month'
    ORGANIZATION_CUSTOMER.seats = 10
    ORGANIZATION_CUSTOMER.pricePerSeat = 0
    ORGANIZATION_CUSTOMER.paymentAmount = 0
    ORGANIZATION_CUSTOMER.plan = 'free_organization'

    render(<CurrentPlanCard customer={ORGANIZATION_CUSTOMER} changeDurationPath={TEST_PATH} />)

    await waitFor(() => expect(screen.getByTestId('bill-section')).toHaveTextContent('$0per month'))

    await waitFor(() =>
      expect(screen.getByTestId('licenses-section')).toHaveTextContent(
        'GitHub Free plan offers basics for organizations and developers.',
      ),
    )
  })

  test('Renders N/A for unexpected plans', async () => {
    ORGANIZATION_CUSTOMER.plan = 'business'

    render(<CurrentPlanCard customer={ORGANIZATION_CUSTOMER} changeDurationPath={TEST_PATH} />)

    const header = await screen.findByText('Current plan - N/A')
    expect(header).toBeTruthy()
  })

  test('Renders monthly plan switch', async () => {
    ORGANIZATION_CUSTOMER.planDuration = 'year'
    render(<CurrentPlanCard customer={ORGANIZATION_CUSTOMER} changeDurationPath={TEST_PATH} />)

    await waitFor(() =>
      expect(screen.getByTestId('cycle-switch-section')).toHaveTextContent('Switch to monthly billing'),
    )
  })

  test('Renders yearly plan switch', async () => {
    ORGANIZATION_CUSTOMER.planDuration = 'month'
    render(<CurrentPlanCard customer={ORGANIZATION_CUSTOMER} changeDurationPath={TEST_PATH} />)

    await waitFor(() =>
      expect(screen.getByTestId('cycle-switch-section')).toHaveTextContent('Switch to yearly billing'),
    )
  })
})
