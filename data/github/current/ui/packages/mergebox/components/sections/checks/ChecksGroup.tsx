import {useAnalytics} from '@github-ui/use-analytics'
import {Button} from '@primer/react'
import {ListView} from '@github-ui/list-view'
import {type PropsWithChildren, useState, useId} from 'react'
import type {STATUS_CHECK_ACCESSIBLE_NAMES} from '../../../helpers/status-check-helpers'
import {getAccessibleStatusText} from '../../../helpers/status-check-helpers'
import styles from './ExpandedChecks.module.css'
import {clsx} from 'clsx'
import {ExpandableGroupIcon} from '../common/ExpandableGroupIcon'

export function ChecksGroup({
  children,
  count,
  groupStatus,
  isOpenByDefault = false,
  isToggleVisible,
  analyticsMetadata,
}: PropsWithChildren<{
  count: number
  groupStatus: string
  analyticsMetadata: {statusCheckCounts: Record<string, number>}
  isOpenByDefault: boolean
  isToggleVisible?: boolean
}>) {
  const [isExpanded, setIsExpanded] = useState(isOpenByDefault)
  const {sendAnalyticsEvent} = useAnalytics()
  const groupStatusText = getAccessibleStatusText(groupStatus as keyof typeof STATUS_CHECK_ACCESSIBLE_NAMES)
  const groupContentId = useId()
  const showListToggle = isToggleVisible
  const showChecksList = isExpanded || !isToggleVisible
  const groupText = `${count} ${groupStatusText} check${count > 1 ? 's' : ''}`

  return (
    <div>
      {showListToggle && (
        <Button
          aria-controls={groupContentId}
          aria-expanded={isExpanded}
          aria-label={isExpanded ? `Collapse ${groupText} group` : `Expand ${groupText} group`}
          className={styles.checksGroupHeadingButton}
          variant="invisible"
          size="small"
          trailingVisual={() => <ExpandableGroupIcon isExpanded={isExpanded} />}
          onClick={() => {
            const eventTarget = 'MERGEBOX_CHECKS_GROUP_TOGGLE_BUTTON'
            const eventType = isExpanded ? 'checks_group.collapse' : 'checks_group.expand'
            const eventMetadata = {...analyticsMetadata, group: groupStatus}
            sendAnalyticsEvent(eventType, eventTarget, eventMetadata)
            setIsExpanded(!isExpanded)
          }}
        >
          {groupText}
        </Button>
      )}
      <div
        className={clsx(styles.expandableWrapper, showChecksList && styles.isExpanded)}
        id={groupContentId}
        aria-label={`${groupStatusText} checks`}
        role="group"
      >
        <div className={styles.expandableListView}>
          <ListView title={`${groupStatusText} checks`}>{children}</ListView>
        </div>
      </div>
    </div>
  )
}
