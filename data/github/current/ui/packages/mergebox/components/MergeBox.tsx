import {assertDataPresent} from '@github-ui/assert-data-present'
import {memo, startTransition, useCallback, useState, Suspense} from 'react'
import {clsx} from 'clsx'
import {MergeAction} from '../types'
import type {ReviewerRuleRollup} from '../types'
import {useMergeMethodContext} from '../contexts/MergeMethodContext'
import {ChecksSection} from './sections/ChecksSection'
import {ChecksSectionFetchFailure} from './sections/ChecksSectionFetchFailure'
import {ClosedOrMergedStateMergeBox} from './ClosedOrMergedStateMergeBox'
import {ConflictsSection, type ConflictsSectionProps} from './sections/ConflictsSection'
import {useMergeabilityLiveUpdates, type Channels} from '../hooks/use-mergeability-live-updates'
import {MergeQueueSection} from './sections/merge-section/MergeQueueSection'
import {MergeSection} from './sections/merge-section/MergeSection'
import {BlockedSection, type BlockedSectionProps} from './sections/BlockedSection'
import {DraftStateSection} from './sections/DraftStateSection'
import styles from './MergeBox.module.css'
import {borderColorClassForStatus, mergeabilityStatus, presentationForStatus} from '../helpers/mergeability-status'
import {GitMergeIcon, GitMergeQueueIcon} from '@primer/octicons-react'
import {MergeabilityIcon} from './MergeabilityIcon'
import {QueryClientProvider, type RefetchOptions} from '@tanstack/react-query'
import {ReactQueryDevtools} from '@tanstack/react-query-devtools'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {ReviewerSection} from './sections/ReviewerSection'
import {useMergeBoxPageData} from '../page-data/loaders/use-merge-box-page-data'
import {
  getConflictsCondition,
  getFailingMergeConditionsWithoutRulesCondition,
  getFailingRulesConditions,
  getReviewRuleRollupMetadata,
} from '../helpers/json-api-helpers'
import {Spinner} from '@primer/react'
import type {JSONAPIPullRequestPayload, PullRequestMergeRequirementsPayload} from '../page-data/payloads/merge-box'
import {MergeBoxErrorState} from './MergeBoxErrorState'
import {useStatusChecksPageDataWithoutError} from '../page-data/loaders/use-status-checks-page-data'

function MergeBoxLoading() {
  return (
    <div className={styles.mergeboxLoading}>
      <Spinner />
    </div>
  )
}

type MergeBoxWithSuspenseProps = {
  /**
   * When true, hides the mergeability icon that is shown to the left of the mergebox
   */
  hideIcon?: boolean
  /**
   * The current user's display login
   */
  viewerLogin: string
  /**
   *  The base help docs URL for the environment
   */
  helpUrl: string
}
/**
 * Provides a suspense boundary for the mergebox
 */
export const MergeBoxWithSuspense = memo(function MergeBoxWithSuspense({
  hideIcon = false,
  ...rest
}: MergeBoxWithSuspenseProps) {
  return (
    <Suspense fallback={<MergeBoxLoading />}>
      <QueryClientProvider client={queryClient}>
        <ErrorBoundary critical fallback={<MergeBoxErrorState hideIcon={hideIcon} />}>
          <MergeBoxWrapper hideIcon={hideIcon} {...rest} />
          <ReactQueryDevtools initialIsOpen={false} />
        </ErrorBoundary>
      </QueryClientProvider>
    </Suspense>
  )
})

/**
 * Loads the data for the MergeBox and translates it into an agnostic format for the MergeBox
 */
