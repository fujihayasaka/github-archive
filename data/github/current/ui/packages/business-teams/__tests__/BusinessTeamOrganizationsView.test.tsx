import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {BusinessTeamOrganizationsView} from '../routes/BusinessTeamOrganizationsView'
import {getBusinessTeamOrganizationsViewRoutePayload, getOrganizationSuggestionsPayload} from '../test-utils/mock-data'
import {verifiedFetchJSON, verifiedFetch} from '@github-ui/verified-fetch'

const userEvent = setupUserEvent()

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
const mockVerifiedFetch = verifiedFetch as jest.Mock

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
  verifiedFetch: jest.fn(),
}))

jest.mock('@github-ui/use-navigate', () => ({
  useNavigate: jest.fn(() => jest.fn()),
}))

beforeEach(() => {
  mockVerifiedFetchJSON.mockReset()
  mockVerifiedFetch.mockReset()
})

test('Renders header with orgs tab selected', () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  // assert any content from header
  expect(screen.getByTestId('overview-team-name')).toBeInTheDocument()

  const orgsTab = screen.getByTestId('nav-Organizations')
  expect(orgsTab).toHaveAttribute('aria-current', 'page')
  expect(orgsTab).toHaveTextContent(routePayload.enterpriseTeam.totalOrganizationCount.toString())
})

test('Renders the BusinessTeamOrganizationsView with orgs', () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const firstOrg = screen.getByTestId('list-item-1')
  expect(firstOrg).toBeVisible()
  expect(within(firstOrg).getByTestId('list-view-item-title-container')).toHaveTextContent('A first org')
  expect(within(firstOrg).getByTestId('list-view-item-description')).toHaveTextContent('The first org')

  const firstOrgLink = within(firstOrg).getByRole('link')
  expect(firstOrgLink).toBeVisible()
  expect(firstOrgLink).toHaveAttribute('href', '/first-org')

  const secondOrg = screen.getByTestId('list-item-2')
  expect(secondOrg).toBeVisible()
  expect(within(secondOrg).getByTestId('list-view-item-title-container')).toHaveTextContent('The other org')

  const secondOrgLink = within(secondOrg).getByRole('link')
  expect(firstOrgLink).toBeVisible()
  expect(secondOrgLink).toHaveAttribute('href', '/other-org')
})

test('Renders the select organizations button', () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  render(<BusinessTeamOrganizationsView />, {routePayload})

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeInTheDocument()
  expect(selectOrgsButton).toBeEnabled()
})

test('Renders org suggestions then close without adding', async () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    json: async () => getOrganizationSuggestionsPayload(),
  })

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeInTheDocument()

  expect(screen.queryByTestId('org-1')).not.toBeInTheDocument()
  expect(screen.queryByTestId('org-2')).not.toBeInTheDocument()

  await userEvent.click(selectOrgsButton)

  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
    `/enterprises/${routePayload.enterpriseSlug}/teams/${routePayload.enterpriseTeam.slug}/organization_suggestions?query=`,
    {
      method: 'GET',
      headers: {Accept: 'application/json'},
    },
  )

  const org1 = await screen.findByTestId('org-1')
  expect(org1).toBeInTheDocument()
  expect(org1).toBeEnabled()
  expect(org1).toHaveTextContent('A first org')

  expect(org1).toHaveAttribute('aria-selected', 'false')
  await userEvent.click(org1)
  expect(org1).toHaveAttribute('aria-selected', 'true')

  const org2 = screen.getByTestId('org-2')
  expect(org2).toBeInTheDocument()
  expect(org2).toBeEnabled()
  expect(org2).toHaveTextContent('The other org')

  const org3 = screen.getByTestId('org-3')
  expect(org3).toBeInTheDocument()
  expect(org3).toBeEnabled()
  expect(org3).toHaveTextContent('The third org')

  const cancelButton = screen.getByRole('button', {name: 'Cancel'})
  await userEvent.click(cancelButton)

  // Confirm suggestions panel is closed
  expect(screen.queryByTestId('org-1')).not.toBeInTheDocument()
  expect(screen.queryByTestId('org-2')).not.toBeInTheDocument()

  // Reopen to verify selection is reset
  await userEvent.click(selectOrgsButton)
  const reopenedOrg1 = await screen.findByTestId('org-1')
  expect(reopenedOrg1).toHaveAttribute('aria-selected', 'false')

  const addButton = screen.getByTestId('add-orgs')
  expect(addButton).toHaveTextContent('Add 0')
  expect(addButton).toBeDisabled()
})

