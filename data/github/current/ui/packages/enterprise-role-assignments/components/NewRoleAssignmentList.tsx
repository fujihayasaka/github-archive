import {testIdProps} from '@github-ui/test-id-props'
import {NoteIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {type Role, NewRoleAssignmentListItem} from './NewRoleAssignmentListItem'
import styles from './NewRoleAssignmentList.module.css'

export interface NewRoleAssignmentListProps {
  roles: Role[]
  selectedRoleId: number | null
  onSelectCallback: (roleId: number) => void
}

export function NewRoleAssignmentList(props: NewRoleAssignmentListProps) {
  return (
    <div {...testIdProps('role-assignment-list')}>
      <div className={styles.rolesListContainer}>
        <ActionList.GroupHeading className={styles.rolesListHeading} variant="filled" as="h4">
          {pluralize('role', props.roles.length)}
        </ActionList.GroupHeading>
        <ActionList role="menu" variant="full" selectionVariant="single" showDividers>
          {props.roles.length === 0 && (
            <div {...testIdProps('empty-roles-content')} className={styles.emptyRolesContent}>
              <NoteIcon className={styles.emptyRolesIcon} size="medium" />
              <p className={styles.emptyRolesText}>You do not have any roles yet</p>
            </div>
          )}

          {props.roles.map(role => (
            <NewRoleAssignmentListItem
              key={role.id}
              role={role}
              selected={props.selectedRoleId === role.id}
              onSelectCallback={props.onSelectCallback}
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