export function MergeBoxWrapper({viewerLogin, ...rest}: {hideIcon?: boolean; viewerLogin: string; helpUrl: string}) {
  const {mergeMethod} = useMergeMethodContext()
  const {
    data: {pullRequest, mergeRequirements},
    refetch,
  } = useMergeBoxPageData({mergeMethod, bypassRequirements: false})

  const aliveChannels = pullRequest.mergeBoxAliveChannels
  const reviewRules = getReviewRuleRollupMetadata(mergeRequirements)
  const conflictsCondition = getConflictsCondition(mergeRequirements)

  const failingMergeConditionsWithoutRulesCondition = getFailingMergeConditionsWithoutRulesCondition(mergeRequirements)

  const failingRulesConditions = getFailingRulesConditions(mergeRequirements)

  return (
    <>
      <h2 className="sr-only">Merge info</h2>
      <MergeBox
        aliveChannels={aliveChannels}
        conflictsCondition={conflictsCondition}
        failingMergeConditionsWithoutRulesCondition={failingMergeConditionsWithoutRulesCondition}
        failingRulesConditions={failingRulesConditions}
        mergeRequirements={mergeRequirements}
        numberOfCommits={pullRequest.numberOfCommits || 0}
        pullRequest={pullRequest}
        reviewRules={reviewRules}
        viewerLogin={viewerLogin}
        refetchQuery={refetch}
        {...rest}
      />
    </>
  )
}

export type MergeBoxProps = {
  aliveChannels: Channels
  conflictsCondition: ConflictsSectionProps['conflictsCondition']
  failingMergeConditionsWithoutRulesCondition: BlockedSectionProps['failingMergeConditionsWithoutRulesCondition']
  failingRulesConditions: BlockedSectionProps['failingRulesConditions']
  helpUrl: string
  hideIcon?: boolean
  mergeRequirements: PullRequestMergeRequirementsPayload | null
  numberOfCommits: number
  pullRequest: JSONAPIPullRequestPayload
  refetchQuery: (options?: RefetchOptions) => void
  reviewRules: ReviewerRuleRollup[]
  viewerLogin: string
}
/**
 * The actual mergebox with sections
 */
