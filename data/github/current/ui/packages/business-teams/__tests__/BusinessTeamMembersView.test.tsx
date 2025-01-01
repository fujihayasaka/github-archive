import {render} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor, within} from '@testing-library/react'
import {BusinessTeamMembersView} from '../routes/BusinessTeamMembersView'
import {
  getBusinessTeamMembersViewRoutePayload,
  getBusinessTeamMembersViewRoutePayloadEmpty,
} from '../test-utils/mock-data'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {updateSearchParams} from '@github-ui/history'

jest.useFakeTimers()
const mockNavigate = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigate,
  }
})

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

beforeEach(() => {
  window.history.replaceState({...window.history.state}, '', '?')
})

test('Renders header w/ members tab current', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  // assert any content from header
  expect(screen.getByTestId('overview-team-name')).toBeInTheDocument()

  const membersTab = screen.getByTestId('nav-Members')
  expect(membersTab).toHaveAttribute('aria-current', 'page')

  const orgsTab = screen.getByTestId('nav-Organizations')
  expect(orgsTab).toBeInTheDocument()
})

test('Renders header without Organizations tab when org assignments is disabled', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  routePayload.orgAssignmentsEnabled = false

  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const orgsTab = screen.queryByTestId('nav-Organizations')
  expect(orgsTab).not.toBeInTheDocument()
})

test('Renders the BusinessTeamMemberView with members', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  // All the tests in the add user component are in AddUserToTeamButton.test.tsx
  expect(screen.getByRole('button', {name: 'Add members'})).toBeVisible()

  const teamMemberLimitBanner = screen.queryByTestId('team-member-limit-error')
  expect(teamMemberLimitBanner).not.toBeInTheDocument()

  const firstUser = screen.getByTestId('list-item-1')
  expect(firstUser).toBeVisible()
  expect(within(firstUser).getByTestId('list-view-item-title-container')).toHaveTextContent('hubot')
  expect(within(firstUser).getByTestId('list-view-item-description')).toHaveTextContent('hubot')

  const secondUser = screen.getByTestId('list-item-2')
  expect(secondUser).toBeVisible()
  expect(within(secondUser).getByTestId('list-view-item-title-container')).toHaveTextContent('monalisa octocat')
  expect(within(secondUser).getByTestId('list-view-item-description')).toHaveTextContent('monalisa')
})

test('Renders the BusinessTeamMemberView with flash banner after team was created', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const searchParams = new URLSearchParams(window.location.search)
  searchParams.set('created', '1')
  updateSearchParams(searchParams)
  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const createdBanner = screen.getByTestId('flash-message-created')
  expect(createdBanner).toBeInTheDocument()

  expect(window.location.search).toBe('')
})

test('Dismiss team created flash banner when the Dismiss Banner button is clicked', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const searchParams = new URLSearchParams(window.location.search)
  searchParams.set('created', '1')
  updateSearchParams(searchParams)
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const createdBanner = screen.getByTestId('flash-message-created')
  expect(createdBanner).toBeInTheDocument()

  const dismissButton = within(createdBanner).getByRole('button')
  expect(dismissButton).toBeInTheDocument()

  await user.click(dismissButton)

  expect(createdBanner).not.toBeInTheDocument()
  expect(window.location.search).toBe('')
})

test('Renders blank state', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayloadEmpty()
  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  expect(screen.getByText('Your team has no members')).toBeVisible()
  expect(
    screen.getByText("Use the 'Add members' button below to add members and start building your team."),
  ).toBeVisible()
  expect(screen.getByRole('button', {name: 'Add members'})).toBeVisible()
})

test('Add members button is inactive and shows banner and tooltip when team member limit is reached', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  routePayload.meta.memberLimitReached = true
  routePayload.meta.membersAllowedToAdd = 0
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const addMembersButton = screen.getByRole('button', {name: 'Add members'})
  expect(addMembersButton).toHaveAttribute('data-inactive', 'true')

  const teamMemberLimitBanner = screen.getByTestId('team-member-limit-error')
  expect(teamMemberLimitBanner).toBeInTheDocument()

  await user.hover(addMembersButton)
  const toolTipLimit = screen.getByText(
    `Cannot add more members, team has reached the ${routePayload.enterpriseTeamMembersLimit} member limit.`,
  )
  expect(toolTipLimit).toBeVisible()
})

test('Sort by name ascending menu triggers search', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        payload: {
          ...routePayload,
        },
      }
    },
  })

  const sortMenu = screen.getByTestId('filterDropdown-header')
  expect(sortMenu).toBeVisible()
  await user.click(sortMenu)

  const nameDescending = screen.getByTestId('sort-name-ascending')
  expect(nameDescending).toBeVisible()
  await user.click(nameDescending)

  expect(window.location.search).toBe('?order=Ascending&page=1')
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
    '/enterprises/acme-corp/teams/acme-engineering?order=Ascending&page=1',
    {
      method: 'GET',
      headers: {Accept: 'application/json'},
    },
  )
})

