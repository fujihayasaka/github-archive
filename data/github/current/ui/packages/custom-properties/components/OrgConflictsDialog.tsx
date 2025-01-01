import type {OrgConflictUsage, PropertyNameOrgConflicts} from '@github-ui/custom-properties-types'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Banner, Dialog} from '@primer/react/experimental'
import {clsx} from 'clsx'
import type {RefObject} from 'react'

import {definitionTypeLabels} from '../helpers/definition-type-labels'
import styles from './OrgConflictsDialog.module.css'

export function OrgConflictsDialog({
  onClose,
  orgConflicts,
  title,
  displayMessage,
  returnFocusRef,
}: {
  onClose: () => void
  displayMessage: string
  title: string
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
    <Dialog
      width="large"
      footerButtons={[
        {
          content: 'Done',
          onClick: onClose,
        },
      ]}
      title={title}
      onClose={onClose}
      returnFocusRef={returnFocusRef}
    >
      <Banner className="mb-2" hideTitle variant="critical" title="Conflicts message">
        {fullDisplayMessage}
      </Banner>
      <p className={styles.orgConflictSubHeader}>Organizations with conflicting properties</p>
      <ul>
        {orgConflicts.usages.map(usage => (
          <OrgConflictRow key={usage.name} orgConflictUsage={usage} />
        ))}
      </ul>
    </Dialog>
  )
}

function OrgConflictRow({orgConflictUsage}: {orgConflictUsage: OrgConflictUsage}) {
  return (
    <li className={styles.orgConflictRow}>
      <div className={styles.avatarLabelGroup}>
        <GitHubAvatar className={clsx(styles.avatarIcon, 'd-inline-block')} square src={orgConflictUsage.avatarUrl} />
        <span className="text-semibold">{orgConflictUsage.name}</span>
      </div>
      <span className={styles.orgConflictPropertyTypeLabel}>{definitionTypeLabels[orgConflictUsage.propertyType]}</span>
    </li>
  )
}
