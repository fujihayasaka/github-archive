import {screen, act} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {StafftoolsBusinessTeamsListView} from '../../routes/stafftools/StafftoolsBusinessTeamsListView'
import {
  getStafftoolsBusinessTeamsListViewRoutePayload,
  getStafftoolsBusinessTeamsListViewRoutePayloadEnterpriseTeamMembersManagementFFEnabled,
  getStafftoolsBusinessTeamsListViewRoutePayloadNoTeams,
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

describe('EnterpriseTeamsListView', () => {
  test('Renders the enterprise team list', () => {
    const routePayload = getStafftoolsBusinessTeamsListViewRoutePayload()
    render(<StafftoolsBusinessTeamsListView />, {
      routePayload,
    })
    expect(screen.getByTestId('link-to-1').textContent).toBe('justice league')
    expect(screen.getByTestId('link-to-1')).toHaveAttribute('href', '/enterprise_teams/1')
    expect(screen.getByTestId('link-to-2').textContent).toBe('justice league 2')
    expect(screen.getByTestId('link-to-2')).toHaveAttribute('href', '/enterprise_teams/2')
    expect(screen.getByTestId('team-1-external-group-count').textContent).toBe('0 linked groups')
    expect(screen.getByTestId('team-2-external-group-count').textContent).toBe('2 linked groups')
    expect(screen.getByTestId('team-1-member-count').textContent).toBe('1 member')
    expect(screen.getByTestId('team-2-member-count').textContent).toBe('2 members')
    expect(screen.getByTestId('team-1-org-selection-type').textContent).toBe('disabled')
    expect(screen.getByTestId('team-2-org-selection-type').textContent).toBe('all')
  })

  test('Renders the enterprise team list with FF enabled', () => {
    const routePayload = getStafftoolsBusinessTeamsListViewRoutePayloadEnterpriseTeamMembersManagementFFEnabled()
    render(<StafftoolsBusinessTeamsListView />, {
      routePayload,
    })
    expect(screen.getByTestId('link-to-1').textContent).toBe('justice league')
    expect(screen.getByTestId('link-to-1')).toHaveAttribute('href', '/enterprise_teams/1')
    expect(screen.getByTestId('link-to-2').textContent).toBe('justice league 2')
    expect(screen.getByTestId('link-to-2')).toHaveAttribute('href', '/enterprise_teams/2')
    expect(screen.getByTestId('team-1-team-management-type').textContent).toBe('Manually Managed')
    expect(screen.getByTestId('team-2-team-management-type').textContent).toBe('IDP Group Linked')
    expect(screen.getByTestId('team-1-member-count').textContent).toBe('1 member')
    expect(screen.getByTestId('team-2-member-count').textContent).toBe('2 members')
    expect(screen.getByTestId('team-1-external-group-sync-status').textContent).toBe('Not linked')
    expect(screen.getByTestId('team-2-external-group-sync-status').textContent).toBe('Synced')
  })

  test('Search text triggers API request with query value', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: () => {
        return {
          totalEntries: 1,
          totalPages: 1,
          businessSlug: 'github',
          enterpriseTeams: [
            {
              id: 3,
              name: 'another',
              externalGroupCount: 0,
              memberCount: 1,
              organizationSelectionType: 'disabled',
            },
          ],
        }
      },
    })

    const routePayload = getStafftoolsBusinessTeamsListViewRoutePayload()
    render(<StafftoolsBusinessTeamsListView />, {
      routePayload,
    })

    const searchInput = screen.getByTestId('search-input')
    await userEvent.type(searchInput, 'a')

    act(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith(`/stafftools/enterprises/github/enterprise_teams?query=a&page=1`, {
        method: 'GET',
        headers: {Accept: 'application/json'},
      })
    })
    expect(screen.getByTestId('link-to-3').textContent).toBe('another')
    expect(screen.queryByTestId('link-to-1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('link-to-2')).not.toBeInTheDocument()
  })

  test('Render blankslate message when no result matches', async () => {
    resetUrlSearchParams()
    mockVerifiedFetch.mockResolvedValue({
      ok: true,
      statusText: 'OK',
      json: () => {
        return {
          totalEntries: 0,
          totalPages: 0,
          enterpriseTeams: [],
          businessSlug: 'github',
        }
      },
    })

    const routePayload = getStafftoolsBusinessTeamsListViewRoutePayload()
    render(<StafftoolsBusinessTeamsListView />, {
      routePayload,
    })

    const searchInput = screen.getByTestId('search-input')
    await userEvent.type(searchInput, 'z')

    act(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith(`/stafftools/enterprises/github/enterprise_teams?query=z&page=1`, {
        method: 'GET',
        headers: {Accept: 'application/json'},
      })
    })

    expect(screen.queryByTestId('link-to-1')).not.toBeInTheDocument()
    expect(screen.queryByTestId('link-to-2')).not.toBeInTheDocument()
    expect(screen.getByText(/no enterprise teams matched your search criteria/i)).toBeInTheDocument()
  })

  test('Renders blankslate message when there are no members', () => {
    const routePayload = getStafftoolsBusinessTeamsListViewRoutePayloadNoTeams()
    render(<StafftoolsBusinessTeamsListView />, {
      routePayload,
    })

    expect(screen.getByText(/no enterprise teams are in this enterprise/i)).toBeInTheDocument()
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
            businessSlug: 'github',
            enterpriseTeams: [
              {
                id: 3,
                name: 'another',
                externalGroupCount: 0,
                memberCount: 1,
                organizationSelectionType: 'disabled',
              },
            ],
          }
        },
      })

      const routePayload = getStafftoolsBusinessTeamsListViewRoutePayload()
      render(<StafftoolsBusinessTeamsListView />, {
        routePayload,
      })

      const nextPageLink = screen.getByText('Next', {selector: 'a'})
      await userEvent.click(nextPageLink)

      act(() => {
        expect(mockVerifiedFetch).toHaveBeenCalledWith(`/stafftools/enterprises/github/enterprise_teams?page=2`, {
          method: 'GET',
          headers: {Accept: 'application/json'},
        })
      })
      expect(screen.getByTestId('link-to-3').textContent).toBe('another')
      expect(screen.queryByTestId('link-to-1')).not.toBeInTheDocument()
      expect(screen.queryByTestId('link-to-2')).not.toBeInTheDocument()
    })
  })
})
