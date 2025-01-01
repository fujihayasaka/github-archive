import {useMemo, useState} from 'react'

import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {clsx} from 'clsx'
import {
  compareChecks,
  countChecksByGroup,
  extractChecksAnalyticsMetadata,
  groupChecks,
} from '../../../helpers/status-check-helpers'
import type {MergeBoxUserPreferences} from '../../../page-data/payloads/merge-box'
import type {CheckStateRollup, StatusCheck} from '../../../page-data/payloads/status-checks'
import {ChecksGroup} from './ChecksGroup'
import styles from './ExpandedChecks.module.css'
import {StatusCheckRow} from './StatusCheckRow'

const CHECKS_LIST_GROUPINGS = {
  FAILURE: ['CANCELLED', 'ERROR', 'FAILURE', 'STALE', 'STARTUP_FAILURE', 'TIMED_OUT'],
  PENDING: ['ACTION_REQUIRED', 'EXPECTED', 'PENDING', 'QUEUED', 'REQUESTED', 'WAITING', '_UNKNOWN_VALUE'],
  IN_PROGRESS: ['IN_PROGRESS'],
  SKIPPED: ['SKIPPED'],
  NEUTRAL: ['NEUTRAL'],
  SUCCESS: ['SUCCESS', 'COMPLETED'],
}

interface Props {
  pullRequestId: string
  statusChecks: StatusCheck[]
  statusRollupSummary: CheckStateRollup[]
  mergeBoxUserPreferences: MergeBoxUserPreferences | null
}

/**
 * Displays the list of expanded checks
 */
export function ExpandedChecksList({pullRequestId, statusChecks, statusRollupSummary, mergeBoxUserPreferences}: Props) {
  const [userPreferences, setUserPreferences] = useState<MergeBoxUserPreferences | null>(
    mergeBoxUserPreferences || null,
  )

  const sortedChecksOrStatuses = useMemo(() => statusChecks.sort(compareChecks), [statusChecks])
  const countsByGroup = countChecksByGroup(statusRollupSummary, CHECKS_LIST_GROUPINGS, userPreferences)
  const checksByGroup = groupChecks(
    sortedChecksOrStatuses,
    CHECKS_LIST_GROUPINGS,
    check => check.state,
    userPreferences,
  )

  const useSmarterChecksKeys = useFeatureFlag('mergebox_smarter_checks_keys')
  const mergeboxPaintContainment = useFeatureFlag('mergebox_paint_containment')
  const limitAnimatedChecks = useFeatureFlag('mergebox_limit_animated_checks')

  const reserveSpaceForRequiredBadge = statusChecks.some(check => check.isRequired)
  const reserveSpaceForActionBar = statusChecks.some(check => check.copilotCheckRunFailureContext || !!check.targetUrl)

  // count how many groups actually have items
  const groupsWithItemsCount = Object.entries(countsByGroup).reduce<number>(
    (groupsWithItems, [, count]) => (count > 0 ? groupsWithItems + 1 : groupsWithItems),
    0,
  )

  const allChecksSameState =
    statusChecks.length > 0 ? statusChecks.every(check => check.state === statusChecks[0]?.state) : false

  const isToggleVisible =
    groupsWithItemsCount > 1 || (userPreferences?.statusChecksGrouping === 'ungrouped' && !allChecksSameState)

  return (
    <div className={clsx(styles.checksContainer, {[styles.containPaint]: mergeboxPaintContainment})}>
      {Object.entries(countsByGroup)
        .filter(([, count]) => count > 0)
        .map(([groupStatus, count], index) => {
          const isFirstGroup = index === 0
          return (
            <ChecksGroup
              key={groupStatus}
              count={count}
              groupStatus={groupStatus}
              isToggleVisible={isToggleVisible}
              pullRequestId={pullRequestId}
              analyticsMetadata={extractChecksAnalyticsMetadata(statusRollupSummary)}
              setUserPreferences={setUserPreferences}
              userPreferences={userPreferences}
              showSettingsIcon={userPreferences && isFirstGroup}
            >
              {checksByGroup[groupStatus]?.map(checkOrStatus => {
                if (!checkOrStatus) return null

                const key = useSmarterChecksKeys
                  ? `${checkOrStatus.displayName}-${checkOrStatus.state}-${checkOrStatus.targetUrl}-${checkOrStatus.stateChangedAt}`
                  : crypto.randomUUID()

                return (
                  <StatusCheckRow
                    key={key}
                    {...checkOrStatus}
                    shouldAnimate={(limitAnimatedChecks && count < 50) || !limitAnimatedChecks}
                    reserveSpaceForActionBar={reserveSpaceForActionBar}
                    reserveSpaceForRequiredBadge={reserveSpaceForRequiredBadge}
                  />
                )
              })}
            </ChecksGroup>
          )
        })}
    </div>
  )
}
