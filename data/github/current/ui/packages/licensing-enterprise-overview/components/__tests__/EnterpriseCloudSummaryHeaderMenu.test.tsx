import {fireEvent, render, screen} from '@testing-library/react'
import {ThemeProvider} from '@primer/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {
  type Props as EnterpriseCloudSummaryHeaderMenuProps,
  EnterpriseCloudSummaryHeaderMenu,
} from '../EnterpriseCloudSummaryHeaderMenu'

const defaultProps: EnterpriseCloudSummaryHeaderMenuProps = {
  isSelfServe: true,
  isSelfServeBlocked: false,
  isVolumeLicensed: true,
  onManageSeatsSelect: jest.fn(),
}
interface OverrideProps {
  isStafftools?: boolean
  isSelfServe?: boolean
  isSelfServeBlocked?: boolean
  isVolumeLicensed?: boolean
  onManageSeatsSelect?: jest.Mock
}

const renderMenu = (overrideProps: OverrideProps = {}) => {
  return render(
    <ThemeProvider>
      <NavigationContextProvider
        enterpriseContactUrl={'/enterprise-contact-url'}
        isStafftools={overrideProps.isStafftools ?? false}
        slug={'test-co'}
        isTeams={false}
      >
        <EnterpriseCloudSummaryHeaderMenu {...defaultProps} {...overrideProps} />
      </NavigationContextProvider>
    </ThemeProvider>,
  )
}

describe('EnterpriseCloudSummaryHeaderMenu Component', () => {
  test('header menu button renders and functions', () => {
    renderMenu()

    const menuButton = screen.getByTestId('ghe-summary-menu-button')
    expect(menuButton).toBeInTheDocument()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(menuButton)

    const menuEl = screen.getByTestId('ghe-summary-menu')
    expect(menuEl).toBeInTheDocument()
  })

  test('shows menu when self-served and volume-licensed', () => {
    renderMenu({isSelfServe: true, isVolumeLicensed: true})

    const menuButton = screen.getByTestId('ghe-summary-menu-button')
    expect(menuButton).toBeInTheDocument()
  })

  test('does not show menu when self-served but metered-licensed', () => {
    renderMenu({isSelfServe: true, isVolumeLicensed: false})

    const menuButton = screen.queryByTestId('ghe-summary-menu-button')
    expect(menuButton).not.toBeInTheDocument()
  })

  test('does not show menu when volume-licensed but not self-served', () => {
    renderMenu({isSelfServe: false, isVolumeLicensed: true})

    const menuButton = screen.queryByTestId('ghe-summary-menu-button')
    expect(menuButton).not.toBeInTheDocument()
  })

  test('does not show menu when volume-licensed and self-served but has self-service blocked', () => {
    renderMenu({isSelfServe: true, isVolumeLicensed: true, isSelfServeBlocked: true})
    const menuButton = screen.queryByTestId('ghe-summary-menu-button')
    expect(menuButton).not.toBeInTheDocument()
  })

  test('does not show menu when isStafftools is set', () => {
    renderMenu({isStafftools: true, isVolumeLicensed: true, isSelfServe: true})

    const menuButton = screen.queryByTestId('ghe-summary-menu-button')
    expect(menuButton).not.toBeInTheDocument()
  })

  test('calls onManageSeatsSelect when "Manage seats" is clicked', () => {
    const onManageSeatsSelect = jest.fn()
    renderMenu({isSelfServe: true, isVolumeLicensed: true, onManageSeatsSelect})

    // open the menu
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('ghe-summary-menu-button'))

    // click "Manage seats"
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByTestId('ghe-summary-menu-manage-seats-item'))

    expect(onManageSeatsSelect).toHaveBeenCalled()
  })
})
