import {Spinner, Label} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {SkeletonAvatar} from '@primer/react/experimental'
import {memo} from 'react'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ArrowRightIcon} from '@primer/octicons-react'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {clsx} from 'clsx'

import {STATUS_CHECK_CONFIGS} from '../../../helpers/status-check-helpers'
import type {StatusCheck} from '../../../page-data/payloads/status-checks'
import styles from './StatusCheckRow.module.css'
import sectionListItemStyles from '../common/SectionListItem.module.css'

function StatusIcon({iconColor, icon}: {iconColor: string; icon: React.ElementType}) {
  return (
    <Octicon
      icon={icon}
      sx={{
        color: iconColor,
      }}
    />
  )
}

function CheckSpinner() {
  return (
    <div className="position-relative d-flex color-fg-attention">
      <Spinner size="small" />
      <div className={styles.spinnerWrapper}>
        <div className={styles.spinnerInner} />
      </div>
    </div>
  )
}

/**
 * Renders either a check run or a status context in the DOM as link.
 */
export const StatusCheckRow = memo(function StatusCheckRow({
  avatarUrl,
  displayName,
  description,
  state,
  targetUrl,
  isRequired,
}: Partial<StatusCheck>) {
  const statusState = STATUS_CHECK_CONFIGS[state as keyof typeof STATUS_CHECK_CONFIGS]

  return (
    <ListItem title={<div />} className={sectionListItemStyles.listItem}>
      <ListItemLeadingContent>
        <ListItemLeadingVisual className={clsx(styles.leadingVisual, 'mt-2')}>
          {state === 'IN_PROGRESS' ? (
            <CheckSpinner />
          ) : (
            <StatusIcon icon={statusState.icon} iconColor={statusState.iconColor} />
          )}
          {avatarUrl ? (
            <GitHubAvatar alt={displayName} size={20} square src={avatarUrl} className="flex-shrink-0 ml-2 mr-2" />
          ) : (
            <SkeletonAvatar size={20} square className="flex-shrink-0 ml-2 mr-2" />
          )}
        </ListItemLeadingVisual>
      </ListItemLeadingContent>
      <ListItemTitle
        containerClassName={styles.title}
        headingClassName={styles.titleHeader}
        value={displayName ?? ''}
        href={targetUrl ?? undefined}
      >
        <span className={styles.titleDescription}>{description}</span>
      </ListItemTitle>
      <ListItemMetadata>
        {isRequired && (
          <div className={clsx(styles.requiredLabel, 'flex-shrink-0 fgColor-default')}>
            <Label>Required</Label>
          </div>
        )}
        {targetUrl && (
          <>
            <a aria-label="Go to Checks detail" href={targetUrl} className={styles.buttonAnchorWrapper}>
              <ArrowRightIcon className={styles.button} />
            </a>
          </>
        )}
      </ListItemMetadata>
    </ListItem>
  )
})
