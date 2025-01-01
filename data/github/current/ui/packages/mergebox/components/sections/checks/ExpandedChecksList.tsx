import {useMemo} from 'react'

import {
  compareChecks,
  countChecksByGroup,
  groupChecks,
  extractChecksAnalyticsMetadata,
} from '../../../helpers/status-check-helpers'
import styles from './ExpandedChecks.module.css'
import {ChecksGroup} from './ChecksGroup'
import {StatusCheckRow} from './StatusCheckRow'
import type {CheckStateRollup, StatusCheck} from '../../../page-data/payloads/status-checks'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

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
}

/**
 * Displays the list of expanded checks
 */
export function ExpandedChecksList({pullRequestId, statusChecks, statusRollupSummary}: Props) {
  const sortedChecksOrStatuses = useMemo(() => statusChecks.sort(compareChecks), [statusChecks])
  const countsByGroup = countChecksByGroup(statusRollupSummary, CHECKS_LIST_GROUPINGS)
  const checksByGroup = groupChecks(sortedChecksOrStatuses, CHECKS_LIST_GROUPINGS, check => check.state)

  const useSmarterChecksKeys = useFeatureFlag('mergebox_smarter_checks_keys')

  const reserveSpaceForRequiredBadge = statusChecks.some(check => check.isRequired)
  const reserveSpaceForActionBar = statusChecks.some(check => check.copilotCheckRunFailureContext || !!check.targetUrl)

  // count how many groups actually have items
  const groupsWithItemsCount = Object.entries(countsByGroup).reduce<number>(
    (groupsWithItems, [, count]) => (count > 0 ? groupsWithItems + 1 : groupsWithItems),
    0,
  )

  return (
    <div className={styles.checksContainer}>
      {Object.entries(countsByGroup).map(([groupStatus, count]) => {
        if (count === 0) return null

        const isToggleVisible = groupsWithItemsCount > 1
        return (
          <ChecksGroup
            key={groupStatus}
            count={count}
            groupStatus={groupStatus}
            isToggleVisible={isToggleVisible}
            pullRequestId={pullRequestId}
            analyticsMetadata={extractChecksAnalyticsMetadata(statusRollupSummary)}
          >
            {checksByGroup[groupStatus]?.map(checkOrStatus => {
              if (!checkOrStatus) return null

              const key = useSmarterChecksKeys
                ? `${checkOrStatus.displayName}-${checkOrStatus.state}-${checkOrStatus.targetUrl}`
                : crypto.randomUUID()

              return (
                <StatusCheckRow
                  key={key}
                  {...checkOrStatus}
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
