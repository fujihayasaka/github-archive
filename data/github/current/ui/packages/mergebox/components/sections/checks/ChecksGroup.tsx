import {ListView} from '@github-ui/list-view'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useAnalytics} from '@github-ui/use-analytics'
import useSafeState from '@github-ui/use-safe-state'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import {GearIcon, StopIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, Flash, IconButton} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {type PropsWithChildren, useId} from 'react'
import type {STATUS_CHECK_ACCESSIBLE_NAMES} from '../../../helpers/status-check-helpers'
import {getAccessibleStatusText} from '../../../helpers/status-check-helpers'
import {useUpdateMergeBoxUserPreferenceMutation} from '../../../hooks/mutations/use-update-merge-box-user-preference'
import type {MergeBoxUserPreferences} from '../../../page-data/payloads/merge-box'
import {ExpandableGroupIcon} from '../common/ExpandableGroupIcon'
import styles from './ExpandedChecks.module.css'

export function ChecksGroup({
  children,
  count,
  groupStatus,
  isToggleVisible,
  analyticsMetadata,
  showSettingsIcon,
  setUserPreferences,
  pullRequestId,
  userPreferences,
}: PropsWithChildren<{
  count: number
  groupStatus: string
  analyticsMetadata: {statusCheckCounts: string}
  isToggleVisible?: boolean
  showSettingsIcon: boolean | null
  setUserPreferences?: (userPreferences: MergeBoxUserPreferences) => void
  pullRequestId: string
  userPreferences: MergeBoxUserPreferences | null
}>) {
  function getGroupText(groupStatusText: string): string {
    if (userPreferences?.statusChecksGrouping === 'ungrouped') {
      return count > 1 ? `${count} checks` : `${count} check`
    }

    return `${count} ${groupStatusText} check${count > 1 ? 's' : ''}`
  }

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
  const groupText = getGroupText(groupStatusText)

  const shouldRenderChecks = !showListToggle || isExpanded

  const [errorMessage, setErrorMessage] = useSafeState<string | null>(null)

  const {mutate: updateMergeBoxUserPreference} = useUpdateMergeBoxUserPreferenceMutation({
    onError: (e: Error) => {
      setErrorMessage(e.message)
    },
  })

  return (
    <div>
      {showListToggle && (
        <div className={styles.groupHeader}>
          {userPreferences?.statusChecksGrouping === 'ungrouped' ? (
            <span className={clsx(styles.totalChecksCountText, 'pl-2 text-semibold f6')}> {groupText} </span>
          ) : (
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
          {showSettingsIcon && setUserPreferences && (
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton
                  icon={GearIcon}
                  variant="invisible"
                  aria-label="Checks settings"
                  className={styles.checkSettingsButton}
                />
              </ActionMenu.Anchor>
              <ActionMenu.Overlay width="auto">
                <ActionList selectionVariant="single">
                  <ActionList.Item
                    onSelect={() => {
                      if (userPreferences?.statusChecksGrouping !== 'grouped_by_status') {
                        updateMergeBoxUserPreference({
                          preferenceName: 'status_checks_grouping_preference',
                          preference: 'grouped_by_status',
                        })
                        setUserPreferences({...userPreferences, statusChecksGrouping: 'grouped_by_status'})
                      }
                    }}
                    selected={userPreferences?.statusChecksGrouping === 'grouped_by_status'}
                  >
                    Group by status
                  </ActionList.Item>
                  <ActionList.Item
                    onSelect={() => {
                      if (userPreferences?.statusChecksGrouping !== 'ungrouped') {
                        updateMergeBoxUserPreference({
                          preferenceName: 'status_checks_grouping_preference',
                          preference: 'ungrouped',
                        })
                        setUserPreferences({...userPreferences, statusChecksGrouping: 'ungrouped'})
                      }
                    }}
                    selected={userPreferences?.statusChecksGrouping === 'ungrouped'}
                  >
                    No grouping
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          )}
        </div>
      )}
      {errorMessage && (
        <Flash sx={{mb: 3}} variant="danger">
          <Octicon sx={{mr: 2}} icon={StopIcon} />
          {errorMessage}
        </Flash>
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
