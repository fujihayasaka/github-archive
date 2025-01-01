import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {CopilotPlanCard} from '../../components/usage'
import type {SubscriptionItem} from '../../types/copilot-for-individuals'

describe('CopilotPlanCard', () => {
  test('Renders the "Copilot" tile for monthly subscriptions', async () => {
    const monthlySubscriptionItem: SubscriptionItem = {
      price: 10.0,
      name: 'GitHub Copilot Pro',
      billingCycle: 'month',
      hasPendingDowngrade: false,
    }
    const props = {
      onFreeTier: false,
      subscriptionItem: monthlySubscriptionItem,
    }
    render(<CopilotPlanCard copilotForIndividualsData={props} />)

    const header = await screen.findByText('Copilot Pro')
    expect(header).toBeTruthy()

    await waitFor(() => expect(screen.getByTestId('bill-section')).toHaveTextContent('$10.00per month'))
  })

  test('Renders the "Copilot" tile for yearly subscriptions', async () => {
    const yearlySubscriptionItem: SubscriptionItem = {
      price: 100.0,
      name: 'GitHub Copilot Pro',
      billingCycle: 'year',
      hasPendingDowngrade: false,
    }
    const props = {
      onFreeTier: false,
      subscriptionItem: yearlySubscriptionItem,
    }
    render(<CopilotPlanCard copilotForIndividualsData={props} />)

    const header = await screen.findByText('Copilot Pro')
    expect(header).toBeTruthy()

    await waitFor(() => expect(screen.getByTestId('bill-section')).toHaveTextContent('$100.00per year'))
  })

  test('Renders Copilot Pro Plus tile', async () => {
    const copilotProPlusSubscriptionItem: SubscriptionItem = {
      price: 390.0,
      name: 'GitHub Copilot Pro+',
      billingCycle: 'year',
      hasPendingDowngrade: false,
    }
    const props = {
      onFreeTier: false,
      subscriptionItem: copilotProPlusSubscriptionItem,
    }

    render(<CopilotPlanCard copilotForIndividualsData={props} />)

    const header = await screen.findByText('Copilot Pro+')
    expect(header).toBeTruthy()
    await waitFor(() => expect(screen.getByTestId('bill-section')).toHaveTextContent('$390.00per year'))
  })

  test('Renders with "Downgrade Pending" label', async () => {
    const copilotProPlusSubscriptionItem: SubscriptionItem = {
      price: 390.0,
      name: 'GitHub Copilot Pro+',
      billingCycle: 'year',
      hasPendingDowngrade: true,
    }
    const props = {
      onFreeTier: false,
      subscriptionItem: copilotProPlusSubscriptionItem,
    }

    render(<CopilotPlanCard copilotForIndividualsData={props} />)
    await waitFor(() => expect(screen.getByTestId('copilot-plan-card')).toHaveTextContent('Downgrade Pending'))
  })

  test('Renders with Copilot Free information', async () => {
    const props = {
      onFreeTier: true,
    }

    render(<CopilotPlanCard copilotForIndividualsData={props} />)
    const header = await screen.findByText('Copilot Free')
    expect(header).toBeTruthy()
    await waitFor(() => expect(screen.getByTestId('bill-section')).toHaveTextContent('$0.00per month'))
  })
})
