import {GitHubAvatar} from '@github-ui/github-avatar'
import {ActorType, type ActorRoleAssignment} from '../types/ActorRoleAssignment'
import {NestingTableRow} from './NestingTable/NestingTableRow'
import {Text, CounterLabel} from '@primer/react'
import {RoleAssignmentsRoleDescriptionRow} from './RoleAssignmentsRoleDescriptionRow'
import {testIdProps} from '@github-ui/test-id-props'

export function RoleAssignmentsTableRow({
  assignment,
  hasWriteAccess,
  showEnterpriseTeamLabel = false,
}: {
  assignment: ActorRoleAssignment
  hasWriteAccess: boolean
  showEnterpriseTeamLabel?: boolean
}) {
  return (
    <NestingTableRow
      leadingIcon={
        <GitHubAvatar
          size={16}
          alt={assignment.actor.name}
          src={assignment.actor.avatar_url}
          // circle if actor is a user, square if the actor is a team
          square={assignment.actor.type !== ActorType.User}
        />
      }
      title={assignment.actor.name}
      titleLabel={
        showEnterpriseTeamLabel && assignment.actor.type === ActorType.EnterpriseTeam ? 'Enterprise team' : ''
      }
      description={assignment.actor.description}
      trailingItems={[
        <span key="roles-count" className="d-flex flex-items-center gap-2" {...testIdProps('roles-assigned-count')}>
          <Text size="small" weight="semibold" className="fgColor-muted">
            Roles assigned
          </Text>
          <CounterLabel scheme="secondary">{assignment.role_assignments.length}</CounterLabel>
        </span>,
      ]}
      subItems={assignment.role_assignments.map(roleAssignment => (
        <RoleAssignmentsRoleDescriptionRow
          actor={assignment.actor}
          roleAssignment={roleAssignment}
          hasWriteAccess={hasWriteAccess}
          key={roleAssignment.role.id}
        />
      ))}
    />
  )
}
