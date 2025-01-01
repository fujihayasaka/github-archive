import {render} from '@github-ui/react-core/test-utils'
import {AdvancedSecuritySummaryHeaderMenu} from '../AdvancedSecuritySummaryHeaderMenu'
import {screen} from '@testing-library/react'
import {ThemeProvider} from '@primer/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'

const renderAdvancedSecuritySummaryHeaderMenu = (overrideProps = {}) => {
  const defaultProps = {
    onManageSeatsSelect: jest.fn(),
    onCancelSubscriptionSelect: jest.fn(),
  }
  return render(
    <ThemeProvider>
      <NavigationContextProvider enterpriseContactUrl={'/enterprise-contact-url'} isStafftools={false} slug={'test-co'}>
        <AdvancedSecuritySummaryHeaderMenu {...defaultProps} {...overrideProps} />
      </NavigationContextProvider>
    </ThemeProvider>,
  )
}

describe('AdvancedSecuritySummaryHeaderMenu Component', () => {
  test('renders the manage seats menu item', async () => {
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