test('Add organizations updates the view with selected orgs', async () => {
  const routePayload = {
    ...getBusinessTeamOrganizationsViewRoutePayload(),
    organizations: [
      {
        id: 2,
        name: 'The other org',
        login: 'other-org',
        avatarUrl: 'http://alambic.github.localhost/avatars/orgs/2',
        description: null,
      },
    ],
  }

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    json: async () => {},
  })

  render(<BusinessTeamOrganizationsView />, {routePayload})

  // Ensure we're not using the Add organization button from the blank state
  expect(screen.queryByText(/Your team doesn't have access to any organizations./i)).not.toBeInTheDocument()

  expect(screen.queryByTestId('list-item-1')).not.toBeInTheDocument()
  expect(screen.queryByTestId('list-item-3')).not.toBeInTheDocument()

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await userEvent.click(selectOrgsButton)

  const org1 = await screen.findByTestId('org-1')
  await userEvent.click(org1)

  const org3 = screen.getByTestId('org-3')
  await userEvent.click(org3)

  mockVerifiedFetchJSON.mockResolvedValueOnce({
    json: async () => ({
      payload: getBusinessTeamOrganizationsViewRoutePayload(),
    }),
    ok: true,
  })

  const addButton = screen.getByTestId('add-orgs')
  expect(addButton).toHaveTextContent('Add 2')
  await userEvent.click(addButton)

  const expectedFormData = new FormData()
  expectedFormData.append('organization_ids[]', '1')
  expectedFormData.append('organization_ids[]', '3')

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    `/enterprises/${routePayload.enterpriseSlug}/teams/${routePayload.enterpriseTeam.slug}/organizations`,
    {
      method: 'POST',
      headers: {Accept: 'application/json'},
      body: expectedFormData,
    },
  )

  const listItem1 = await screen.findByTestId('list-item-1')
  const listItem3 = await screen.findByTestId('list-item-3')
  expect(listItem1).toBeVisible()
  expect(listItem3).toBeVisible()

  expect(within(listItem1).getByTestId('list-view-item-title-container')).toHaveTextContent('A first org')
  expect(within(listItem3).getByTestId('list-view-item-title-container')).toHaveTextContent('The third org')
})

test('Add button is disabled when no org is selected', async () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()

  mockVerifiedFetchJSON.mockResolvedValueOnce({
    ok: true,
    json: async () => getOrganizationSuggestionsPayload(),
  })

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await userEvent.click(selectOrgsButton)

  const addButton = screen.getByTestId('add-orgs')
  expect(addButton).toBeDisabled()
})

test('Select organizations button is disabled when org limit is reached', () => {
  const routePayload = {
    ...getBusinessTeamOrganizationsViewRoutePayload(),
    enterpriseTeamsOrgAssignmentLimit: 3,
    enterpriseTeam: {
      ...getBusinessTeamOrganizationsViewRoutePayload().enterpriseTeam,
      totalOrganizationCount: 3,
    },
  }

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeInTheDocument()
  expect(selectOrgsButton).toHaveAttribute('data-inactive', 'true')
})

test('Displays org limit banner when max is reached', () => {
  const routePayload = {
    ...getBusinessTeamOrganizationsViewRoutePayload(),
    enterpriseTeamsOrgAssignmentLimit: 3,
    enterpriseTeam: {
      ...getBusinessTeamOrganizationsViewRoutePayload().enterpriseTeam,
      totalOrganizationCount: 3,
    },
  }

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const banner = screen.getByText(/your team has reached the/i)
  expect(banner).toBeVisible()
})

test('Displays blank state when organizationSelectionType is "disabled"', () => {
  const routePayload = {
    ...getBusinessTeamOrganizationsViewRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamOrganizationsViewRoutePayload().enterpriseTeam,
      totalOrganizationCount: 0,
      organizationSelectionType: 'disabled',
    },
    organizations: null,
  }

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const heading = screen.getByText(/your team doesn't have access to any organizations/i)
  expect(heading).toBeInTheDocument()

  const description = screen.getByText(/Use the 'Add organizations' button below to add organizations to your team./)
  expect(description).toBeInTheDocument()

  const addButton = screen.getByTestId('select-orgs-button')
  expect(addButton).toBeInTheDocument()

  const updateSettingsLink = screen.getByText(/Update settings/)
  expect(updateSettingsLink).toBeInTheDocument()
})

test('Displays blank state when organizationSelectionType is "selected" and no organizations are assigned', () => {
  const routePayload = {
    ...getBusinessTeamOrganizationsViewRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamOrganizationsViewRoutePayload().enterpriseTeam,
      totalOrganizationCount: 0,
      organizationSelectionType: 'selected',
    },
    organizations: [],
  }

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const heading = screen.getByText(/your team doesn't have access to any organizations/i)
  expect(heading).toBeInTheDocument()

  const description = screen.getByText(/Use the 'Add organizations' button below to add organizations to your team./)
  expect(description).toBeInTheDocument()

  const addButton = screen.getByTestId('select-orgs-button')
  expect(addButton).toBeInTheDocument()

  const updateSettingsLink = screen.getByText(/Update settings/)
  expect(updateSettingsLink).toBeInTheDocument()
})

