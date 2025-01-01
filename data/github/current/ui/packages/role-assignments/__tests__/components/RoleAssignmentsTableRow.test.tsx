import {render, screen} from '@testing-library/react'
import {RoleAssignmentsTableRow} from '../../components/RoleAssignmentsTableRow'
import {ActorType} from '../../types/ActorRoleAssignment'
import {mockAssignment} from '../../test-utils/mock-data'

test('Renders RoleAssignmentTableRow', () => {
  render(<RoleAssignmentsTableRow assignment={mockAssignment} hasWriteAccess canViewEnterpriseTeams />)

  // title and description
  expect(screen.getByText('Mona Lisa')).toBeInTheDocument()
  expect(screen.getByText('monalisa')).toBeInTheDocument()

  // avatar
  const avatar = screen.getByAltText('Mona Lisa')
  expect(avatar).toBeInTheDocument()
  expect(avatar).toHaveAttribute('src', expect.stringContaining('monalisa'))

  // roles count
  const rolesCount = screen.getByTestId('roles-assigned-count')
  expect(rolesCount).toContainElement(screen.getByText('Roles assigned'))
  expect(rolesCount).toContainElement(screen.getByText('2'))
})

test('renders square avatar for non-user actor type', () => {
  const teamAssignment = {
    ...mockAssignment,
    actor: {
      ...mockAssignment.actor,
      type: ActorType.EnterpriseTeam,
    },
  }
  render(<RoleAssignmentsTableRow assignment={teamAssignment} hasWriteAccess canViewEnterpriseTeams />)
  const avatar = screen.getByAltText('Mona Lisa')
  expect(avatar).toHaveAttribute('data-square')
})

describe('enterprise team label', () => {
  const enterpriseTeamAssignment = {
    ...mockAssignment,
    actor: {
      ...mockAssignment.actor,
      type: ActorType.EnterpriseTeam,
    },
  }

  test('does not render title label for enterprise team by default', () => {
    render(<RoleAssignmentsTableRow assignment={enterpriseTeamAssignment} hasWriteAccess canViewEnterpriseTeams />)
    expect(screen.queryByTestId('title-label')).not.toBeInTheDocument()
  })

  test('does not render if showEnterpriseTeamLabel is true but actor is not an enterprise team', () => {
    const teamAssignment = {
      ...mockAssignment,
      actor: {
        ...mockAssignment.actor,
        type: ActorType.Team,
      },
    }
    render(<RoleAssignmentsTableRow assignment={teamAssignment} hasWriteAccess canViewEnterpriseTeams />)
    expect(screen.queryByTestId('title-label')).not.toBeInTheDocument()
  })

  test('renders title label for enterprise team when showEnterpriseTeamLabel is true and actor is an enterprise team', () => {
    render(
      <RoleAssignmentsTableRow
        assignment={enterpriseTeamAssignment}
        showEnterpriseTeamLabel
        hasWriteAccess
        canViewEnterpriseTeams
      />,
    )
    expect(screen.getByTestId('title-label')).toHaveTextContent('Enterprise team')
  })
})
