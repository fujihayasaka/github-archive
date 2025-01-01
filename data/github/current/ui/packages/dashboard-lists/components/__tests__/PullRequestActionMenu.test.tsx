import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {PullRequestActionMenu} from '../PullRequestActionMenu'
import {PullRequestQueryQualifier} from '../../types'
import {isStaff} from '@github-ui/stats'

jest.mock('@github-ui/stats', () => ({
  isStaff: jest.fn(),
}))
const mockIsStaff = isStaff as jest.Mock

describe('PullRequestActionMenu', () => {
  mockIsStaff.mockReturnValue(false)
  // Helper function to render PullRequestActionMenu with default props
  const renderPullRequestActionMenu = (overrides = {}) => {
    const defaultProps = {
      setPullRequestQueryQualifiers: jest.fn(),
      selectedPullRequestQueryQualifiers: [PullRequestQueryQualifier.Authored],
      setPullRequestResultCount: jest.fn(),
      initialResultCount: 6,
      ...overrides,
    }

    return render(<PullRequestActionMenu {...defaultProps} />)
  }

  test('renders the component', () => {
    renderPullRequestActionMenu()

    expect(screen.getByTestId('pull-request-filter-menu-button')).toBeInTheDocument()
  })

  test('opens filter menu when button is clicked', async () => {
    const {user} = renderPullRequestActionMenu()

    expect(screen.queryByTestId('pull-request-filter-menu-overlay')).not.toBeInTheDocument()

    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    expect(screen.getByTestId('pull-request-filter-menu-overlay')).toBeInTheDocument()
    expect(screen.getByText('Pull requests to include')).toBeInTheDocument()
  })

  test('does not close the menu when an item is selected', async () => {
    const {user} = renderPullRequestActionMenu()

    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    expect(screen.getByTestId('pull-request-filter-menu-overlay')).toBeInTheDocument()

    await user.click(screen.getByText('Mentioned'))

    expect(screen.getByTestId('pull-request-filter-menu-overlay')).toBeInTheDocument()
  })

  test('initializes with selected filters', async () => {
    const selectedPullRequestQueryQualifiers = [
      PullRequestQueryQualifier.Authored,
      PullRequestQueryQualifier.ReviewedBy,
      PullRequestQueryQualifier.Mentions,
    ]
    const {user} = renderPullRequestActionMenu({selectedPullRequestQueryQualifiers})

    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    expect(screen.getByRole('menuitemcheckbox', {name: 'Authored'})).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByRole('menuitemcheckbox', {name: 'Reviewed'})).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByRole('menuitemcheckbox', {name: 'Mentioned'})).toHaveAttribute('aria-checked', 'true')
  })

  test('"Authored" item is disabled and always checked', async () => {
    const {user} = renderPullRequestActionMenu()
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))
    const authoredItem = screen.getByRole('menuitemcheckbox', {name: 'Authored'})

    expect(authoredItem).toBeInTheDocument()
    expect(authoredItem).toHaveAttribute('aria-disabled', 'true')
    expect(authoredItem).toHaveAttribute('aria-checked', 'true')

    await user.click(authoredItem)
    expect(authoredItem).toHaveAttribute('aria-checked', 'true')
  })

  test('sets the pull request query qualifers', async () => {
    const setPullRequestQueryQualifiers = jest.fn()
    const {user} = renderPullRequestActionMenu({setPullRequestQueryQualifiers})

    // Open the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))
    expect(screen.getByTestId('pull-request-filter-menu-overlay')).toBeInTheDocument()

    await user.click(screen.getByText('Mentioned'))
    await user.click(screen.getByText('Reviewed'))

    // Close the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))
    expect(screen.queryByTestId('pull-request-filter-menu-overlay')).not.toBeInTheDocument()

    expect(setPullRequestQueryQualifiers).toHaveBeenCalledWith(['author', 'mentions', 'reviewed-by'])
  })

  test('sends click event when pull request filter is saved', async () => {
    const {user} = renderPullRequestActionMenu()

    // Open the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))
    expect(screen.getByTestId('pull-request-filter-menu-overlay')).toBeInTheDocument()

    await user.click(screen.getByText('Mentioned'))
    await user.click(screen.getByText('Reviewed'))

    // Close the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))
    expect(screen.queryByTestId('pull-request-filter-menu-overlay')).not.toBeInTheDocument()

    expectAnalyticsEvents({
      type: 'pull_request_options.save',
      target: 'DASHBOARD_PULL_REQUEST_ACTION_MENU',
      data: {
        category: 'productivity_dashboard',
        filters: 'author,mentions,reviewed-by',
        result_count: '6',
      },
    })
  })

  test('displays Number of results group with options', async () => {
    const {user} = renderPullRequestActionMenu()

    // Open the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    // Verify that the Number of results group is displayed
    expect(screen.getByText('Number of results')).toBeInTheDocument()

    // Verify all options are displayed
    expect(screen.getByRole('menuitemradio', {name: '3'})).toBeInTheDocument()
    expect(screen.getByRole('menuitemradio', {name: '6'})).toBeInTheDocument()
    expect(screen.getByRole('menuitemradio', {name: '9'})).toBeInTheDocument()
    expect(screen.getByRole('menuitemradio', {name: '12'})).toBeInTheDocument()

    // Verify the default option (6) is selected
    expect(screen.getByRole('menuitemradio', {name: '6'})).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByRole('menuitemradio', {name: '3'})).toHaveAttribute('aria-checked', 'false')
    expect(screen.getByRole('menuitemradio', {name: '9'})).toHaveAttribute('aria-checked', 'false')
    expect(screen.getByRole('menuitemradio', {name: '12'})).toHaveAttribute('aria-checked', 'false')
  })

  test('updates result count when an option is selected', async () => {
    const {user} = renderPullRequestActionMenu()

    // Open the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    // Click on the 9 option
    await user.click(screen.getByRole('menuitemradio', {name: '9'}))

    // Verify that the 9 option is now selected
    expect(screen.getByRole('menuitemradio', {name: '9'})).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByRole('menuitemradio', {name: '6'})).toHaveAttribute('aria-checked', 'false')

    //Close the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    // Verify analytics event was sent
    expectAnalyticsEvents({
      type: 'pull_request_options.save',
      target: 'DASHBOARD_PULL_REQUEST_ACTION_MENU',
      data: {
        category: 'productivity_dashboard',
        result_count: '9',
      },
    })
  })

  test('preserves selected result count when menu is closed and reopened', async () => {
    const {user} = renderPullRequestActionMenu()

    // Open the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    // Select the 12 option
    await user.click(screen.getByRole('menuitemradio', {name: '12'}))

    // Close the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    // Reopen the menu
    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    // Verify that the 12 option is still selected
    expect(screen.getByRole('menuitemradio', {name: '12'})).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByRole('menuitemradio', {name: '6'})).toHaveAttribute('aria-checked', 'false')
  })

  test('shows feedback link for staff members', async () => {
    mockIsStaff.mockReturnValue(true)
    const {user} = renderPullRequestActionMenu()

    await user.click(screen.getByTestId('pull-request-filter-menu-button'))

    expect(screen.getByText(/Help give feature preview feedback in this/)).toBeInTheDocument()
    expect(screen.getByText('discussion post')).toBeInTheDocument()
  })

  test('does not show feedback link for non-staff members', async () => {
    mockIsStaff.mockReturnValue(false)
    const {user: nonStaffUser} = renderPullRequestActionMenu()

    await nonStaffUser.click(screen.getByTestId('pull-request-filter-menu-button'))

    expect(screen.queryByText(/Help give feature preview feedback in this/)).not.toBeInTheDocument()
    expect(screen.queryByText('discussion post')).not.toBeInTheDocument()
  })
})
