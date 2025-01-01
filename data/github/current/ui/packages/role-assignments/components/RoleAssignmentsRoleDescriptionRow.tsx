import {testIdProps} from '@github-ui/test-id-props'
import {InheritedRoleOverlayButton} from './InheritedRoleOverlayButton'
import {NestingTableRow} from './NestingTable/NestingTableRow'
import {RemoveRoleAssignmentButton} from './RemoveRoleAssignmentButton'
import type {Actor, RoleAssignment} from '../types/ActorRoleAssignment'
import {createAssignmentSourcesList, getIndirectAssignmentSourceElements} from '../utils/AssignmentSourcesUtils'
import getRoleIcon from '../utils/RoleIconMap'

interface RoleAssignmentsRoleDescriptionRowProps {
  actor: Actor
  roleAssignment: RoleAssignment
  hasWriteAccess: boolean
  canViewEnterpriseTeams: boolean
}

export function RoleAssignmentsRoleDescriptionRow({
  actor,
  roleAssignment,
  hasWriteAccess,
  canViewEnterpriseTeams,
}: RoleAssignmentsRoleDescriptionRowProps) {
  const assignmentSourcesCount = roleAssignment.indirect_assignments.length + (roleAssignment.directly_assigned ? 1 : 0)

  let assignedVia = 'Assigned via '
  if (assignmentSourcesCount > 1) {
    assignedVia += `${assignmentSourcesCount} sources: `
  }

  // Create list of assignment sources to display
  const assignmentSources = []

  if (roleAssignment.directly_assigned) {
    assignmentSources.push(
      <span key="direct" className="fgColor-default">
        direct assignment
      </span>,
    )
  }

  assignmentSources.push(
    ...getIndirectAssignmentSourceElements(
      roleAssignment.role.id,
      roleAssignment.indirect_assignments,
      true,
      canViewEnterpriseTeams,
    ),
  )

  const sources = createAssignmentSourcesList(assignmentSources)

  const trailingItems = []

  if (hasWriteAccess) {
    if (roleAssignment.directly_assigned) {
      trailingItems.push(
        <RemoveRoleAssignmentButton
          key="remove-assignment-button"
          actor={actor}
          roleAssignment={roleAssignment}
          canViewEnterpriseTeams={canViewEnterpriseTeams}
        />,
      )
    } else {
      trailingItems.push(<InheritedRoleOverlayButton key="inherited-role-overlay" />)
    }
  }

  return (
    <NestingTableRow
      leadingIcon={
        <span className="fgColor-muted" {...testIdProps('role-icon')}>
          {getRoleIcon(roleAssignment.role.octicon)}
        </span>
      }
      title={roleAssignment.role.name}
      description={
        <span>
          <div>{roleAssignment.role.description}</div>
          <div {...testIdProps('role-assignment-sources')}>
            {assignedVia} {sources}.
          </div>
        </span>
      }
      trailingItems={trailingItems}
      key={`actor-${actor.id}`}
    />
  )
}
