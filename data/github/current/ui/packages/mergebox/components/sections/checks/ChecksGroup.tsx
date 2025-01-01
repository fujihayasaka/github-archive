import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useAnalytics} from '@github-ui/use-analytics'
import {Button} from '@primer/react'
import {ListView} from '@github-ui/list-view'
import {type PropsWithChildren, useId} from 'react'
import type {STATUS_CHECK_ACCESSIBLE_NAMES} from '../../../helpers/status-check-helpers'
import {getAccessibleStatusText} from '../../../helpers/status-check-helpers'
import styles from './ExpandedChecks.module.css'
import {clsx} from 'clsx'
import {ExpandableGroupIcon} from '../common/ExpandableGroupIcon'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'

export function ChecksGroup({
  children,
  count,
  groupStatus,
  isToggleVisible,
  analyticsMetadata,
  pullRequestId,
}: PropsWithChildren<{
  count: number
  groupStatus: string
  analyticsMetadata: {statusCheckCounts: string}
  isToggleVisible?: boolean
  pullRequestId: string
}>) {
  const strictFocusZoneDisabled = useFeatureFlag('mergebox_disable_strict_focus_zone')
  const [isExpanded, setIsExpanded] = useSessionStorage<boolean>(
    `${pullRequestId}:checksGroup:${groupStatus}Expanded`,
    true,
  )
  const {sendAnalyticsEvent} = useAnalytics()
  const groupStatusText = getAccessibleStatusText(groupStatus as keyof typeof STATUS_CHECK_ACCESSIBLE_NAMES)
  const groupContentId = useId()
  const showListToggle = isToggleVisible
  const showChecksList = isExpanded || !isToggleVisible
  const groupText = `${count} ${groupStatusText} check${count > 1 ? 's' : ''}`
  const shouldRenderChecks = !showListToggle || isExpanded

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
      {shouldRenderChecks && (
        <div
          className={clsx(styles.expandableWrapper, showChecksList && styles.isExpanded)}
          id={groupContentId}
          aria-label={`${groupStatusText} checks`}
          role="group"
        >
          <div className={styles.expandableListView}>
            <ListView
              title={`${groupStatusText} checks`}
              titleHeaderTag="h3"
              strictFocusZone={!strictFocusZoneDisabled}
            >
              {children}
            </ListView>
          </div>
        </div>
      )}
    </div>
  )
}
