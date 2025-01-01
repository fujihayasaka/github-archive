import {render} from '@github-ui/react-core/test-utils'
import {act, screen, waitFor, within} from '@testing-library/react'
import {BusinessTeamMembersView} from '../routes/BusinessTeamMembersView'
import {
  getBusinessTeamMembersViewRoutePayload,
  getBusinessTeamMembersViewRoutePayloadEmpty,
} from '../test-utils/mock-data'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

jest.useFakeTimers()
const mockNavigate = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigate,
  }
})

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
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

  const firstUser = screen.getByTestId('list-item-1')
  expect(firstUser).toBeVisible()
  expect(within(firstUser).getByTestId('list-view-item-title-container')).toHaveTextContent('hubot')
  expect(within(firstUser).getByTestId('list-view-item-description')).toHaveTextContent('hubot')

  const secondUser = screen.getByTestId('list-item-2')
  expect(secondUser).toBeVisible()
  expect(within(secondUser).getByTestId('list-view-item-title-container')).toHaveTextContent('monalisa octocat')
  expect(within(secondUser).getByTestId('list-view-item-description')).toHaveTextContent('monalisa')
})

test('Renders blank state', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayloadEmpty()
  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  expect(screen.getByText('Your team has no members')).toBeVisible()
  expect(
    screen.getByText("Use the 'Add Member' button below to add members and start building your team."),
  ).toBeVisible()
  expect(screen.getByRole('button', {name: 'Add members'})).toBeVisible()
})

test('Add members button is inactive when team member limit is reached', () => {
  const routePayload = getBusinessTeamMembersViewRoutePayload()
  routePayload.meta.memberLimitReached = true
  render(<BusinessTeamMembersView />, {
    routePayload,
  })

  expect(screen.getByRole('button', {name: 'Add members'})).toHaveAttribute('data-inactive', 'true')
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
