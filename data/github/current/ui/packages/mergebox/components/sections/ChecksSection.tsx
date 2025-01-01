import {useAnalytics} from '@github-ui/use-analytics'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import {useId} from 'react'

import {announce} from '@github-ui/aria-live'
import useSafeState from '@github-ui/use-safe-state'
import {StopIcon} from '@primer/octicons-react'
import {Button, Flash, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type {ChecksSectionStatusType} from '../../helpers/merge-box-status-calculator/checks-section-status'
import {
  countChecksByGroup,
  extractChecksAnalyticsMetadata,
  getAccessibleStatusText,
  STATUS_CHECK_ACCESSIBLE_NAMES,
} from '../../helpers/status-check-helpers'
import {useRunActionRequiredWorkflows} from '../../hooks/mutations/use-run-action-required-workflows'
import {useStatusChecksLiveUpdates} from '../../hooks/use-status-checks-live-updates'
import {useSyncFavicon} from '../../hooks/use-sync-favicon'
import {useStatusChecksPageData} from '../../page-data/loaders/use-status-checks-page-data'
import type {MergeBoxUserPreferences} from '../../page-data/payloads/merge-box'
import type {
  CheckStateRollup,
  PendingWorkflowApprovalRollup,
  StatusCheck,
  StatusRollup,
} from '../../page-data/payloads/status-checks'
import {ExpandedChecksList} from './checks/ExpandedChecksList'
import {StatusCheckStatesIcon} from './checks/StatusCheckStatesIcon'
import {AlertIcon} from './common/AlertIcon'
import {MergeBoxExpandable} from './common/MergeBoxExpandable'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'

const CHECKS_SUMMARY_GROUPINGS = {
  FAILURE: ['ERROR', 'FAILURE', 'STARTUP_FAILURE'],
  TIMED_OUT: ['TIMED_OUT'],
  CANCELLED: ['CANCELLED'],
  SUCCESS: ['SUCCESS'],
  STALE: ['STALE'],
  PENDING: ['ACTION_REQUIRED', 'PENDING', 'WAITING', '_UNKNOWN_VALUE'],
  IN_PROGRESS: ['IN_PROGRESS'],
  QUEUED: ['QUEUED'],
  NEUTRAL: ['NEUTRAL'],
  SKIPPED: ['SKIPPED'],
  EXPECTED: ['EXPECTED'],
  REQUESTED: ['REQUESTED'],
}
export type ChecksSectionProps = {
  pullRequestId: string
  pullRequestHeadSha: string
  focusPrimaryMergeButton: () => void
  sectionStatus: ChecksSectionStatusType
  shouldRender: boolean
  mergeBoxUserPreferences: MergeBoxUserPreferences | null
}

/**
 * Renders when there are workflows pending approval
 * Conditionally allows the user to approve and run the workflows pending approval
 * Always renders the full list of status checks (does not allow collapse)
 */
function PendingApprovalChecksSection({
  checkSectionAriaId,
  pendingWorkflowApprovalRollup,
  statusRollup,
  statusChecks,
  pullRequestHeadSha,
  pullRequestId,
  focusPrimaryMergeButton,
  mergeBoxUserPreferences,
}: {
  checkSectionAriaId: string
  pendingWorkflowApprovalRollup: PendingWorkflowApprovalRollup
  statusRollup: StatusRollup
  statusChecks: StatusCheck[]
  pullRequestHeadSha: string
  pullRequestId: string
  focusPrimaryMergeButton: () => void
  mergeBoxUserPreferences: MergeBoxUserPreferences | null
}) {
  const {isPending, mutate: runActionRequiredWorkflows} = useRunActionRequiredWorkflows({pullRequestHeadSha})
  const handleRunActionRequiredWorkflows = (): void => {
    setErrorMessage(null)
    runActionRequiredWorkflows(undefined, {
      onSuccess: () => {
        setTimeout(() => announce('Successfully approved and re-requested workflows.'), 1000)
        focusPrimaryMergeButton()
      },
      onError: (e: Error): void => setErrorMessage(e.message),
    })
  }
  const [errorMessage, setErrorMessage] = useSafeState<string | null>(null)
  const {
    workflowsRequiringApprovalCount,
    hasExpiredWorkflowRuns,
    approvalRequiredMessage,
    helpLink,
    viewerCanApproveWorkflowRuns,
  } = pendingWorkflowApprovalRollup

  const title = `${workflowsRequiringApprovalCount} workflow${
    workflowsRequiringApprovalCount === 1 ? '' : 's'
  } awaiting approval`
  const subtitle = hasExpiredWorkflowRuns ? (
    'Unable to re-run one or more workflows because they were created over a month ago.'
  ) : (
    <>
      {approvalRequiredMessage}{' '}
      <Link inline href={helpLink}>
        Learn more about approving workflows.
      </Link>
    </>
  )

  return (
    <>
      <MergeBoxSectionHeader
        headerId={checkSectionAriaId}
        title={title}
        subtitle={subtitle}
        icon={<AlertIcon bgColor="attention.emphasis" color="fg.onEmphasis" />}
        rightSideContent={
          viewerCanApproveWorkflowRuns ? (
            <Button
              loading={isPending}
              loadingAnnouncement="Re-running workflows"
              onClick={handleRunActionRequiredWorkflows}
            >
              Approve workflows to run
            </Button>
          ) : undefined
        }
      />
      {errorMessage && (
        <Flash className="m-3" variant="danger">
          <Octicon className="mr-2" icon={StopIcon} />
          {errorMessage}
        </Flash>
      )}
      {statusRollup.summary.length > 0 && (
        <MergeBoxExpandable isExpanded>
          <ExpandedChecksList
            pullRequestId={pullRequestId}
            statusChecks={statusChecks}
            statusRollupSummary={statusRollup.summary}
            mergeBoxUserPreferences={mergeBoxUserPreferences}
          />
        </MergeBoxExpandable>
      )}
    </>
  )
}

/**
 *  Returns a text summary of the statuses of skipped, pending, failing, and successful checks
 *
 *  examples:
 *   - "4 successful checks"
 *   - "1 pending, 1 successful checks"
 *   - "2 failing, 3 successful checks"
 */
export function accessibleChecksSummary(checks: CheckStateRollup[]): string {
  if (checks.length === 0) {
    return 'No checks available.'
  }

  const groupedCheckCounts = countChecksByGroup(checks, CHECKS_SUMMARY_GROUPINGS)
  const totalCheckCounts = Object.keys(groupedCheckCounts).reduce((previous, key) => {
    const count = groupedCheckCounts[key]
    return count ? previous + count : previous
  }, 0)
  const summaryText = Object.keys(STATUS_CHECK_ACCESSIBLE_NAMES)
    .map(key => {
      const count = groupedCheckCounts[key] ?? 0
      const text = getAccessibleStatusText(key as keyof typeof STATUS_CHECK_ACCESSIBLE_NAMES)
      return count > 0 ? `${count} ${text}` : undefined
    })
    .filter(Boolean)
    .join(', ')

  return `${summaryText} ${totalCheckCounts > 1 ? 'checks' : 'check'}`
}

const heading: Record<ChecksSectionStatusType, string> = {
  PASSED: 'All checks have passed',
  PENDING: "Some checks haven't completed yet",
  PENDING_APPROVAL: 'Some checks are waiting for approval',
  PENDING_FAILED: 'Some checks were not successful',
  SOME_FAILED: 'Some checks were not successful',
  FAILED: 'All checks have failed',
  PENDING_CONFLICTS: 'Checks awaiting conflict resolution',
  UNKNOWN: 'Checks status is unknown',
}

/**
 *
 * Renders a collapsible checks section for a pull request
 */
export function ChecksSection({
  pullRequestId,
  pullRequestHeadSha,
  focusPrimaryMergeButton,
  sectionStatus,
  shouldRender,
  mergeBoxUserPreferences,
}: ChecksSectionProps) {
  const {
    data: {aliveChannels, statusRollup, statusChecks},
  } = useStatusChecksPageData({pullRequestHeadSha})
  // expand checks state by default unless all checks pass or user has already collapsed toggle
  const isPassingChecksState = statusRollup.combinedState === 'PASSED'
  const [checksExpanded, setChecksExpanded] = useSessionStorage<boolean>(
    `${pullRequestId}:checksExpanded`,
    !isPassingChecksState,
  )
  const {sendAnalyticsEvent} = useAnalytics()
  const checkSectionAriaId = useId()

  useStatusChecksLiveUpdates(aliveChannels.commitHeadShaChannel, pullRequestHeadSha)
  useSyncFavicon(statusRollup)

  const workflowApproval = statusRollup.pendingWorkflowApprovalRollup
  if (!shouldRender) return null

  return (
    <section aria-label="Checks" aria-describedby={checkSectionAriaId} className="border-bottom color-border-subtle">
      {statusRollup.combinedState === 'PENDING_APPROVAL' && workflowApproval ? (
        <PendingApprovalChecksSection
          checkSectionAriaId={checkSectionAriaId}
          pendingWorkflowApprovalRollup={workflowApproval}
          statusRollup={statusRollup}
          statusChecks={statusChecks}
          pullRequestHeadSha={pullRequestHeadSha}
          pullRequestId={pullRequestId}
          focusPrimaryMergeButton={focusPrimaryMergeButton}
          mergeBoxUserPreferences={mergeBoxUserPreferences}
        />
      ) : (
        <>
          <MergeBoxSectionHeader
            headerId={checkSectionAriaId}
            title={heading[sectionStatus]}
            subtitle={accessibleChecksSummary(statusRollup.summary)}
            icon={<StatusCheckStatesIcon statusRollupSummary={statusRollup.summary} />}
            expandableProps={{
              ariaLabel: checksExpanded ? 'Collapse checks' : 'Expand checks',
              isExpanded: checksExpanded,
              onToggle: () => {
                const eventMetadata = extractChecksAnalyticsMetadata(statusRollup.summary)
                const eventTarget = 'MERGEBOX_CHECKS_SECTION_TOGGLE_BUTTON'
                const eventType = !checksExpanded ? 'checks_section.expand' : 'checks_section.collapse'
                sendAnalyticsEvent(eventType, eventTarget, eventMetadata)
                setChecksExpanded(!checksExpanded)
              },
            }}
          />
          <MergeBoxExpandable isExpanded={checksExpanded}>
            <ExpandedChecksList
              statusChecks={statusChecks}
              statusRollupSummary={statusRollup.summary}
              pullRequestId={pullRequestId}
              mergeBoxUserPreferences={mergeBoxUserPreferences}
            />
          </MergeBoxExpandable>
        </>
      )}
    </section>
  )
}
