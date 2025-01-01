import {testIdProps} from '@github-ui/test-id-props'
import {XIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useState, useRef} from 'react'
import type {Actor, RoleAssignment} from '../types/ActorRoleAssignment'
import {RemoveRoleAssignmentDialog} from './RemoveRoleAssignmentDialog'

export function RemoveRoleAssignmentButton({
  actor,
  roleAssignment,
  canViewEnterpriseTeams,
}: {
  actor: Actor
  roleAssignment: RoleAssignment
  canViewEnterpriseTeams: boolean
}) {
  const [isOpen, setIsOpen] = useState(false)

  const buttonRef = useRef<HTMLButtonElement>(null)

  return (
    <>
      <IconButton
        ref={buttonRef}
        icon={XIcon}
        variant="invisible"
        aria-label="Remove role assignment"
        onClick={() => setIsOpen(!isOpen)}
        {...testIdProps('remove-assignment-button')}
      />
      {isOpen && (
        <RemoveRoleAssignmentDialog
          actor={actor}
          roleId={roleAssignment.role.id}
          roleName={roleAssignment.role.name}
          indirectAssignments={roleAssignment.indirect_assignments}
          setOpen={setIsOpen}
          returnFocusRef={buttonRef}
          canViewEnterpriseTeams={canViewEnterpriseTeams}
        />
      )}
    </>
  )
}
