import type {OrgConflictUsage, PropertyNameOrgConflicts} from '@github-ui/custom-properties-types'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Button} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import type {RefObject} from 'react'

import {definitionTypeLabels} from '../helpers/definition-type-labels'
import styles from './OrgConflictsDialog.module.css'

export function OrgConflictsDialog({
  onClose,
  orgConflicts,
  displayMessage,
  returnFocusRef,
}: {
  onClose: () => void
  displayMessage: string
  orgConflicts: PropertyNameOrgConflicts
  returnFocusRef?: RefObject<HTMLElement>
}) {
  const {usages, totalUsageCount} = orgConflicts
  const displayedUsagesCount = usages.length

  const fullDisplayMessage = `${displayMessage}${
    displayedUsagesCount < totalUsageCount
      ? ` (showing ${displayedUsagesCount} out of a total ${totalUsageCount} conflicts)`
      : ''
  }.`

  return (
    <Dialog onClose={onClose} renderHeader={() => null} returnFocusRef={returnFocusRef}>
      <Dialog.Header>
        <h4>Conflicts</h4>
        <p className={styles.description}>{fullDisplayMessage}</p>
      </Dialog.Header>
      <Dialog.Body as="ul">
        {orgConflicts.usages.map(usage => (
          <OrgConflictRow key={usage.name} orgConflictUsage={usage} />
        ))}
      </Dialog.Body>
      <Dialog.Footer>
        <Button onClick={onClose}>Done</Button>
      </Dialog.Footer>
    </Dialog>
  )
}

function OrgConflictRow({orgConflictUsage}: {orgConflictUsage: OrgConflictUsage}) {
  return (
    <li className={styles.orgConflictRow}>
      <div className={styles.avatarLabelGroup}>
        <GitHubAvatar className={styles.avatarIcon} square src={orgConflictUsage.avatarUrl} />
        <span className={styles.avatarLabel}>{orgConflictUsage.name}</span>
      </div>
      <span className={styles.orgConflictPropertyTypeLabel}>{definitionTypeLabels[orgConflictUsage.propertyType]}</span>
    </li>
  )
}
