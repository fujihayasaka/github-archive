import {screen, act} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {StafftoolsBusinessTeamMembersView} from '../../routes/stafftools/StafftoolsBusinessTeamMembersView'
import {
  getStafftoolsBusinessTeamMembersViewRoutePayload,
  getStafftoolsBusinessTeamMembersViewRoutePayloadNoMembers,
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

describe('StafftoolsBusinessTeamMembersView', () => {
  test('Renders the enterprise team list', () => {
    const routePayload = getStafftoolsBusinessTeamMembersViewRoutePayload()
    render(<StafftoolsBusinessTeamMembersView />, {
      routePayload,
    })
    expect(screen.getByTestId('team-link-1').textContent).toBe('justice league')
    expect(screen.getByTestId('team-link-1')).toHaveAttribute('href', '/enterprise_teams/1')
    expect(screen.getByTestId('member-link-1').textContent).toBe('monalisa')
    expect(screen.getByTestId('member-link-1')).toHaveAttribute('href', '/monalisa')
    expect(screen.getByTestId('member-name-1').textContent).toBe('monalisa')
    expect(screen.getByTestId('member-link-2').textContent).toBe('jane-doe')
    expect(screen.getByTestId('member-link-2')).toHaveAttribute('href', '/jane-doe')
    expect(screen.getByTestId('member-name-2').textContent).toBe('Jane Doe')
  })

  test('Renders blankslate message when there are no members', () => {
    const routePayload = getStafftoolsBusinessTeamMembersViewRoutePayloadNoMembers()
    render(<StafftoolsBusinessTeamMembersView />, {
      routePayload,
    })

    expect(screen.getByText(/no members are in this enterprise team/i)).toBeInTheDocument()
  })

  test('Search text triggers API request with query value', async () => {
    resetUrlSearchParams()

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
          members: [
            {
              id: 3,
              name: 'another',
              login: 'another',
              showRoute: '/another',
            },
          ],
          businessSlug: 'github',
        }
      },
    })

    const routePayload = getStafftoolsBusinessTeamMembersViewRoutePayload()
    render(<StafftoolsBusinessTeamMembersView />, {
      routePayload,
    })

    const searchInput = screen.getByTestId('search-input')
    await userEvent.type(searchInput, 'a')

    act(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith(
        `/stafftools/enterprises/github/enterprise_teams/1/members?query=a&page=1`,
        {
          method: 'GET',
          headers: {Accept: 'application/json'},
        },
      )
    })
    expect(screen.getByTestId('member-link-3').textContent).toBe('another')
    expect(screen.queryByTestId('member-link-1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('member-link-2')).not.toBeInTheDocument()
  })

  test('Render blankslate message when no result matches', async () => {
    resetUrlSearchParams()
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: () => {
        return {
          totalEntries: 0,
          totalPages: 1,
          enterpriseTeam: {
            id: 1,
            name: 'justice league',
            memberCount: 1,
            showRoute: '/enterprise_teams/1',
          },
          members: [],
          businessSlug: 'github',
        }
      },
    })

    const routePayload = getStafftoolsBusinessTeamMembersViewRoutePayload()
    render(<StafftoolsBusinessTeamMembersView />, {
      routePayload,
    })

    const searchInput = screen.getByTestId('search-input')
    await userEvent.type(searchInput, 'z')

    act(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith(
        `/stafftools/enterprises/github/enterprise_teams/1/members?query=z&page=1`,
        {
          method: 'GET',
          headers: {Accept: 'application/json'},
        },
      )
    })

    expect(screen.queryByTestId('member-link-1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('member-link-2')).not.toBeInTheDocument()
    expect(screen.queryByTestId('member-link-3')).not.toBeInTheDocument()
    expect(screen.getByText(/no members matched your search criteria/i)).toBeInTheDocument()
  })

  describe('pagination', () => {
    test('queries with the right params and updates the page', async () => {
      resetUrlSearchParams()

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
              memberCount: 1,
              showRoute: '/enterprise_teams/1',
            },
            members: [
              {
                id: 3,
                name: 'another',
                login: 'another',
                showRoute: '/another',
              },
            ],
            businessSlug: 'github',
          }
        },
      })

      const routePayload = getStafftoolsBusinessTeamMembersViewRoutePayload()
      render(<StafftoolsBusinessTeamMembersView />, {
        routePayload,
      })

      const nextPageLink = screen.getByText('Next', {selector: 'a'})
      await userEvent.click(nextPageLink)

      act(() => {
        expect(mockVerifiedFetch).toHaveBeenCalledWith(
          `/stafftools/enterprises/github/enterprise_teams/1/members?page=2`,
          {
            method: 'GET',
            headers: {Accept: 'application/json'},
          },
        )
      })
      expect(screen.getByTestId('member-link-3').textContent).toBe('another')
      expect(screen.queryByTestId('member-link-1')).not.toBeInTheDocument()
      expect(screen.queryByTestId('member-link-2')).not.toBeInTheDocument()
    })
  })
})
