import {render, screen, within} from '@testing-library/react'
import {MemoryRouter} from 'react-router-dom'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {usersWithoutCopilotAccess} from '../../../test-utils/mock-data'
import {CopilotUserGrantAccessDialog} from '../../users/CopilotUserGrantAccessDialog'
import {ThemeProvider} from '@primer/react'
import {useEnterpriseMemberSearch} from '../../../hooks/use-enterprise-member-search'
import {setupUserEvent} from '@github-ui/react-core/test-utils'

jest.mock('../../../hooks/use-enterprise-member-search')
const mockUseEnterpriseMemberSearch = useEnterpriseMemberSearch as jest.MockedFunction<typeof useEnterpriseMemberSearch>

const users = usersWithoutCopilotAccess
const [user1, user2] = usersWithoutCopilotAccess
if (!user1 || !user2) {
  throw new Error('users array cannot be empty.')
}

beforeEach(() => {
  // Default mock - no search query
  mockUseEnterpriseMemberSearch.mockReturnValue({
    users: [],
    loading: false,
    isEmpty: true,
    hasQuery: false,
  })
})

const renderCopilotUserGrantAccessDialog = () => {
  const user = setupUserEvent()
  const utils = render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isTeams={false}
          isStafftools={false}
          slug={'test-co'}
        >
          <CopilotUserGrantAccessDialog onDialogClose={jest.fn()} />
        </NavigationContextProvider>
      </ThemeProvider>
    </MemoryRouter>,
  )
  return {...utils, user}
}

describe('CopilotUserGrantAccessDialog Component', () => {
  test('renders the CopilotUserGrantAccessDialog component with search', () => {
    renderCopilotUserGrantAccessDialog()
    expect(screen.getByTestId('licensing-copilot-user-grant-search')).toBeInTheDocument()
  })

  test('renders no members if the search query returns no results', async () => {
    const {user} = renderCopilotUserGrantAccessDialog()
    mockUseEnterpriseMemberSearch.mockImplementation(() => {
      return {
        users: [],
        loading: false,
        isEmpty: true,
        hasQuery: true,
      }
    })

    const searchInput = screen.getByPlaceholderText('Search for members')
    await user.type(searchInput, 'test')

    expect(screen.getByTestId('licensing-copilot-user-grant-search')).toBeInTheDocument()
    expect(screen.getByTestId('licensing-copilot-user-grant-access-list')).toBeInTheDocument()
    expect(screen.getByText('No members found matching your search.')).toBeInTheDocument()
  })

  test('renders the user list returned from the search', async () => {
    const {user} = renderCopilotUserGrantAccessDialog()

    mockUseEnterpriseMemberSearch.mockImplementation(() => {
      return {
        users: [user1],
        loading: false,
        isEmpty: false,
        hasQuery: true,
      }
    })

    const searchInput = screen.getByPlaceholderText('Search for members')
    await user.type(searchInput, 'test')

    expect(screen.getByTestId('licensing-copilot-user-grant-access-list')).toBeInTheDocument()
    expect(screen.getByText(user1.login)).toBeInTheDocument()
    expect(screen.getByText(user1.name)).toBeInTheDocument()

    expect(screen.queryByText(user2.login)).not.toBeInTheDocument()
  })

  test('allows selecting a user to assign a license', async () => {
    const {user} = renderCopilotUserGrantAccessDialog()
    mockUseEnterpriseMemberSearch.mockImplementation(() => {
      return {
        users: [user1],
        loading: false,
        isEmpty: false,
        hasQuery: true,
      }
    })
    const searchInput = screen.getByPlaceholderText('Search for members')
    await user.type(searchInput, 'test')

    const userListItem = screen.getByTestId(`user-li-${user1.login}`)
    const userButton = within(userListItem).getByRole('button')
    await user.click(userButton)

    const selectedUserItem = screen.getByTestId(`selected-user-item-${user1.login}`)
    expect(selectedUserItem).toBeInTheDocument()
  })

  test('allows de-selection of a selected user', async () => {
    const {user} = renderCopilotUserGrantAccessDialog()
    mockUseEnterpriseMemberSearch.mockImplementation(() => {
      return {
        users: [user1],
        loading: false,
        isEmpty: false,
        hasQuery: true,
      }
    })
    const searchInput = screen.getByPlaceholderText('Search for members')
    await user.type(searchInput, 'test')

    const userListItem = screen.getByTestId(`user-li-${user1.login}`)
    const userButton = within(userListItem).getByRole('button')
    await user.click(userButton)

    const selectedUserItem = screen.getByTestId(`selected-user-item-${user1.login}`)
    expect(selectedUserItem).toBeInTheDocument()

    const removeButton = screen.getByTestId(`remove-user-${user1.id}`)
    await user.click(removeButton)
    expect(screen.queryByTestId(`selected-user-item-${user1.login}`)).not.toBeInTheDocument()
  })

  test('renders the CopilotUserChangeAccessDialog to review adding multiple licenses', async () => {
    const {user} = renderCopilotUserGrantAccessDialog()
    mockUseEnterpriseMemberSearch.mockImplementation(() => {
      return {
        users,
        loading: false,
        isEmpty: false,
        hasQuery: true,
      }
    })
    const searchInput = screen.getByPlaceholderText('Search for members')
    await user.type(searchInput, 'test')

    const userListItem1 = screen.getByTestId(`user-li-${user1.login}`)
    const userButton1 = within(userListItem1).getByRole('button')
    await user.click(userButton1)

    const userListItem2 = screen.getByTestId(`user-li-${user2.login}`)
    const userButton2 = within(userListItem2).getByRole('button')
    await user.click(userButton2)

    const confirmButton = screen.getByRole('button', {name: 'Add licenses'})
    await user.click(confirmButton)

    expect(screen.getByTestId(`copilot-license-change-dialog`)).toBeInTheDocument()
    expect(
      screen.getByText((content, element) => {
        return element?.textContent === 'Do you want to assign 2 Copilot Business licenses?'
      }),
    ).toBeInTheDocument()
  })
})
