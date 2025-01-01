import {act, render, screen} from '@testing-library/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {ThemeProvider} from '@primer/react'
import {MemoryRouter} from 'react-router-dom'
import {getCopilotDetailsProps} from '../../test-utils/mock-data'
import {CopilotAccessList} from '../CopilotAccessList'

const organizations = getCopilotDetailsProps().organizations
const users = getCopilotDetailsProps().users
const enabledOrganizationCount = getCopilotDetailsProps().copilotDetails?.enabledOrganizationCount || 0
const enabledUserCount = getCopilotDetailsProps().copilotDetails?.enabledUserCount || 0
const isCopilotUserFlagEnabled = getCopilotDetailsProps().isCopilotUserFlagEnabled || false
const isCopilotEnterpriseTeamsFlagEnabled = getCopilotDetailsProps().isCopilotEnterpriseTeamsFlagEnabled || false

type CopilotAccessListOverrides = {
  isCopilotUserFlagEnabled?: boolean
  isCopilotEnterpriseTeamsFlagEnabled?: boolean
}

const renderCopilotAccessList = (overrides: CopilotAccessListOverrides = {}) => {
  return render(
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <ThemeProvider>
        <NavigationContextProvider
          enterpriseContactUrl={'/enterprise-contact-url'}
          isTeams={false}
          isStafftools={false}
          slug={'test-co'}
        >
          <CopilotAccessList
            organizations={organizations}
            users={users}
            enabledOrganizationCount={enabledOrganizationCount}
            enabledUserCount={enabledUserCount}
            isCopilotUserFlagEnabled={
              overrides.isCopilotUserFlagEnabled !== undefined
                ? overrides.isCopilotUserFlagEnabled
                : isCopilotUserFlagEnabled
            }
            isCopilotEnterpriseTeamsFlagEnabled={
              overrides.isCopilotEnterpriseTeamsFlagEnabled !== undefined
                ? overrides.isCopilotEnterpriseTeamsFlagEnabled
                : isCopilotEnterpriseTeamsFlagEnabled
            }
          />
        </NavigationContextProvider>
      </ThemeProvider>
    </MemoryRouter>,
  )
}

describe('CopilotAccessList Component', () => {
  test('renders the SearchBar component', () => {
    renderCopilotAccessList()

    const searchBar = screen.queryByTestId('search-bar')
    expect(searchBar).toBeInTheDocument()
    expect(searchBar).toHaveAttribute('placeholder', 'Search or filter organizations')
    expect(searchBar).toHaveAttribute('aria-label', 'Search or filter organizations')
  })

  test('renders the CopilotAccessList component with tab values and counters', async () => {
    renderCopilotAccessList()

    const copilotAccessSection = screen.queryByTestId('licensing-copilot-access-list')
    expect(copilotAccessSection).toBeInTheDocument()

    // Organizations tab is rendered with proper counter
    const organizationsTab = screen.queryByTestId('licensing-copilot-organization-access-tab')
    expect(organizationsTab).toBeInTheDocument()
    expect(organizationsTab).toHaveTextContent('6')
  })

  test('does not render the user access tab when the flag is disabled', async () => {
    renderCopilotAccessList({isCopilotUserFlagEnabled: false})

    const organizationsTab = screen.queryByTestId('licensing-copilot-organization-access-list-view')
    expect(organizationsTab).toBeInTheDocument()

    const usersTabButton = screen.queryByTestId('licensing-copilot-users-access-tab')
    expect(usersTabButton).not.toBeInTheDocument()
  })

  test('does not render the enterprise teams tab when the flag is disabled', async () => {
    renderCopilotAccessList({isCopilotEnterpriseTeamsFlagEnabled: false})

    const organizationsTab = screen.queryByTestId('licensing-copilot-organization-access-list-view')
    expect(organizationsTab).toBeInTheDocument()

    const enterpriseTeamsTabButton = screen.queryByTestId('licensing-copilot-enterprise-teams-access-tab')
    expect(enterpriseTeamsTabButton).not.toBeInTheDocument()
  })

  test('renders the CopilotAccessList component, and allows switching between tabs', async () => {
    renderCopilotAccessList()

    const organizationsTab = screen.queryByTestId('licensing-copilot-organization-access-list-view')
    expect(organizationsTab).toBeInTheDocument()

    const usersTabButton = screen.getByTestId('licensing-copilot-users-access-tab')
    expect(usersTabButton).toBeInTheDocument()
    expect(usersTabButton).toHaveTextContent('10')

    await act(async () => {
      usersTabButton.click()
    })

    const usersTab = screen.getByTestId('licensing-copilot-user-access-list-view')
    expect(organizationsTab).not.toBeInTheDocument()
    expect(usersTab).toBeInTheDocument()
  })

  test('renders the grant access button, which displays the organization grant access modal when clicked', async () => {
    renderCopilotAccessList()
    const grantAccessButton = screen.getByRole('button', {name: /Grant access/i})
    expect(grantAccessButton).toBeInTheDocument()
    await act(async () => grantAccessButton.click())
    await screen.findByTestId('licensing-copilot-organization-grant-access-list')
  })
})
