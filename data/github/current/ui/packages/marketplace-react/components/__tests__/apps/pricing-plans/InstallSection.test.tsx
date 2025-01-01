import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {InstallSection} from '../../../apps/pricing-plans/InstallSection'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockPlan} from '../../../../test-utils/mock-data'

describe('InstallSection', () => {
  test('renders message for regular EMU user', () => {
    render(
      <InstallSection
        planInfo={mockPlanInfo({isRegularEmuUser: true, emuOwnerButNotAdmin: false})}
        listing={mockAppListing()}
        selectedPlan={mockPlan()}
      />,
    )

    expect(screen.getByTestId('install-section')).toBeInTheDocument()
    expect(
      screen.getByText(
        'Only enterprise administrators and organization admins can purchase applications from the marketplace.',
      ),
    ).toBeInTheDocument()
  })

  test('renders message for EMU owner but not admin', () => {
    render(
      <InstallSection
        planInfo={mockPlanInfo({isRegularEmuUser: false, emuOwnerButNotAdmin: true})}
        listing={mockAppListing()}
        selectedPlan={mockPlan()}
      />,
    )

    expect(screen.getByTestId('install-section')).toBeInTheDocument()
    expect(screen.getByText('Only enterprise admins are able to install paid Marketplace plans.')).toBeInTheDocument()
  })

  test('renders plan form when a plan is provided', () => {
    render(
      <InstallSection
        planInfo={mockPlanInfo({isRegularEmuUser: false, emuOwnerButNotAdmin: false})}
        listing={mockAppListing()}
        selectedPlan={mockPlan()}
      />,
    )

    expect(screen.getByTestId('install-section')).toBeInTheDocument()
    expect(screen.getByTestId('plan-form')).toBeInTheDocument()
  })

  test('does not render when no conditions are met', () => {
    render(
      <InstallSection
        planInfo={mockPlanInfo({isRegularEmuUser: false, emuOwnerButNotAdmin: false})}
        listing={mockAppListing()}
        selectedPlan={undefined}
      />,
    )

    expect(screen.queryByTestId('install-section')).not.toBeInTheDocument()
  })
})
