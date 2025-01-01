import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {RoleAssignmentsRoleDescriptionRow} from '../../components/RoleAssignmentsRoleDescriptionRow'
import {directRoleAssignment, indirectRoleAssignment, mockAssignment} from '../../test-utils/mock-data'

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {setBanner: jest.fn()}
  }),
}))

function expectTeamLink(element: HTMLElement, teamName: string, teamUrl: string) {
  const teamLink = within(element).getByRole('link', {name: teamName})
  expect(teamLink).toBeInTheDocument()
  expect(teamLink).toHaveAttribute('href', teamUrl)
}

test('Renders one source, direct assignment', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={directRoleAssignment}
      hasWriteAccess
    />,
  )
  expect(screen.getByText(directRoleAssignment.role.name)).toBeInTheDocument()
  expect(screen.getByText(directRoleAssignment.role.description)).toBeInTheDocument()

  const assignmentSources = screen.getByTestId('role-assignment-sources')
  expect(assignmentSources).toBeInTheDocument()
  expect(assignmentSources).toHaveTextContent(`Assigned via direct assignment.`)
})

test('Renders one source, indirect assignment', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={indirectRoleAssignment}
      hasWriteAccess
    />,
  )
  const team = indirectRoleAssignment.indirect_assignments[0]!

  const assignmentSources = screen.getByTestId('role-assignment-sources')
  expect(assignmentSources).toBeInTheDocument()
  expect(assignmentSources).toHaveTextContent(`Assigned via ${team.team_name} team.`)
  expectTeamLink(assignmentSources, team.team_name, team.team_url)
})

test('Renders two sources separated by and', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={{
        ...indirectRoleAssignment,
        directly_assigned: true,
      }}
      hasWriteAccess
    />,
  )
  const team = indirectRoleAssignment.indirect_assignments[0]!

  const assignmentSources = screen.getByTestId('role-assignment-sources')
  expect(assignmentSources).toBeInTheDocument()
  expect(assignmentSources).toHaveTextContent(`Assigned via 2 sources: direct assignment and ${team.team_name} team.`)
  expectTeamLink(assignmentSources, team.team_name, team.team_url)
})

test('Renders three sources separated by comma and and', () => {
  const roleAssignment = {
    ...indirectRoleAssignment,
    indirect_assignments: [
      {
        team_name: 'Team 1',
        team_url: '/team_1_url',
        type: 'BusinessTeam',
      },
      {
        team_name: 'Team 2',
        team_url: '/team_2_url',
        type: 'BusinessTeam',
      },
      {
        team_name: 'Team 3',
        team_url: '/team_3_url',
        type: 'BusinessTeam',
      },
    ],
  }

  render(
    <RoleAssignmentsRoleDescriptionRow actor={mockAssignment.actor} roleAssignment={roleAssignment} hasWriteAccess />,
  )
  const team1 = roleAssignment.indirect_assignments[0]!
  const team2 = roleAssignment.indirect_assignments[1]!
  const team3 = roleAssignment.indirect_assignments[2]!

  const assignmentSources = screen.getByTestId('role-assignment-sources')
  expect(assignmentSources).toBeInTheDocument()
  expect(assignmentSources).toHaveTextContent(
    `Assigned via 3 sources: ${team1.team_name} team, ${team2.team_name} team, and ${team3.team_name} team.`,
  )
  expectTeamLink(assignmentSources, team1.team_name, team1.team_url)
  expectTeamLink(assignmentSources, team2.team_name, team2.team_url)
  expectTeamLink(assignmentSources, team3.team_name, team3.team_url)
})

test('Renders role octicon', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={directRoleAssignment}
      hasWriteAccess
    />,
  )
  const roleIcon = screen.getByTestId('role-icon')
  expect(roleIcon).toBeInTheDocument()
  expect(roleIcon.childNodes[0]).toHaveClass(`octicon-${directRoleAssignment.role.octicon}`)
})

test('Renders remove assignment button when user has write access and role is directly assigned', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={directRoleAssignment}
      hasWriteAccess
    />,
  )
  expect(screen.getByTestId('remove-assignment-button')).toBeInTheDocument()
  expect(screen.queryByTestId('inherited-assignment-button')).not.toBeInTheDocument()
})

test('Renders inherited role assignment button when user has write access and role is indirectly assigned', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={indirectRoleAssignment}
      hasWriteAccess
    />,
  )
  expect(screen.getByTestId('inherited-assignment-button')).toBeInTheDocument()
  expect(screen.queryByTestId('remove-assignment-button')).not.toBeInTheDocument()
})

test('Does not render remove assignment button when user does not have write access and role is directly assigned', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={directRoleAssignment}
      hasWriteAccess={false}
    />,
  )
  expect(screen.queryByTestId('remove-assignment-button')).not.toBeInTheDocument()
})

test('Does not render inherited role assignment button when user does not have write access and role is indirectly assigned', () => {
  render(
    <RoleAssignmentsRoleDescriptionRow
      actor={mockAssignment.actor}
      roleAssignment={indirectRoleAssignment}
      hasWriteAccess={false}
    />,
  )
  expect(screen.queryByTestId('inherited-assignment-button')).not.toBeInTheDocument()
})
