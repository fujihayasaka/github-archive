import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockPlan, mockPlanInfo} from '../../../../test-utils/mock-data'
import PlansRadioGroup from '../../../apps/pricing-plans/PlansRadioGroup'

function renderComponent({plans = [mockPlan()]} = {}) {
  const planInfo = mockPlanInfo({plans})
  render(<PlansRadioGroup planInfo={planInfo} onPlanChange={() => {}} selectedPlanId={planInfo.plans[0]?.id} />)
}

describe('PlansRadioGroup', () => {
  test('Renders each plan', () => {
    const plans = [
      mockPlan({name: 'Free', id: '1'}),
      mockPlan({name: 'Cheap', id: '2'}),
      mockPlan({name: 'Expensive', id: '3'}),
    ]
    renderComponent({plans})

    expect(screen.getAllByRole('radio')).toHaveLength(3)
    expect(screen.getByText('Free')).toBeInTheDocument()
    expect(screen.getByText('Cheap')).toBeInTheDocument()
    expect(screen.getByText('Expensive')).toBeInTheDocument()
  })

  test('Renders a free trial label for paid plans with a free trial', () => {
    const plans = [mockPlan({isPaid: true, hasFreeTrial: true})]
    renderComponent({plans})

    expect(screen.getByText('Free trial available')).toBeInTheDocument()
  })

  test('Does not render a free trial label for paid plans without a free trial', () => {
    const plans = [mockPlan({isPaid: true, hasFreeTrial: false})]
    renderComponent({plans})

    expect(screen.queryByText('Free trial available')).not.toBeInTheDocument()
  })

  test('Does not render a free trial label for free plans', () => {
    const plans = [mockPlan({isPaid: false})]
    renderComponent({plans})

    expect(screen.queryByText('Free trial available')).not.toBeInTheDocument()
  })

  test('Renders the plan description', () => {
    const plans = [mockPlan({description: 'A great plan'})]
    renderComponent({plans})

    expect(screen.getByText('A great plan')).toBeInTheDocument()
  })

  test('Renders plan price information if the plan is paid', () => {
    const plans = [mockPlan({isPaid: true, price: '$5', perUnit: true, unitName: 'seat'})]
    renderComponent({plans})

    expect(screen.getByTestId('plan-price-info')).toHaveTextContent('$5 / seat / month')
  })

  test('Renders $0 price if the plan is not paid and does not have direct billing', () => {
    const plans = [mockPlan({isPaid: false, directBilling: false})]
    renderComponent({plans})

    expect(screen.getByText('$0')).toBeInTheDocument()
  })

  test('Only renders plan bullets for the currently selected plan', () => {
    const plans = [
      mockPlan({id: '1', bullets: ['Render this', 'and this']}),
      mockPlan({id: '2', bullets: ['But not this']}),
    ]
    renderComponent({plans})

    expect(screen.getByText('Render this')).toBeInTheDocument()
    expect(screen.getByText('and this')).toBeInTheDocument()
    expect(screen.queryByText('But not this')).not.toBeInTheDocument()
  })

  test('Renders a message if the selected plan is for organizations only', () => {
    const plans = [mockPlan({forOrganizationsOnly: true})]
    renderComponent({plans})

    expect(screen.getByText('For organizations only')).toBeInTheDocument()
  })

  test('Renders a message if the selected plan is for users only', () => {
    const plans = [mockPlan({forUsersOnly: true})]
    renderComponent({plans})

    expect(screen.getByText('For users only')).toBeInTheDocument()
  })
})