export function MergeBox({
  aliveChannels,
  conflictsCondition,
  failingMergeConditionsWithoutRulesCondition,
  failingRulesConditions,
  helpUrl,
  hideIcon = false,
  mergeRequirements,
  numberOfCommits,
  pullRequest: pullRequestData,
  refetchQuery: refetch,
  reviewRules,
  viewerLogin,
}: MergeBoxProps) {
  const directMergeAction = pullRequestData.viewerMergeActions.find(action => action.name === MergeAction.DIRECT_MERGE)
  assertDataPresent(directMergeAction)

  const [shouldFocusPrimaryMergeButton, setShouldFocusPrimaryMergeButton] = useState(false)
  const {isInMergeQueue, state, viewerCanDeleteHeadRef, viewerCanRestoreHeadRef} = pullRequestData
  const shouldHideIcon =
    hideIcon || ((state === 'CLOSED' || state === 'MERGED') && !viewerCanDeleteHeadRef && !viewerCanRestoreHeadRef)

  const statusChecksData = useStatusChecksPageDataWithoutError({
    pullRequestHeadSha: pullRequestData.headRefOid,
  }).data

  const status = mergeabilityStatus({
    pullRequest: pullRequestData,
    mergeRequirements,
    statusChecksData,
  })
  const mergeStatusPresentation = presentationForStatus(status)
  const mergeboxBorderColor = borderColorClassForStatus(status)

  const userStateCondition = mergeRequirements?.conditions.find(
    condition => condition.type === 'PULL_REQUEST_USER_STATE',
  )
  const canUserPushToBase = userStateCondition?.result === 'PASSED'

  const mergeBoxIcon = isInMergeQueue ? GitMergeQueueIcon : GitMergeIcon

  const refetchQuery = useCallback(() => {
    startTransition(() => {
      refetch({cancelRefetch: false})
    })
  }, [refetch])

  useMergeabilityLiveUpdates({refetchQuery, channels: aliveChannels})

  const focusPrimaryMergeButton = useCallback(() => {
    setShouldFocusPrimaryMergeButton(true)
  }, [setShouldFocusPrimaryMergeButton])

  return (
    <div className={clsx(styles.mergePartialContainer, 'position-relative partial-pull-merging-analytics-js')}>
      {!shouldHideIcon && (
        <MergeabilityIcon
          icon={mergeBoxIcon}
          ariaLabel={mergeStatusPresentation.title}
          iconBackgroundColor={mergeStatusPresentation.iconColor}
        />
      )}
      {pullRequestData.state !== 'OPEN' || !mergeRequirements ? (
        <ClosedOrMergedStateMergeBox
          state={pullRequestData.state}
          headRefName={pullRequestData.headRefName}
          headRepository={pullRequestData.headRepository}
          viewerCanDeleteHeadRef={pullRequestData.viewerCanDeleteHeadRef}
          viewerCanRestoreHeadRef={pullRequestData.viewerCanRestoreHeadRef}
        />
      ) : (
        <div className={`border rounded-2 ${mergeboxBorderColor}`}>
          {isInMergeQueue ? (
            <MergeQueueSection
              viewerCanAddAndRemoveFromMergeQueue={pullRequestData.viewerCanAddAndRemoveFromMergeQueue}
              mergeQueueEntry={pullRequestData.mergeQueueEntry}
              mergeQueue={pullRequestData.mergeQueue}
              focusPrimaryMergeButton={focusPrimaryMergeButton}
            />
          ) : (
            <>
              <ReviewerSection
                refetchMergeBoxQuery={refetchQuery}
                reviewerRuleRollups={reviewRules}
                viewerCanDismissReviews={pullRequestData.viewerCanDismissReviews}
                latestOpinionatedReviews={pullRequestData.latestOpinionatedReviews}
                pendingRequestedReviews={pullRequestData.pendingReviewRequests}
                viewerCanReRequestReviews={pullRequestData.viewerCanReRequestReviews}
              />
              <ErrorBoundary fallback={<ChecksSectionFetchFailure />}>
                <ChecksSection pullRequestId={pullRequestData.id} pullRequestHeadSha={pullRequestData.headRefOid} />
              </ErrorBoundary>
              <ConflictsSection
                baseRefName={pullRequestData.baseRefName}
                headRefOid={pullRequestData.headRefOid}
                conflictsCondition={conflictsCondition}
                mergeStateStatus={pullRequestData.mergeStateStatus}
                resourcePath={pullRequestData.resourcePath}
                canUserPushToBase={canUserPushToBase}
                viewerCanUpdateBranch={pullRequestData.viewerCanUpdateBranch}
                viewerLogin={viewerLogin}
              />
              <BlockedSection
                isDraft={pullRequestData.isDraft}
                failingMergeConditionsWithoutRulesCondition={failingMergeConditionsWithoutRulesCondition}
                failingRulesConditions={failingRulesConditions}
                mergeRequirementsState={mergeRequirements.state}
              />
              <DraftStateSection
                isDraft={pullRequestData.isDraft}
                state={pullRequestData.state}
                viewerCanUpdate={pullRequestData.viewerCanUpdate}
              />
              <MergeSection
                autoMergeRequest={pullRequestData.autoMergeRequest}
                baseRefName={pullRequestData.baseRefName}
                numberOfCommits={numberOfCommits}
                conflictsCondition={conflictsCondition}
                headRepository={pullRequestData.headRepository}
                helpUrl={helpUrl}
                id={pullRequestData.id}
                isCrossRepo={pullRequestData.isCrossRepo}
                isDraft={pullRequestData.isDraft}
                isInMergeQueue={pullRequestData.isInMergeQueue}
                mergeQueue={pullRequestData.mergeQueue}
                canUserPushToBase={canUserPushToBase}
                commitAuthorEmail={mergeRequirements.commitAuthorEmail}
                commitMessageBody={mergeRequirements.commitMessageBody}
                commitMessageHeadline={mergeRequirements.commitMessageHeadline}
                mergeRequirementsState={mergeRequirements.state}
                mergeStateStatus={pullRequestData.mergeStateStatus}
                viewerCanAddAndRemoveFromMergeQueue={pullRequestData.viewerCanAddAndRemoveFromMergeQueue}
                viewerCanAdminBypassMergeRequirements={pullRequestData.viewerCanAdminBypassMergeRequirements}
                viewerCanAddToMergeQueueSolo={pullRequestData.viewerCanAddToMergeQueueSolo}
                viewerCanDisableAutoMerge={pullRequestData.viewerCanDisableAutoMerge}
                viewerMergeActions={pullRequestData.viewerMergeActions}
                viewerCanEnableAutoMerge={pullRequestData.viewerCanEnableAutoMerge}
                shouldFocusPrimaryMergeButton={shouldFocusPrimaryMergeButton}
                setShouldFocusPrimaryMergeButton={setShouldFocusPrimaryMergeButton}
                status={status}
              />
            </>
          )}
        </div>
      )}
    </div>
  )
}
