import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {StafftoolsBusinessTeamsItemView} from '../../routes/stafftools/StafftoolsBusinessTeamsItemView'
import {getStafftoolsBusinessTeamsItemViewRoutePayload} from '../../test-utils/mock-data'

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
})