test('Sort by name descending menu triggers search', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        payload: {
          ...routePayload,
          members: [
            {
              displayLogin: 'monalisa',
              id: 2,
              profileName: 'monalisa octocat',
              avatarUrl: 'http://alambic.github.localhost/avatars/u/1',
            },
            {
              displayLogin: 'hubot',
              id: 1,
              profileName: 'hubot',
              avatarUrl: 'http://alambic.github.localhost/avatars/u/2',
            },
          ],
          meta: {
            ...routePayload.meta,
            orderOption: 'Descending',
          },
        },
      }
    },
  })

  const sortMenu = screen.getByTestId('filterDropdown-header')
  expect(sortMenu).toBeVisible()
  await user.click(sortMenu)

  const nameDescending = screen.getByTestId('sort-name-descending')
  expect(nameDescending).toBeVisible()
  await user.click(nameDescending)

  expect(window.location.search).toBe('?order=Descending&page=1')
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
    '/enterprises/acme-corp/teams/acme-engineering?order=Descending&page=1',
    {
      method: 'GET',
      headers: {Accept: 'application/json'},
    },
  )
})

test('Searching for user triggers search', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        payload: {
          ...routePayload,
          members: [
            {
              displayLogin: 'monalisa',
              id: 2,
              profileName: 'monalisa octocat',
              avatarUrl: 'http://alambic.github.localhost/avatars/u/1',
            },
          ],
          meta: {
            ...routePayload.meta,
            totalMemberCount: 1,
          },
        },
      }
    },
  })

  const searchInput = screen.getByTestId('member-search-input')
  expect(searchInput).toBeVisible()
  await act(async () => {
    await user.type(searchInput, 'monalisa')
  })

  jest.runOnlyPendingTimers()

  await waitFor(() => expect(window.location.search).toBe('?query=monalisa&page=1'))
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
    '/enterprises/acme-corp/teams/acme-engineering?query=monalisa&page=1',
    {
      method: 'GET',
      headers: {Accept: 'application/json'},
    },
  )
})

test('Renders empty state if no members after search (not to be confused with blank state)', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        payload: {
          ...routePayload,
          members: [],
          meta: {
            ...routePayload.meta,
            totalMemberCount: 0,
            filter: 'nomatch',
          },
        },
      }
    },
  })

  const searchInput = screen.getByTestId('member-search-input')
  expect(searchInput).toBeVisible()
  await act(async () => {
    await user.type(searchInput, 'nomatch')
  })

  jest.runOnlyPendingTimers()

  await waitFor(() => expect(window.location.search).toBe('?query=nomatch&page=1'))
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
    '/enterprises/acme-corp/teams/acme-engineering?query=nomatch&page=1',
    {
      method: 'GET',
      headers: {Accept: 'application/json'},
    },
  )
})

test('Renders blank state for IDP-linked team with loading state when just created', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayloadEmpty()
  routePayload.enterpriseTeam = {
    id: 1,
    linkedToExternalGroup: true,
    name: 'Engineering',
    slug: 'acme-engineering',
    description: 'Engineering team',
    totalMemberCount: 0,
    totalOrganizationCount: 0,
    totalRoleCount: 0,
    organizationSelectionType: 'none',
  }
  routePayload.externalGroup = {
    id: 1,
    displayName: 'Engineering Group',
    updatedAt: '2023-10-01T00:00:00Z',
  }

  const searchParams = new URLSearchParams(window.location.search)
  searchParams.set('created', '1')
  updateSearchParams(searchParams)

  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  expect(screen.getByText('Waiting for members to sync')).toBeVisible()
  expect(screen.getByText(/This team is linked to the identity provider group Engineering Group/)).toBeVisible()
  expect(screen.getByText(/The members from this group are being synced/)).toBeVisible()
  expect(screen.getByRole('button', {name: 'Refresh'})).toBeVisible()
})

test('Renders blank state for IDP-linked team with no members after sync completed', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayloadEmpty()
  routePayload.enterpriseTeam = {
    id: 1,
    linkedToExternalGroup: true,
    name: 'Engineering',
    slug: 'acme-engineering',
    description: 'Engineering team',
    totalMemberCount: 0,
    totalOrganizationCount: 0,
    totalRoleCount: 0,
    organizationSelectionType: 'none',
  }
  routePayload.externalGroup = {
    id: 1,
    displayName: 'Engineering Group',
    updatedAt: '2023-10-01T00:00:00Z',
  }

  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  expect(screen.getByText('Your team has no members')).toBeVisible()
  expect(screen.getByText(/Your team is managed by an identity provider group with no members/)).toBeVisible()
  expect(
    screen.getByText(/To add members, you need to add members to the group in your Identity Provider/),
  ).toBeVisible()
  expect(
    screen.getByText(/Alternatively, you can change the group or switch to manual member management/),
  ).toBeVisible()
  const addMembersButton = screen.queryByRole('button', {name: 'Add members'})
  expect(addMembersButton).not.toBeInTheDocument()
})

