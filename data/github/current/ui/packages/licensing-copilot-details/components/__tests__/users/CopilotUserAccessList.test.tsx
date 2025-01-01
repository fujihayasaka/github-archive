import {render, screen, act} from '@testing-library/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {ThemeProvider} from '@primer/react'
import {CopilotUserAccessList} from '../../users/CopilotUserAccessList'
import {MemoryRouter} from 'react-router-dom'
import {usersWithCopilotAccess} from '../../../test-utils/mock-data'
import type {User} from '../../../types'

const users = usersWithCopilotAccess
const [firstUser, secondUser] = users
if (!firstUser || !secondUser) {
  throw new Error('Users not found.')
}

const renderCopilotUserAccessList = (
  userList?: User[],
  noUsersWithCopilotFlag?: boolean,
  isCopilotUserFlagEnabled = true,
) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isTeams={false}
          isStafftools={false}
          slug={'test-co'}
        >
          <CopilotUserAccessList
            setOpenGrantAccessDialog={jest.fn()}
            users={userList || users}
            noUsersWithCopilot={noUsersWithCopilotFlag || false}
            isCopilotUserFlagEnabled={isCopilotUserFlagEnabled}
          />
        </NavigationContextProvider>
      </ThemeProvider>
    </MemoryRouter>,
  )
}

describe('CopilotUserAccessList Component', () => {
  test('renders the CopilotUserAccessList component', async () => {
    renderCopilotUserAccessList()
    expect(screen.getByTestId('licensing-copilot-user-access-list-view')).toBeInTheDocument()
  })

  test('does not render the CopilotUserAccessList component when isCopilotUserFlagEnabled is false', () => {
    renderCopilotUserAccessList(users, true, false)
    expect(screen.queryByTestId('licensing-copilot-user-access-list-view')).not.toBeInTheDocument()
  })

  test('renders all users that are passed in', () => {
    renderCopilotUserAccessList()
    expect(screen.getByTestId('licensing-copilot-user-access-list-view')).toBeInTheDocument()

    for (const user of users) {
      expect(screen.getByText(user.login)).toBeInTheDocument()
      expect(screen.getByText(user.name)).toBeInTheDocument()
    }
  })

  test('displays expiration date pill when user license has pending downgrade date', () => {
    // Clone the existing users and add expiration date to one of them
    const usersWithExpiration: User[] = [
      {
        ...usersWithCopilotAccess[0]!,
        dominantLicense: {
          ...usersWithCopilotAccess[0]!.dominantLicense!,
          expirationDate: '2024-12-31',
        },
      },
      {
        ...usersWithCopilotAccess[1]!,
        // Keep the existing dominant license without expiration date
      },
    ]

    renderCopilotUserAccessList(usersWithExpiration)

    expect(screen.getByText('github-1')).toBeInTheDocument()
    expect(screen.getByText('github-2')).toBeInTheDocument()

    const allExpirationPills = screen.queryAllByText('Expires on 2024-12-31')
    expect(allExpirationPills).toHaveLength(1)
  })

  test('renders the CopilotUserAccessList component, and associated dialog when a license review is performed', async () => {
    renderCopilotUserAccessList()
    expect(screen.getByTestId('licensing-copilot-user-access-list-view')).toBeInTheDocument()

    const kebabIcon = await screen.findByTestId(`kebab-icon-${firstUser.id}`)
    expect(kebabIcon).toBeInTheDocument()
    await act(async () => kebabIcon.click())

    const viewLicensesOption = screen.getByTestId(`view-license-assignments-${firstUser.id}`)
    expect(viewLicensesOption).toBeInTheDocument()
    if (viewLicensesOption) {
      await act(async () => viewLicensesOption.click())
    }

    const licenseSummaryDialog = screen.getByTestId(`license-assignment-summary-for-${firstUser.id}`)
    expect(licenseSummaryDialog).toBeInTheDocument()
    expect(screen.getByText(`Copilot license assignments for ${firstUser.name}`)).toBeInTheDocument()
  })

  test('renders the CopilotUserAccessList component, and associated dialog when a license removal is performed', async () => {
    renderCopilotUserAccessList()
    expect(screen.getByTestId('licensing-copilot-user-access-list-view')).toBeInTheDocument()

    const kebabIcon = await screen.findByTestId(`kebab-icon-${firstUser.id}`)
    expect(kebabIcon).toBeInTheDocument()
    await act(async () => kebabIcon.click())

    const disableOption = screen.getByTestId(`unassign-license-${firstUser.id}`)
    expect(disableOption).toBeInTheDocument()
    if (disableOption) {
      await act(async () => disableOption.click())
    }

    const downgradeConfirmationButton = screen.getByRole('button', {name: /Remove licenses/i})
    expect(screen.getByTestId('copilot-license-change-dialog')).toBeInTheDocument()
    expect(downgradeConfirmationButton).toBeInTheDocument()
  })

  test('renders the CopilotUserAccessList component, and associated dialog when a bulk license removal is performed', async () => {
    renderCopilotUserAccessList()

    // Bulk select both users
    const selectAllCheckbox = screen.getByRole('checkbox', {name: /Select all members/i})
    expect(selectAllCheckbox).toBeInTheDocument()
    await act(async () => selectAllCheckbox.click())

    // Verify that both users are selected
    const firstUserCheckbox = screen.getByRole('checkbox', {name: `Select ${firstUser.login}`})
    const secondUserCheckbox = screen.getByRole('checkbox', {name: `Select ${secondUser.login}`})
    expect(firstUserCheckbox).toBeChecked()
    expect(secondUserCheckbox).toBeChecked()

    const removeAccessButton = screen.getByRole('button', {name: /Remove access/i})
    expect(removeAccessButton).toBeInTheDocument()
    await act(async () => removeAccessButton.click())

    // Verify that the bulk disable dialog is displayed
    const downgradeConfirmationButton = screen.getByRole('button', {name: /Remove licenses/i})
    expect(screen.getByTestId('copilot-license-change-dialog')).toBeInTheDocument()
    expect(downgradeConfirmationButton).toBeInTheDocument()
  })

  test('renders the grant access section if the EA has no users with copilot access', () => {
    renderCopilotUserAccessList([], true)
    expect(screen.getByText('No individual licenses')).toBeInTheDocument()
    const grantAccessButton = screen.getByRole('button', {name: /Assign licenses/i})
    expect(grantAccessButton).toBeInTheDocument()
  })

  test('does not render the grant access section if the EA has users with copilot access', () => {
    renderCopilotUserAccessList()
    expect(screen.queryByText('No individual licenses')).not.toBeInTheDocument()
    const grantAccessButton = screen.queryByRole('button', {name: /Assign licenses/i})
    expect(grantAccessButton).not.toBeInTheDocument()
  })

  test('displays pagination controls when users exceed page size of 20', () => {
    const manyUsers = Array.from({length: 25}, (_, i) => ({
      id: i + 1,
      login: `user-${i + 1}`,
      name: `User ${i + 1}`,
      userUrl: `/user-${i + 1}`,
      avatarUrl: `https://github.com/user-${i + 1}.png`,
      licenses: [],
      dominantLicense: null,
    }))

    renderCopilotUserAccessList(manyUsers)

    expect(screen.getByRole('navigation', {name: /Pagination/})).toBeInTheDocument()
    expect(screen.getByLabelText('Page 1')).toBeInTheDocument()
    expect(screen.getByLabelText('Page 2')).toBeInTheDocument()
  })
})
