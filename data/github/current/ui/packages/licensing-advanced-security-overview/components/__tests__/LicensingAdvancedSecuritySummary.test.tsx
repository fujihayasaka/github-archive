import {getLicensingAdvancedSecuritySummaryProps, getSelfServeSubscriptionInfo, skus} from '../../test-utils/mock-data'
import {screen} from '@testing-library/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {LicensingAdvancedSecuritySummary} from '../LicensingAdvancedSecuritySummary'
import {render} from '@github-ui/react-core/test-utils'

const renderLicensingAdvancedSecuritySummary = (overrideProps = {}) => {
  return render(
    <NavigationContextProvider enterpriseContactUrl={'/enterprise-contact-url'} isStafftools={false} slug={'test-co'}>
      <LicensingAdvancedSecuritySummary {...getLicensingAdvancedSecuritySummaryProps()} {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('LicensingAdvancedSecuritySummary Component', () => {
  test('renders the summary UI when isAdvancedSecurityEnabled is true', () => {
    renderLicensingAdvancedSecuritySummary({skus: [{...skus[0], consumedLicenses: 30}]})

    const summaryHeaderTitleEl = screen.queryByTestId('usage-summary-header-title')
    expect(summaryHeaderTitleEl).toBeInTheDocument()
    expect(summaryHeaderTitleEl).toHaveTextContent('Consumed licenses')

    const consumedLicensesAmountEl = screen.queryByTestId('summary-item-amount')
    expect(consumedLicensesAmountEl).toBeInTheDocument()
    expect(consumedLicensesAmountEl).toHaveTextContent('30')
  })

  test('does not render the summary UI when isAdvancedSecurityEnabled is false', () => {
    renderLicensingAdvancedSecuritySummary({consumedLicenses: 30, isAdvancedSecurityEnabled: false})

    const consumedLicensesHeaderEl = screen.queryByTestId('usage-summary-header')
    expect(consumedLicensesHeaderEl).not.toBeInTheDocument()
  })
})

describe('LicensingAdvancedSecuritySummary manage seats', () => {
  test('renders the manage licenses menu option when isSelfServeAdvancedSecurity is true', async () => {
    const {user} = renderLicensingAdvancedSecuritySummary({
      isSelfServeAdvancedSecurity: true,
      isMeteredLicensed: false,
    })

    expect(screen.queryByTestId('manage-seats')).not.toBeInTheDocument()

    const menuButton = screen.getByTestId('ghas-summary-menu-button')
    expect(menuButton).toBeInTheDocument()

    // open the menu
    await user.click(menuButton)

    const manageSeatsMenuItem = screen.getByTestId('ghas-summary-menu-manage-seats-item')
    expect(manageSeatsMenuItem).toBeInTheDocument()

    // click the menu item
    await user.click(manageSeatsMenuItem)

    expect(screen.getByTestId('manage-seats')).toBeInTheDocument()
  })
})

describe('LicensingAdvancedSecuritySummary cancel subscription', () => {
  test('renders the cancel subscription menu option when isSelfServeAdvancedSecurity is true', async () => {
    const {user} = renderLicensingAdvancedSecuritySummary({
      isSelfServeAdvancedSecurity: true,
      isMeteredLicensed: false,
      selfServeSubscriptionInfo: getSelfServeSubscriptionInfo(),
    })

    expect(screen.queryByTestId('cancel-subscription')).not.toBeInTheDocument()

    const menuButton = screen.getByTestId('ghas-summary-menu-button')
    expect(menuButton).toBeInTheDocument()

    // open the menu
    await user.click(menuButton)

    const cancelSubscriptionMenuItem = screen.getByTestId('ghas-summary-menu-cancel-subscription-item')
    expect(cancelSubscriptionMenuItem).toBeInTheDocument()

    // click the menu item
    await user.click(cancelSubscriptionMenuItem)

    expect(screen.getByRole('dialog', {name: 'Cancel GitHub Advanced Security'})).toBeInTheDocument()
    expect(
      screen.getByText(/your access to GitHub Advanced Security will expire on March 21, 2025/),
    ).toBeInTheDocument()
  })
})

describe('LicensingAdvancedSecuritySummary pending plan change', () => {
  test('renders the pending plan change banner when one is present', () => {
    renderLicensingAdvancedSecuritySummary({
      isSelfServeAdvancedSecurity: true,
      selfServeSubscriptionInfo: getSelfServeSubscriptionInfo(),
    })

    expect(screen.getByTestId('pending-plan-change')).toBeInTheDocument()
  })

  test('does not render the pending plan change banner when one is not present', () => {
    renderLicensingAdvancedSecuritySummary({
      isSelfServeAdvancedSecurity: true,
      getSelfServeSubscriptionInfo: {
        ...getSelfServeSubscriptionInfo(),
        pendingCycleChange: null,
      },
    })

    expect(screen.queryByTestId('pending-plan-change')).not.toBeInTheDocument()
  })
})
