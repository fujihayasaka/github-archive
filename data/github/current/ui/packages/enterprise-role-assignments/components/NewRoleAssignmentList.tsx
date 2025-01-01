import {testIdProps} from '@github-ui/test-id-props'
import {NoteIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {NewRoleAssignmentListItem} from './NewRoleAssignmentListItem'
import styles from './NewRoleAssignmentList.module.css'
import type {Role, AssigneeType, EnterpriseOrg} from '../enterprise-role-assignments-types'
import {esmStatus, isEsm} from '../utils/role-utils'

export interface NewRoleAssignmentListProps {
  roles: Role[]
  assigneeType: AssigneeType | null
  selectedRoleId: number | null
  enterpriseOrgs?: EnterpriseOrg[]
  enterpriseTeamOrgAssignmentLimitExceeded?: boolean
  onSelectCallback: (roleId: number) => void
}

export function NewRoleAssignmentList({
  roles,
  assigneeType,
  selectedRoleId,
  enterpriseOrgs,
  enterpriseTeamOrgAssignmentLimitExceeded,
  onSelectCallback,
}: NewRoleAssignmentListProps) {
  return (
    <div {...testIdProps('role-assignment-list')}>
      <div className={styles.rolesListContainer}>
        <ActionList.GroupHeading className={styles.rolesListHeading} variant="filled" as="h4">
          {pluralize('role', roles.length)}
        </ActionList.GroupHeading>
        <ActionList role="menu" variant="full" selectionVariant="single" showDividers>
          {roles.length === 0 && (
            <div {...testIdProps('empty-roles-content')} className={styles.emptyRolesContent}>
              <NoteIcon className={styles.emptyRolesIcon} size="medium" />
              <p className={styles.emptyRolesText}>You do not have any roles yet</p>
            </div>
          )}

          {roles.map(role => (
            <NewRoleAssignmentListItem
              key={role.id}
              role={role}
              roleStatus={isEsm(role) ? esmStatus(assigneeType, !!enterpriseTeamOrgAssignmentLimitExceeded) : null}
              enterpriseOrgs={enterpriseOrgs}
              selected={selectedRoleId === role.id}
              onSelectCallback={onSelectCallback}
            />
          ))}
        </ActionList>
      </div>
    </div>
  )
}

function pluralize(word: string, count: number) {
  return `${count} ${word}${count === 1 ? '' : 's'}`
}
