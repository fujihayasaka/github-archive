import {Spinner, Label, RelativeTime} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {SkeletonAvatar} from '@primer/react/experimental'
import {memo, useEffect, useRef, useState} from 'react'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {clsx} from 'clsx'

import {STATUS_CHECK_CONFIGS} from '../../../helpers/status-check-helpers'
import type {StatusCheck} from '../../../page-data/payloads/status-checks'
import styles from './StatusCheckRow.module.css'
import sectionListItemStyles from '../common/SectionListItem.module.css'
import {StatusCheckRowActionBar} from './StatusCheckRowActionBar'

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

function additionalInformation({
  state,
  stateChangedAt,
  additionalContext,
}: {
  state: StatusCheck['state'] | undefined
  stateChangedAt: StatusCheck['stateChangedAt'] | undefined
  additionalContext: StatusCheck['additionalContext'] | undefined
}) {
  switch (state) {
    case 'IN_PROGRESS': {
      return (
        <span>
          Started <RelativeTime datetime={stateChangedAt} />
        </span>
      )
    }
    case 'SKIPPED': {
      return (
        <span>
          Skipped <RelativeTime datetime={stateChangedAt} />
        </span>
      )
    }
    case 'QUEUED': {
      return <span>Queued</span>
    }
    default:
      return <span>{additionalContext}</span>
  }
}

/**
 * Renders either a check run or a status context in the DOM as link.
 */
export const StatusCheckRow = memo(function StatusCheckRow({
  additionalContext,
  avatarUrl,
  copilotCheckRunFailureContext,
  description,
  displayName,
  state,
  stateChangedAt,
  targetUrl,
  isRequired,
  reserveSpaceForRequiredBadge,
  reserveSpaceForActionBar,
}: Partial<StatusCheck> & {reserveSpaceForRequiredBadge?: boolean; reserveSpaceForActionBar?: boolean}) {
  const statusState = STATUS_CHECK_CONFIGS[state as keyof typeof STATUS_CHECK_CONFIGS]
  const listItemAriaLabel = `${displayName} ${
    additionalContext ? additionalContext.charAt(0).toLowerCase() + additionalContext.slice(1) : ''
  }`
  const requiredBadgeNoCopilotCheckRunFailureContext = reserveSpaceForRequiredBadge && !reserveSpaceForActionBar

  const [isTruncated, setIsTruncated] = useState(false)
  const titleRef = useRef<HTMLHeadingElement>(null)
  const titleContainerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handleResize = () => {
      if (titleRef.current && titleContainerRef.current) {
        const parentOffsetWidth = (titleContainerRef.current as HTMLElement).offsetWidth
        const childOffsetWidth = (titleRef.current as HTMLElement).offsetWidth

        setIsTruncated(childOffsetWidth + 31 > parentOffsetWidth)
      }
    }

    const resizeObserver = new ResizeObserver(handleResize)

    if (titleContainerRef.current) {
      resizeObserver.observe(titleContainerRef.current)
    }

    return () => {
      resizeObserver.disconnect()
    }
  }, [displayName])

  return (
    <ListItem
      title={<div />}
      aria-label={listItemAriaLabel}
      className={clsx(sectionListItemStyles.listItem)}
      secondaryActions={
        reserveSpaceForActionBar ? (
          <StatusCheckRowActionBar
            copilotCheckRunFailureContext={copilotCheckRunFailureContext}
            targetUrl={targetUrl}
          />
        ) : (
          <></>
        )
      }
    >
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
        tooltip={isTruncated ? `${displayName} ${additionalContext} ${description}` : undefined}
        headingRef={titleRef}
        headerContainerRef={titleContainerRef}
      >
        <span
          className={clsx(styles.titleDescription, (state === 'IN_PROGRESS' || state === 'QUEUED') && 'text-italic')}
        >
          {additionalInformation({state, stateChangedAt, additionalContext})} {description && `— ${description}`}
        </span>
      </ListItemTitle>
      {reserveSpaceForRequiredBadge ? (
        <ListItemMetadata>
          {isRequired && (
            <div
              className={clsx(
                styles.requiredLabel,
                'flex-shrink-0 fgColor-default',
                requiredBadgeNoCopilotCheckRunFailureContext && 'pr-3',
              )}
            >
              <Label>Required</Label>
            </div>
          )}
        </ListItemMetadata>
      ) : (
        // Triggers overflow earlier to show ellipsis for long descriptions
        <div className="px-5" />
      )}
    </ListItem>
  )
})
