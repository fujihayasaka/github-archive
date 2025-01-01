import {screen, act} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {StafftoolsBusinessTeamMembersView} from '../../routes/stafftools/StafftoolsBusinessTeamMembersView'
import {getStafftoolsBusinessTeamMembersViewRoutePayload} from '../../test-utils/mock-data'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

const userEvent = setupUserEvent()
const mockVerifiedFetch = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
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

    await act(() => {
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

      await act(() => {
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
