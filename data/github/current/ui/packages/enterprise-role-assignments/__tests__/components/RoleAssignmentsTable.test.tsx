import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {RoleAssignmentsTable, RoleType} from '../../components/RoleAssignmentsTable'
import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {SelectedTab} from '../../types/selected-tab'

const roleAssignmentsPathMock = jest.fn((query: string) => `/role-assignments?query=${query}`)
jest.mock('@github-ui/role-assignments/routing-provider', () => ({
  useRoutingContext: () => {
    return {
      roleAssignmentsPath: ({query}: {query: string}) => roleAssignmentsPathMock(query),
      newRoleAssignmentPath: jest.fn(),
    }
  },
}))

let mockUseSearchParams = [new URLSearchParams(''), jest.fn()]
jest.mock('@github-ui/use-navigate', () => {
  return {
    useSearchParams: () => mockUseSearchParams,
  }
})

const navigateMock = jest.fn()
jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: navigateMock, showBanner: jest.fn()}
  }),
}))

describe.each([
  ['Enterprise', RoleType.Enterprise],
  ['Organization', RoleType.Organization],
])('RoleAssignmentsTable with role type %s', (_label, roleType) => {
  const defaultProps = {
    usersCount: 10,
    teamsCount: 10,
    roleType,
    assignments: [],
    hasWriteAccess: true,
    canViewEnterpriseTeams: true,
  }

  beforeEach(() => {
    setupExpectedAsyncErrorHandler()
  })

  afterEach(() => {
    jest.clearAllMocks()
    jest.restoreAllMocks()
    mockUseSearchParams = [new URLSearchParams(''), jest.fn()]
  })

  test('Renders the RoleAssignmentsTable', () => {
    render(<RoleAssignmentsTable {...defaultProps} />)

    // Users tab selected by default
    const userTab = screen.getByTestId('role-assignments-table-tab-users-selected')
    const teamTab = screen.getByTestId('role-assignments-table-tab-teams')
    expect(userTab).toBeInTheDocument()
    expect(teamTab).toBeInTheDocument()
    expect(userTab).toHaveTextContent('Users')
    expect(teamTab).toHaveTextContent('Teams')
    expect(userTab).toHaveAttribute('href', roleAssignmentsPathMock('is:user'))
    expect(teamTab).toHaveAttribute('href', roleAssignmentsPathMock('is:team'))
    expect(screen.getByTestId('role-assignments-filter')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Assign role'})).toBeInTheDocument()
  })

  test('displays blankstate when there are no assignments', () => {
    render(<RoleAssignmentsTable {...defaultProps} />)
    const blankstate = screen.getByTestId('role-assignments-blankstate')
    expect(blankstate).toBeInTheDocument()
  })

  test('teams tab is selected when provided', () => {
    render(<RoleAssignmentsTable {...defaultProps} selectedTab={SelectedTab.Team} />)
    expect(screen.getByTestId('role-assignments-table-tab-teams-selected')).toBeInTheDocument()
  })

  test('users tab is selected when provided', () => {
    render(<RoleAssignmentsTable {...defaultProps} selectedTab={SelectedTab.User} />)
    expect(screen.getByTestId('role-assignments-table-tab-users-selected')).toBeInTheDocument()
  })

  test('displays Pagination component when page count is greater than 1', () => {
    render(<RoleAssignmentsTable {...defaultProps} pageCount={2} />)

    expect(screen.getByTestId('role-assignment-pagination')).toBeInTheDocument()
  })

  test('pagination includes query', () => {
    mockUseSearchParams = [new URLSearchParams('query=is:team search term'), jest.fn()]

    render(<RoleAssignmentsTable {...defaultProps} pageCount={2} />)

    const pagination = screen.getByTestId('role-assignment-pagination')
    expect(pagination).toBeInTheDocument()
    const page2 = within(pagination).getByRole('link', {name: 'Page 1'})
    expect(page2).toBeInTheDocument()
    expect(page2).toHaveAttribute('href', roleAssignmentsPathMock('is:team search term'))
  })

  test('does not display Pagination component when there is a single page', () => {
    render(<RoleAssignmentsTable {...defaultProps} pageCount={1} />)

    expect(screen.queryByTestId('role-assignment-pagination')).not.toBeInTheDocument()
  })

  test('does not display `Assign role` button when hasWriteAccess is false', () => {
    render(<RoleAssignmentsTable {...defaultProps} hasWriteAccess={false} />)

    // Users tab selected by default
    const userTab = screen.getByTestId('role-assignments-table-tab-users-selected')
    const teamTab = screen.getByTestId('role-assignments-table-tab-teams')
    expect(userTab).toBeInTheDocument()
    expect(teamTab).toBeInTheDocument()
    expect(userTab).toHaveTextContent('Users')
    expect(teamTab).toHaveTextContent('Teams')
    expect(userTab).toHaveAttribute('href', roleAssignmentsPathMock('is:user'))
    expect(teamTab).toHaveAttribute('href', roleAssignmentsPathMock('is:team'))
    expect(screen.getByTestId('role-assignments-filter')).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Assign role'})).not.toBeInTheDocument()
  })

  test('tabs href includes query with updated selected tab', () => {
    mockUseSearchParams = [new URLSearchParams('query=is:user is:team search term is:user'), jest.fn()]

    render(<RoleAssignmentsTable {...defaultProps} />)
    const userTab = screen.getByTestId('role-assignments-table-tab-users-selected')
    const teamTab = screen.getByTestId('role-assignments-table-tab-teams')
    expect(userTab).toBeInTheDocument()
    expect(teamTab).toBeInTheDocument()
    expect(userTab).toHaveAttribute('href', roleAssignmentsPathMock('is:user search term'))
    expect(teamTab).toHaveAttribute('href', roleAssignmentsPathMock('is:team search term'))
  })

  test('search redirects with updated query', async () => {
    const prevQuery = 'is:user'
    mockUseSearchParams = [new URLSearchParams(`query=${prevQuery}`), jest.fn()]

    const {user} = render(<RoleAssignmentsTable {...defaultProps} />)

    const search = screen.getByTestId('role-assignments-filter')
    expect(search).toBeInTheDocument()
    const searchInput = within(search).getByTestId('filter-input')
    expect(searchInput).toBeInTheDocument()

    // Assert query from search params is prepopulated
    expect(searchInput).toHaveValue(prevQuery)

    // Submit new search term, expect navigation
    const appendQuery = ' new_search_term'
    await user.type(searchInput, appendQuery)
    expect(searchInput).toHaveValue(prevQuery + appendQuery)
    await user.keyboard('{Enter}')
    expect(navigateMock).toHaveBeenCalledWith(roleAssignmentsPathMock(prevQuery + appendQuery), {
      preventAutofocus: true,
    })
  })

  test('soft nav updates query in filter', () => {
    const prevQuery = 'is:user old_search_term'
    mockUseSearchParams = [new URLSearchParams(`query=${prevQuery}`), jest.fn()]

    const {rerender} = render(<RoleAssignmentsTable {...defaultProps} />)

    const search = screen.getByTestId('role-assignments-filter')
    expect(search).toBeInTheDocument()
    const searchInput = within(search).getByTestId('filter-input')
    expect(searchInput).toBeInTheDocument()

    // Assert query from search params is prepopulated
    expect(searchInput).toHaveValue(prevQuery)

    // Simulate soft nav by rerendering the component with new search params, assert new query is prepopulated
    const newQuery = 'is:team old_search_term'
    mockUseSearchParams = [new URLSearchParams(`query=${newQuery}`), jest.fn()]
    rerender(<RoleAssignmentsTable {...defaultProps} />)
    expect(searchInput).toHaveValue(newQuery)
  })

  test('renders blankslate and no table when there are no assignments and no filter', () => {
    render(<RoleAssignmentsTable {...defaultProps} usersCount={0} teamsCount={0} />)

    expect(screen.getByTestId('role-assignments-blankstate')).toBeInTheDocument()
    expect(screen.queryByTestId('role-assignments-table')).not.toBeInTheDocument()
  })

  test('renders blankslate and no table when there are no assignments and assignee filter', () => {
    mockUseSearchParams = [new URLSearchParams(`query=is:team`), jest.fn()]
    render(<RoleAssignmentsTable {...defaultProps} usersCount={0} teamsCount={0} />)

    expect(screen.getByTestId('role-assignments-blankstate')).toBeInTheDocument()
    expect(screen.queryByTestId('role-assignments-table')).not.toBeInTheDocument()
  })

  test('renders table with no results blankslate if there are no assignments and a non-assignee filter is present', () => {
    mockUseSearchParams = [new URLSearchParams(`query=search term`), jest.fn()]
    render(<RoleAssignmentsTable {...defaultProps} usersCount={0} teamsCount={0} />)

    expect(screen.queryByTestId('role-assignments-blankstate')).not.toBeInTheDocument()
    const table = screen.getByTestId('role-assignments-table')
    expect(table).toBeInTheDocument()
    expect(within(table).getByTestId('role-assignments-no-results-blankstate')).toBeInTheDocument()
  })
})