test('Displays blank state when organizationSelectionType is "all"', () => {
  const routePayload = {
    ...getBusinessTeamOrganizationsViewRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamOrganizationsViewRoutePayload().enterpriseTeam,
      organizationSelectionType: 'all',
    },
  }

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const heading = screen.getByText(/Your team has access to all organizations/)
  expect(heading).toBeInTheDocument()

  const description = screen.getByText(
    /Your team currently has access to all 3 organizations. To limit access to specific organizations, update the team access in the settings page./,
  )
  expect(description).toBeInTheDocument()

  const updateSettingsLink = screen.getByText(/Update settings/)
  expect(updateSettingsLink).toBeInTheDocument()

  const seeAllOrgsLink = screen.getByText(/See all organizations/)
  expect(seeAllOrgsLink).toBeInTheDocument()
})

test('Transition from disabled blank state to selected by adding orgs', async () => {
  const routePayload = {
    ...getBusinessTeamOrganizationsViewRoutePayload(),
    enterpriseTeam: {
      ...getBusinessTeamOrganizationsViewRoutePayload().enterpriseTeam,
      totalOrganizationCount: 0,
      organizationSelectionType: 'disabled',
    },
    organizations: null,
  }

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const heading = screen.getByText(/your team doesn't have access to any organizations/i)
  expect(heading).toBeInTheDocument()

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    json: async () => {},
  })

  expect(screen.queryByTestId('list-item-1')).not.toBeInTheDocument()
  expect(screen.queryByTestId('list-item-3')).not.toBeInTheDocument()

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await userEvent.click(selectOrgsButton)

  const org1 = await screen.findByTestId('org-1')
  await userEvent.click(org1)

  const org3 = screen.getByTestId('org-3')
  await userEvent.click(org3)

  mockVerifiedFetchJSON.mockResolvedValueOnce({
    json: async () => ({
      payload: getBusinessTeamOrganizationsViewRoutePayload(),
    }),
    ok: true,
  })

  const addButton = screen.getByTestId('add-orgs')
  expect(addButton).toHaveTextContent('Add 2')
  await userEvent.click(addButton)

  const expectedFormData = new FormData()
  expectedFormData.append('organization_ids[]', '1')
  expectedFormData.append('organization_ids[]', '3')

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    `/enterprises/${routePayload.enterpriseSlug}/teams/${routePayload.enterpriseTeam.slug}/organizations`,
    {
      method: 'POST',
      headers: {Accept: 'application/json'},
      body: expectedFormData,
    },
  )

  const listItem1 = await screen.findByTestId('list-item-1')
  const listItem3 = await screen.findByTestId('list-item-3')
  expect(listItem1).toBeVisible()
  expect(listItem3).toBeVisible()

  expect(within(listItem1).getByTestId('list-view-item-title-container')).toHaveTextContent('A first org')
  expect(within(listItem3).getByTestId('list-view-item-title-container')).toHaveTextContent('The third org')

  expect(screen.queryByText(/your team doesn't have access to any organizations/i)).not.toBeInTheDocument()
})

test('Pagination descending works', async () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const sortBtn = screen.getByTestId('filterDropdown-header')

  await userEvent.click(sortBtn)
  const sortDesc = screen.getByTestId('sort-name-descending')
  await userEvent.click(sortDesc)
  expect(global.window.location.href).toContain('order=Descending')
})

test('Pagination ascending works', async () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  render(<BusinessTeamOrganizationsView />, {routePayload})

  const sortBtn = screen.getByTestId('filterDropdown-header')

  await userEvent.click(sortBtn)
  const sortAsc = screen.getByTestId('sort-name-ascending')
  await userEvent.click(sortAsc)
  expect(global.window.location.href).toContain('order=Ascending')
})

test('Pagination buttons work', async () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  routePayload.meta.pageSize = 2

  render(<BusinessTeamOrganizationsView />, {routePayload})
  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  const pagination = screen.getByTestId('pagination')
  expect(pagination).toBeVisible()
  // we have to use a query selector because the pagination component does not offer any more specific test selectors
  // eslint-disable-next-line testing-library/no-node-access
  const pageTwoButton = pagination.querySelectorAll('a')[2]
  expect(pageTwoButton).toBeVisible()
  await userEvent.click(pageTwoButton!)
  expect(global.window.location.href).toContain('page=2')
})
