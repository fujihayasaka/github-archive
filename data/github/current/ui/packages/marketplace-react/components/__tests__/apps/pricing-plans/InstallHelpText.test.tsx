import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {InstallHelpText} from '../../../apps/pricing-plans/InstallHelpText'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockPlan} from '../../../../test-utils/mock-data'

const listing = mockAppListing()

describe('InstallHelpText', () => {
  test('renders a message if the free trials have been used', () => {
    const planInfo = mockPlanInfo({freeTrialsUsed: true})
    const plan = mockPlan()
    render(<InstallHelpText planInfo={planInfo} plan={plan} listing={listing} />)

    expect(screen.getByText('You’ve already used a free trial for this app')).toBeInTheDocument()
  })

  test('renders a message if the app installation requirements are not met and the user can edit the listing', () => {
    const planInfo = mockPlanInfo({
      freeTrialsUsed: false,
      installationUrlRequirementMet: false,
      userCanEditListing: true,
    })
    const plan = mockPlan()
    render(<InstallHelpText planInfo={planInfo} plan={plan} listing={listing} />)

    expect(screen.getByText(/This app is not installable because it is missing/)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'an installation URL'})).toHaveAttribute(
      'href',
      '/marketplace/amazing-app/edit/description#naming_and_links',
    )
  })

  test('does not render a message if the app installation requirements are not met and the user cannot edit the listing', () => {
    const planInfo = mockPlanInfo({
      freeTrialsUsed: false,
      installationUrlRequirementMet: false,
      userCanEditListing: false,
    })
    const plan = mockPlan()
    const {container} = render(<InstallHelpText planInfo={planInfo} plan={plan} listing={listing} />)

    expect(container).toBeEmptyDOMElement()
  })

  test('renders a message if the app is buyable and the plan is paid', () => {
    const planInfo = mockPlanInfo({freeTrialsUsed: false, installationUrlRequirementMet: true, isBuyable: true})
    const plan = mockPlan({isPaid: true})
    render(<InstallHelpText planInfo={planInfo} plan={plan} listing={listing} />)

    expect(screen.getByText(/Next: Confirm your installation location and payment information/)).toBeInTheDocument()
  })

  test('renders a message if the app is buyable and the plan is not paid', () => {
    const planInfo = mockPlanInfo({freeTrialsUsed: false, installationUrlRequirementMet: true, isBuyable: true})
    const plan = mockPlan({isPaid: false})
    render(<InstallHelpText planInfo={planInfo} plan={plan} listing={listing} />)

    expect(screen.getByText(/Next: Confirm your installation location/)).toBeInTheDocument()
    expect(screen.queryByText(/and payment information/)).not.toBeInTheDocument()
  })

  test('renders a message if free trials have no been used, the app installation requirements have been met, and the plan is not buyable', () => {
    const planInfo = mockPlanInfo({freeTrialsUsed: false, installationUrlRequirementMet: true, isBuyable: false})
    const plan = mockPlan()
    render(<InstallHelpText planInfo={planInfo} plan={plan} listing={listing} />)

    expect(screen.getByText(/You’ve already purchased this on all of your GitHub accounts/)).toBeInTheDocument()
  })
})
