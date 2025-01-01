import {screen, act} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {StafftoolsBusinessTeamOrganizationsView} from '../../routes/stafftools/StafftoolsBusinessTeamOrganizationsView'
import {
  getStafftoolsBusinessTeamOrganizationsViewRoutePayload,
  getStafftoolsBusinessTeamOrganizationsViewRoutePayloadNoOrg,
} from '../../test-utils/mock-data'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

const userEvent = setupUserEvent()
const mockVerifiedFetch = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))
jest.mock('@github-ui/use-debounce', () => ({
  useDebounce: jest.fn((callback, _delay) => callback),
}))

const resetUrlSearchParams = () => {
  window.history.replaceState({...window.history.state}, '', '?')
}

describe('StafftoolsBusinessTeamOrganizationsView', () => {
  beforeEach(() => {
    resetUrlSearchParams()
  })

  test('Renders the organizations list correctly', () => {
    const routePayload = getStafftoolsBusinessTeamOrganizationsViewRoutePayload()
    render(<StafftoolsBusinessTeamOrganizationsView />, {
      routePayload,
    })
    expect(screen.getByTestId('team-link-1').textContent).toBe('justice league')
    expect(screen.getByTestId('team-link-1')).toHaveAttribute('href', '/enterprise_teams/1')
    expect(screen.getByTestId('org-link-1').textContent).toBe('monalisa')
    expect(screen.getByTestId('org-link-1')).toHaveAttribute('href', '/monalisa')
    expect(screen.getByTestId('org-link-2').textContent).toBe('Jane Doe')
    expect(screen.getByTestId('org-link-2')).toHaveAttribute('href', '/jane-doe')
  })

  test('Renders blankslate message when there are no assigned organizations', () => {
    const routePayload = getStafftoolsBusinessTeamOrganizationsViewRoutePayloadNoOrg()
    render(<StafftoolsBusinessTeamOrganizationsView />, {
      routePayload,
    })

    expect(screen.getByTestId('team-link-1').textContent).toBe('justice league')
    expect(screen.getByTestId('team-link-1')).toHaveAttribute('href', '/enterprise_teams/1')
    expect(screen.getByText(/no organizations are assigned to this enterprise team/i)).toBeInTheDocument()
  })

  test('Search text triggers API request with query value', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: () => {
        return {
          totalEntries: 1,
          totalPages: 1,
          enterpriseTeam: {
            id: 1,
            name: 'justice league',
            memberCount: 1,
            showRoute: '/enterprise_teams/1',
          },
          orgs: [
            {
              id: 3,
              name: 'another',
              showRoute: '/another',
            },
          ],
          businessSlug: 'github',
        }
      },
    })

    const routePayload = getStafftoolsBusinessTeamOrganizationsViewRoutePayload()
    render(<StafftoolsBusinessTeamOrganizationsView />, {
      routePayload,
    })

    const searchInput = screen.getByTestId('search-input')
    await userEvent.type(searchInput, 'a')

    act(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith(
        `/stafftools/enterprises/github/enterprise_teams/1/organizations?query=a&page=1`,
        {
          method: 'GET',
          headers: {Accept: 'application/json'},
        },
      )
    })

    expect(screen.getByTestId('org-link-3').textContent).toBe('another')
    expect(screen.queryByTestId('org-link-1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('org-link-2')).not.toBeInTheDocument()
  })

  test('Render blankslate message when no result matches', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: () => {
        return {
          totalEntries: 0,
          totalPages: 0,
          enterpriseTeam: {
            id: 1,
            name: 'justice league',
            memberCount: 1,
            showRoute: '/enterprise_teams/1',
          },
          orgs: [],
          businessSlug: 'github',
        }
      },
    })

    const routePayload = getStafftoolsBusinessTeamOrganizationsViewRoutePayload()
    render(<StafftoolsBusinessTeamOrganizationsView />, {
      routePayload,
    })

    const searchInput = screen.getByTestId('search-input')
    await userEvent.type(searchInput, 'a')

    act(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith(
        `/stafftools/enterprises/github/enterprise_teams/1/organizations?query=a&page=1`,
        {
          method: 'GET',
          headers: {Accept: 'application/json'},
        },
      )
    })

    expect(screen.queryByTestId('org-link-3')).not.toBeInTheDocument()
    expect(screen.queryByTestId('org-link-1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('org-link-2')).not.toBeInTheDocument()
    expect(screen.getByText(/no organizations matched your search criteria/i)).toBeInTheDocument()
  })
})

describe('pagination', () => {
  beforeEach(() => {
    resetUrlSearchParams()
  })

  test('Renders the organizations list with pagination', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: () => {
        return {
          totalEntries: 3,
          totalPages: 2,
          enterpriseTeam: {
            id: 1,
            name: 'justice league',
            showRoute: '/enterprise_teams/1',
          },
          orgs: [
            {
              id: 3,
              name: 'another',
              showRoute: '/another',
            },
          ],
          businessSlug: 'github',
        }
      },
    })

    const routePayload = getStafftoolsBusinessTeamOrganizationsViewRoutePayload()
    render(<StafftoolsBusinessTeamOrganizationsView />, {
      routePayload,
    })

    expect(screen.getByTestId('org-link-1').textContent).toBe('monalisa')
    expect(screen.getByTestId('org-link-2').textContent).toBe('Jane Doe')
    expect(screen.queryByTestId('org-link-3')).not.toBeInTheDocument()

    const nextPageLink = screen.getByText('Next', {selector: 'a'})
    await userEvent.click(nextPageLink)

    act(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith(
        `/stafftools/enterprises/github/enterprise_teams/1/organizations?page=2`,
        {
          method: 'GET',
          headers: {Accept: 'application/json'},
        },
      )
    })

    expect(screen.getByTestId('org-link-3').textContent).toBe('another')
    expect(screen.queryByTestId('org-link-1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('org-link-2')).not.toBeInTheDocument()
  })
})