test('When externalGroup is present, shows IdP group and updated time, and hides Add members button', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  routePayload.externalGroup = {
    id: 123,
    displayName: 'Active Directory Group',
    updatedAt: '2025-05-27T22:41:13.000Z',
  }

  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  // Verify that the IdP group info section is present
  const idpGroupInfo = screen.getByTestId('identity-provider-group-info')
  expect(idpGroupInfo).toBeInTheDocument()
  expect(screen.getByText('Active Directory Group')).toBeInTheDocument()
  const relativeTime = screen.getByTestId('external-group-updated-time')
  expect(relativeTime).toBeInTheDocument()

  // Add members button should not be present
  expect(screen.queryByTestId('add-members-button')).not.toBeInTheDocument()
})

test('When externalGroup is undefined, shows Add members button and hides IdP group info', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  routePayload.externalGroup = undefined

  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  // Verify that the Add members button is present
  expect(screen.getByTestId('add-members-button')).toBeInTheDocument()

  // Verify that the IdP group info section is not shown
  expect(screen.queryByTestId('identity-provider-group-info')).not.toBeInTheDocument()
})

test('Dismiss team created banner shows IDP-linked team with no members', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayloadEmpty()
  routePayload.enterpriseTeam = {
    id: 1,
    linkedToExternalGroup: true,
    name: 'Engineering',
    slug: 'acme-engineering',
    description: 'Engineering team',
    totalMemberCount: 0,
    totalOrganizationCount: 0,
    totalRoleCount: 0,
    organizationSelectionType: 'none',
  }
  routePayload.externalGroup = {
    id: 1,
    displayName: 'Engineering Group',
    updatedAt: '2023-10-01T00:00:00Z',
  }

  const searchParams = new URLSearchParams(window.location.search)
  searchParams.set('created', '1')
  updateSearchParams(searchParams)

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        payload: {
          ...routePayload,
          meta: {
            ...routePayload.meta,
          },
        },
      }
    },
  })

  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  // First we see the loading state
  expect(screen.getByText('Waiting for members to sync')).toBeVisible()

  // Find and click the banner dismiss button
  const createdBanner = screen.getByTestId('flash-message-created')
  const dismissButton = within(createdBanner).getByRole('button')
  await user.click(dismissButton)

  // Now we should see the "no members" state for an IDP-linked team
  expect(screen.queryByText('Waiting for members to sync')).not.toBeInTheDocument()
  expect(screen.getByText('Your team has no members')).toBeVisible()
  expect(screen.getByText(/Your team is managed by an identity provider group with no members/)).toBeVisible()
})

test('Clicking refresh button on IDP-linked team calls API to refresh data', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayloadEmpty()
  routePayload.enterpriseTeam = {
    id: 1,
    linkedToExternalGroup: true,
    name: 'Engineering',
    slug: 'acme-engineering',
    description: 'Engineering team',
    totalMemberCount: 0,
    totalOrganizationCount: 0,
    totalRoleCount: 0,
    organizationSelectionType: 'none',
  }
  routePayload.externalGroup = {
    id: 1,
    displayName: 'Engineering Group',
    updatedAt: '2023-10-01T00:00:00Z',
  }

  const searchParams = new URLSearchParams(window.location.search)
  searchParams.set('created', '1')
  updateSearchParams(searchParams)

  mockVerifiedFetchJSON.mockResolvedValueOnce({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        meta: routePayload.meta,
        members: [
          {
            displayLogin: 'testuser',
            id: 3,
            profileName: 'Test User',
            avatarUrl: 'http://alambic.github.localhost/avatars/u/3',
          },
        ],
        enterpriseTeam: routePayload.enterpriseTeam,
        enterpriseSlug: routePayload.enterpriseSlug,
        viewerPermissions: routePayload.viewerPermissions,
        externalGroup: routePayload.externalGroup,
        orgAssignmentsEnabled: routePayload.orgAssignmentsEnabled,
        enterpriseTeamMembersLimit: routePayload.enterpriseTeamMembersLimit,
      }
    },
  })

  const {user} = render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const refreshButton = screen.getByRole('button', {name: 'Refresh'})
  await user.click(refreshButton)

  expect(mockVerifiedFetchJSON).toHaveBeenCalled()
  // Check that the URL contains page=1 parameter
  expect(mockVerifiedFetchJSON.mock.calls[0][0]).toMatch(/\?.*page=1/)

  // Verify that the IdP group info section is not shown
  expect(screen.queryByTestId('identity-provider-group-info')).not.toBeInTheDocument()
})

test('Shows remove member action when team is not linked to an external group', async () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const firstUser = screen.getByTestId('list-item-1')
  expect(firstUser).toBeVisible()

  // Verify the menu button exists (linked teams won't have this)
  const actionMenuButton = within(firstUser).getByTestId('overflow-menu-anchor')
  expect(actionMenuButton).toBeInTheDocument()
})

test('Hides remove member action when team is linked to an external group', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  routePayload.enterpriseTeam.linkedToExternalGroup = true
  routePayload.externalGroup = {
    id: 123,
    displayName: 'Active Directory Group',
    updatedAt: '2025-05-27T22:41:13.000Z',
  }

  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  const firstUser = screen.getByTestId('list-item-1')
  expect(firstUser).toBeVisible()

  // Verify there's no action bar button/menu for removing users
  expect(within(firstUser).queryByLabelText('Open menu')).not.toBeInTheDocument()
})
