import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {StafftoolsBusinessTeamsItemView} from '../../routes/stafftools/StafftoolsBusinessTeamsItemView'
import {
  getStafftoolsBusinessTeamsItemViewRoutePayload,
  getStafftoolsBusinessTeamsItemViewRoutePayloadEnterpriseTeamMembersManagementFFEnabled,
} from '../../test-utils/mock-data'

describe('EnterpriseTeamsItemView', () => {
  test('Renders the enterprise team list', () => {
    const routePayload = getStafftoolsBusinessTeamsItemViewRoutePayload()
    render(<StafftoolsBusinessTeamsItemView />, {
      routePayload,
    })
    expect(screen.getByTestId('team-id').textContent).toBe('1')
    expect(screen.getByTestId('team-name').textContent).toBe('justice league')
    expect(screen.getByTestId('team-slug').textContent).toBe('justice-league')
    expect(screen.getByTestId('team-group-count').textContent).toBe('0 external groups')
    expect(screen.getByTestId('direct-member-count').textContent).toBe('2 members')
    expect(screen.getByTestId('external-member-count').textContent).toBe('0 external group members')
    expect(screen.getByTestId('database-link')).toHaveAttribute('href', '/enterprise_teams/1/database')
    expect(screen.getByTestId('members-link')).toHaveAttribute('href', '/enterprise_teams/1/members')
  })

  test('Renders the enterprise team list for idp linked team ff enabled', () => {
    const routePayload = getStafftoolsBusinessTeamsItemViewRoutePayloadEnterpriseTeamMembersManagementFFEnabled()
    render(<StafftoolsBusinessTeamsItemView />, {
      routePayload,
    })
    expect(screen.getByTestId('team-id').textContent).toBe('1')
    expect(screen.getByTestId('team-name').textContent).toBe('justice league')
    expect(screen.getByTestId('team-slug').textContent).toBe('justice-league')
    expect(screen.getByTestId('external-group-link').textContent).toBe('justice-league-external-group')
    expect(screen.getByTestId('external-group-members-count').textContent).toBe('2 members')
    expect(screen.getByTestId('external-group-sync-status').textContent).toBe('Synced')
    expect(screen.getByTestId('members-link').textContent).toBe('2 members')
    expect(screen.getByTestId('database-link')).toHaveAttribute('href', '/enterprise_teams/1/database')
    expect(screen.getByTestId('members-link')).toHaveAttribute('href', '/enterprise_teams/1/members')
  })

  test('Renders the enterprise team list for manually managed team ff enabled', () => {
    const routePayload = getStafftoolsBusinessTeamsItemViewRoutePayload()
    render(<StafftoolsBusinessTeamsItemView />, {
      routePayload,
    })
    expect(screen.getByTestId('team-id').textContent).toBe('1')
    expect(screen.getByTestId('team-name').textContent).toBe('justice league')
    expect(screen.getByTestId('team-slug').textContent).toBe('justice-league')
    expect(screen.queryByTestId('external-group-link')).not.toBeInTheDocument()
    expect(screen.queryByTestId('external-group-members-count')).not.toBeInTheDocument()
    expect(screen.queryByTestId('external-group-sync-status')).not.toBeInTheDocument()
    expect(screen.getByTestId('members-link').textContent).toBe('2 members')
    expect(screen.getByTestId('database-link')).toHaveAttribute('href', '/enterprise_teams/1/database')
    expect(screen.getByTestId('members-link')).toHaveAttribute('href', '/enterprise_teams/1/members')
  })

  test('Renders the assigned organizations row when displayOrgsPage is true', () => {
    const routePayload = getStafftoolsBusinessTeamsItemViewRoutePayload()
    render(<StafftoolsBusinessTeamsItemView />, {
      routePayload,
    })

    expect(screen.getByTestId('assigned-organizations-count').textContent).toBe('0 organizations')
    expect(screen.getByTestId('assigned-organizations-link')).toHaveAttribute(
      'href',
      '/stafftools/enterprises/your-business-slug/enterprise_teams/1/organizations',
    )
  })

  test('Do not render the assigned organizations row when displayOrgsPage is false', () => {
    const routePayload = getStafftoolsBusinessTeamsItemViewRoutePayload()
    routePayload.enterpriseTeam.displayOrgsPage = false

    render(<StafftoolsBusinessTeamsItemView />, {
      routePayload,
    })

    expect(screen.queryByTestId('assigned-organizations-count')).not.toBeInTheDocument()
  })
})
