import {IdBadgeIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import {testIdProps} from '@github-ui/test-id-props'
import {useRoutingContext} from '../RoutingProvider'

export interface RoleAssignmentsBlankslateProps {
  roleType: string
  actorTypePlural: string
  hasWriteAccess: boolean
  usePrimaryAction?: boolean
}

export function RoleAssignmentsBlankslate({
  roleType,
  actorTypePlural,
  hasWriteAccess,
  usePrimaryAction = false,
}: RoleAssignmentsBlankslateProps) {
  const {newRoleAssignmentPath} = useRoutingContext()
  const capitalizedRoleType = roleType.charAt(0).toUpperCase() + roleType.slice(1)

  let action = null
  if (hasWriteAccess) {
    if (usePrimaryAction) {
      action = <Blankslate.PrimaryAction href={newRoleAssignmentPath()}>Assign role</Blankslate.PrimaryAction>
    } else {
      action = <Blankslate.SecondaryAction href={newRoleAssignmentPath()}>Assign role</Blankslate.SecondaryAction>
    }
  }

  return (
    <div {...testIdProps('role-assignments-blankstate')}>
      <Blankslate spacious>
        <Blankslate.Visual>
          <IdBadgeIcon size={24} />
        </Blankslate.Visual>
        <Blankslate.Heading>No {roleType} roles assigned</Blankslate.Heading>
        <Blankslate.Description>
          {capitalizedRoleType} roles have not been assigned to any {actorTypePlural}.
        </Blankslate.Description>
        {action}
      </Blankslate>
    </div>
  )
}
