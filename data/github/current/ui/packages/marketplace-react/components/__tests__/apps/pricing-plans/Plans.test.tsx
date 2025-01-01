import {Plans} from '../../../apps/pricing-plans/Plans'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockPlan} from '../../../../test-utils/mock-data'

describe('Plans', () => {
  test('Renders component', () => {
    render(<Plans planInfo={mockPlanInfo()} listing={mockAppListing()} />)

    expect(screen.getByTestId('pricing')).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Plans and pricing'})).toBeInTheDocument()
  })

  test('Renders plans radio group', () => {
    render(<Plans planInfo={mockPlanInfo()} listing={mockAppListing()} />)

    expect(screen.getByTestId('plans-radio-group')).toBeInTheDocument()
  })

  test('Selecting new plan updates the selected plan', async () => {
    const plans = [
      mockPlan({name: 'Free', id: '1', isPaid: false, price: '$0'}),
      mockPlan({name: 'Cheap', id: '2', isPaid: true, perUnit: false, price: '$5'}),
      mockPlan({name: 'Expensive', id: '3', isPaid: true, price: '$10'}),
    ]

    const {user} = render(<Plans planInfo={mockPlanInfo({plans})} listing={mockAppListing()} />)

    // ensure the price is not rendered initially (free plan)
    expect(screen.queryByTestId('plan-form-price')).not.toBeInTheDocument()

    // click the cheap plan
    const newPlanRadio = screen.getByRole('radio', {name: /Cheap/})
    await user.click(newPlanRadio)

    // ensure the new price is rendered
    expect(screen.getByTestId('plan-form-price')).toHaveTextContent('$5')
  })

  test('Renders install section', () => {
    render(<Plans planInfo={mockPlanInfo()} listing={mockAppListing()} />)

    expect(screen.getByTestId('install-section')).toBeInTheDocument()
  })

  test('Renders terms of service when the selected plan is direct billing, a user is logged in, and an agreement is present', () => {
    const plans = [mockPlan({directBilling: true})]
    render(
      <Plans
        planInfo={mockPlanInfo({
          plans,
          isLoggedIn: true,
          endUserAgreement: {html: 'html', id: 1, version: '1'},
        })}
        listing={mockAppListing()}
      />,
    )

    expect(screen.getByTestId('terms-of-service')).toBeInTheDocument()
  })
})
