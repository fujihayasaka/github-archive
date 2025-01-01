import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ThemeProvider} from '@primer/react'

import {AdvancedSecuritySummaryHeaderMenu} from '../AdvancedSecuritySummaryHeaderMenu'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'

const renderAdvancedSecuritySummaryHeaderMenu = (overrideProps = {}, stafftools = false, teams = false) => {
  const defaultProps = {
    eligibleForTrial: false,
    isSelfServeAdvancedSecurity: true,
    invoiceLicenseInfo: undefined,
    isTeams: false,
    skus: [],
    onManageSeatsSelect: jest.fn(),
    onCancelSubscriptionSelect: jest.fn(),
  }
  return render(
    <ThemeProvider>
      <NavigationContextProvider
        enterpriseContactUrl={'/enterprise-contact-url'}
        isStafftools={stafftools}
        slug={'test-co'}
        isTeams={teams}
      >
        <AdvancedSecuritySummaryHeaderMenu {...defaultProps} {...overrideProps} />
      </NavigationContextProvider>
    </ThemeProvider>,
  )
}

describe('AdvancedSecuritySummaryHeaderMenu Component', () => {
  describe('manage seats', () => {
    test('renders menu item', async () => {
      const onManageSeatsSelect = jest.fn()
      const {user} = renderAdvancedSecuritySummaryHeaderMenu({onManageSeatsSelect})

      const menuButton = screen.getByTestId('ghas-summary-menu-button')
      expect(menuButton).toBeInTheDocument()

      await user.click(menuButton)
      const menuEl = screen.getByTestId('ghas-summary-menu-manage-seats-item')
      expect(menuEl).toBeInTheDocument()

      await user.click(menuEl)
      expect(onManageSeatsSelect).toHaveBeenCalled()
    })

    test('does not render menu item for trials', async () => {
      const onManageSeatsSelect = jest.fn()
      renderAdvancedSecuritySummaryHeaderMenu({
        onManageSeatsSelect,
        trialInfo: {isActive: false, expirationDate: new Date()},
      })

      expect(screen.queryByTestId('ghas-summary-menu-button')).not.toBeInTheDocument()
    })
  })

  describe('cancel subscription', () => {
    test('renders the cancel subscription menu item', async () => {
      const onCancelSubscriptionSelect = jest.fn()
      const {user} = renderAdvancedSecuritySummaryHeaderMenu({onCancelSubscriptionSelect})

      const menuButton = screen.getByTestId('ghas-summary-menu-button')
      expect(menuButton).toBeInTheDocument()

      await user.click(menuButton)
      const menuEl = screen.getByTestId('ghas-summary-menu-cancel-subscription-item')
      expect(menuEl).toBeInTheDocument()

      await user.click(menuEl)
      expect(onCancelSubscriptionSelect).toHaveBeenCalled()
    })
  })
})
