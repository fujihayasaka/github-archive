import {assertDataPresent} from '@github-ui/assert-data-present'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {GitMergeIcon, GitMergeQueueIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'
import {clsx} from 'clsx'
import {memo, startTransition, Suspense, useCallback, useMemo, useState} from 'react'
import {useMergeMethodContext} from '../contexts/MergeMethodContext'
import {getConflictsCondition, isUserBlockedFromPushingByAuthorizationPolicy} from '../helpers/json-api-helpers'
import {MergeBoxStatusCalculator} from '../helpers/merge-box-status-calculator/merge-box-status-calculator'
import {mergeBoxStatusPresentation} from '../helpers/merge-box-status-presentation'
import {mergeabilityStatus, presentationForStatus} from '../helpers/mergeability-status'
import {useMergeabilityLiveUpdates, type Channels} from '../hooks/use-mergeability-live-updates'
import {useMergeBoxPageData} from '../page-data/loaders/use-merge-box-page-data'
import {useStatusChecksPageDataWithoutError} from '../page-data/loaders/use-status-checks-page-data'
import type {JSONAPIPullRequestPayload, PullRequestMergeRequirementsPayload} from '../page-data/payloads/merge-box'
import {MergeAction} from '../types'
import {ClosedOrMergedStateMergeBox} from './ClosedOrMergedStateMergeBox'
import {MergeabilityIcon} from './MergeabilityIcon'
import styles from './MergeBox.module.css'
import {MergeBoxErrorState} from './MergeBoxErrorState'
import {BlockedSection} from './sections/BlockedSection'
import {ChecksSection} from './sections/ChecksSection'
import {ChecksSectionFetchFailure} from './sections/ChecksSectionFetchFailure'
import {ConflictsSection} from './sections/ConflictsSection'
import {DraftStateSection} from './sections/DraftStateSection'
import {MergeQueueSection} from './sections/merge-section/MergeQueueSection'
import {MergeSection} from './sections/merge-section/MergeSection'
import {ReviewerSection} from './sections/ReviewerSection'

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
  /**
   * The alive channels used for refetching mergeability updates
   */
  channels: Channels
}
/**
 * Provides a suspense boundary for the mergebox
 */
export const MergeBoxWithSuspense = memo(function MergeBoxWithSuspense({
  hideIcon = false,
  ...rest
}: MergeBoxWithSuspenseProps) {
  return (
    <ErrorBoundary critical fallback={<MergeBoxErrorState hideIcon={hideIcon} />}>
      <Suspense>
        <MergeBoxWrapper hideIcon={hideIcon} {...rest} />
      </Suspense>
    </ErrorBoundary>
  )
})

/**
 * Loads the data for the MergeBox and translates it into an agnostic format for the MergeBox
 */
export function MergeBoxWrapper({
  viewerLogin,
  channels,
  ...rest
}: {
  hideIcon?: boolean
  viewerLogin: string
  helpUrl: string
  channels: Channels
}) {
  const {mergeMethod} = useMergeMethodContext()

  const {data, refetch, isLoading, error} = useMergeBoxPageData({mergeMethod, bypassRequirements: false})

  const aliveChannels = useMemo(() => {
    if (data?.pullRequest.mergeBoxAliveChannels) return data?.pullRequest.mergeBoxAliveChannels

    return channels
  }, [channels, data])

  const refetchQuery = useCallback(() => {
    startTransition(() => {
      refetch({cancelRefetch: false})
    })
  }, [refetch])

  useMergeabilityLiveUpdates({refetchQuery, channels: aliveChannels})

  if (isLoading) return <MergeBoxLoading />
  // re-throw error to bubble up to our ErrorBoundary wrapping this component.
  if (error) throw error
  if (!data) return null

  return (
    // This suspense boundary ensures the entire merge box shows a loading state if any children of the merge box are fetching/consuming different data via `useSuspenseQuery` calls that are not wrapped in their own `Suspense` boundary.
    // Specifically, we don't render the merge box until we've received both core merge box data and status checks data.
    <Suspense fallback={<MergeBoxLoading />}>
      <h2 className="sr-only">Merge info</h2>
      <MergeBox
        mergeRequirements={data.mergeRequirements}
        numberOfCommits={data.pullRequest.numberOfCommits || 0}
        pullRequest={data.pullRequest}
        viewerLogin={viewerLogin}
        {...rest}
      />
    </Suspense>
  )
}

export type MergeBoxProps = {
  helpUrl: string
  hideIcon?: boolean
  mergeRequirements: PullRequestMergeRequirementsPayload | null
  numberOfCommits: number
  pullRequest: JSONAPIPullRequestPayload
  viewerLogin: string
}
/**
 * The actual mergebox with sections
 */
export function MergeBox({
  helpUrl,
  hideIcon = false,
  mergeRequirements,
  numberOfCommits,
  pullRequest: pullRequestData,
  viewerLogin,
}: MergeBoxProps) {
  const directMergeAction = pullRequestData.viewerMergeActions.find(action => action.name === MergeAction.DIRECT_MERGE)
  assertDataPresent(directMergeAction)

  const mergeboxHideSectionsFeatureFlag = useFeatureFlag('merge_box_hide_sections')
  const [isConfirmingMergeInfo, setIsConfirmingMergeInfo] = useState(false)
  const shouldRenderAllSections = mergeboxHideSectionsFeatureFlag ? !isConfirmingMergeInfo : true

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

  // Merge Box Status Calculator Helpers
  const statusCalculator = new MergeBoxStatusCalculator(pullRequestData, mergeRequirements, statusChecksData)
  const mergeBoxRollupStatus = statusCalculator.overallStatus
  const blockedSectionStatus = statusCalculator.sections.BlockedSection
  const checksSectionStatus = statusCalculator.sections.ChecksSection
  const closedOrMergedStateSectionStatus = statusCalculator.sections.ClosedOrMergedStateMergeBox
  const conflictsSectionStatus = statusCalculator.sections.ConflictsSection
  const draftStateSectionStatus = statusCalculator.sections.DraftStateSection
  const mergeQueueSectionStatus = statusCalculator.sections.MergeQueueSection
  const reviewerSectionStatus = statusCalculator.sections.ReviewerSection

  // Determines the text for the icon
  const mergeStatusPresentation = presentationForStatus(status)
  const mergeBoxOverallStatusPresentation = mergeBoxStatusPresentation(mergeBoxRollupStatus, !shouldRenderAllSections)

  const userStateCondition = mergeRequirements?.conditions.find(
    condition => condition.type === 'PULL_REQUEST_USER_STATE',
  )

  const canUserPushToBase = userStateCondition?.result === 'PASSED'
  const isUserBlockedFromPushing = isUserBlockedFromPushingByAuthorizationPolicy(mergeRequirements)
  const conflictsCondition = getConflictsCondition(mergeRequirements)
  const mergeBoxIcon = isInMergeQueue ? GitMergeQueueIcon : GitMergeIcon

  const focusPrimaryMergeButton = useCallback(() => {
    setShouldFocusPrimaryMergeButton(true)
  }, [setShouldFocusPrimaryMergeButton])

  const shouldHideMergeSection = !canUserPushToBase || isUserBlockedFromPushing

  const mergeBoxUserPreferences = pullRequestData.mergeBoxUserPreferences

  return (
    <div className={clsx(styles.mergePartialContainer, 'position-relative partial-pull-merging-analytics-js')}>
      {!shouldHideIcon && (
        <div className="d-none d-lg-block" data-testid="mergeability-icon-wrapper">
          <MergeabilityIcon
            icon={mergeBoxIcon}
            ariaLabel={mergeStatusPresentation.title}
            iconBackgroundColor={mergeBoxOverallStatusPresentation.iconColor}
          />
        </div>
      )}
      <div
        className={clsx(
          shouldHideMergeSection ? styles.mergeBoxAdjustBorders : '',
          `border rounded-2 ${mergeBoxOverallStatusPresentation.borderColor}`,
        )}
      >
        {closedOrMergedStateSectionStatus.shouldRender || !mergeRequirements ? (
          <ClosedOrMergedStateMergeBox
            isCrossRepo={pullRequestData.isCrossRepo}
            state={pullRequestData.state}
            headRefName={pullRequestData.headRefName}
            headRepository={pullRequestData.headRepository}
            baseRepository={pullRequestData.baseRepository}
            viewerCanDeleteHeadRef={pullRequestData.viewerCanDeleteHeadRef}
            viewerCanRestoreHeadRef={pullRequestData.viewerCanRestoreHeadRef}
            deprovisionableCodespaces={pullRequestData.deprovisionableCodespaces}
          />
        ) : mergeQueueSectionStatus.shouldRender ? (
          <MergeQueueSection
            viewerCanAddAndRemoveFromMergeQueue={pullRequestData.viewerCanAddAndRemoveFromMergeQueue}
            mergeQueueEntry={pullRequestData.mergeQueueEntry}
            mergeQueue={pullRequestData.mergeQueue}
            focusPrimaryMergeButton={focusPrimaryMergeButton}
          />
        ) : (
          <>
            {shouldRenderAllSections && (
              <>
                {reviewerSectionStatus.shouldRender && (
                  <ReviewerSection
                    consolidatedFailureReasons={reviewerSectionStatus.consolidatedFailureReasons}
                    helpUrl={helpUrl}
                    latestOpinionatedReviews={pullRequestData.latestOpinionatedReviews}
                    numReviewsRequired={reviewerSectionStatus.numReviewsRequired}
                    pendingRequestedReviews={pullRequestData.pendingReviewRequests}
                    pullRequestId={pullRequestData.id}
                    reviewsState={reviewerSectionStatus.sectionStatus}
                    viewerCanDismissReviews={pullRequestData.viewerCanDismissReviews}
                    viewerCanReRequestReviews={pullRequestData.viewerCanReRequestReviews}
                  />
                )}
                <ErrorBoundary fallback={<ChecksSectionFetchFailure />}>
                  <ChecksSection
                    pullRequestId={pullRequestData.id}
                    pullRequestHeadSha={pullRequestData.headRefOid}
                    focusPrimaryMergeButton={focusPrimaryMergeButton}
                    sectionStatus={checksSectionStatus.sectionStatus}
                    shouldRender={checksSectionStatus.shouldRender}
                    mergeBoxUserPreferences={mergeBoxUserPreferences}
                  />
                </ErrorBoundary>
                {conflictsSectionStatus.shouldRender && conflictsSectionStatus.conflictsCondition && (
                  <ConflictsSection
                    advisoryWorkspace={pullRequestData.advisoryWorkspace}
                    baseRefName={pullRequestData.baseRefName}
                    headRefOid={pullRequestData.headRefOid}
                    conflictsCondition={conflictsSectionStatus.conflictsCondition}
                    conflictsState={conflictsSectionStatus.sectionStatus}
                    mergeStateStatus={pullRequestData.mergeStateStatus}
                    resourcePath={pullRequestData.resourcePath}
                    canUserPushToBase={canUserPushToBase}
                    viewerCanUpdateBranch={pullRequestData.viewerCanUpdateBranch}
                    viewerLogin={viewerLogin}
                    viewerUpdateMethods={pullRequestData.viewerUpdateMethods}
                  />
                )}
                {blockedSectionStatus.shouldRender && (
                  <BlockedSection failingConditionsAndRules={blockedSectionStatus.failingConditionsAndRules} />
                )}
                {draftStateSectionStatus.shouldRender && (
                  <DraftStateSection viewerCanUpdate={pullRequestData.viewerCanUpdate} helpUrl={helpUrl} />
                )}
              </>
            )}
            {shouldHideMergeSection ? null : (
              <MergeSection
                advisoryWorkspace={pullRequestData.advisoryWorkspace}
                autoMergeRequest={pullRequestData.autoMergeRequest}
                baseRefName={pullRequestData.baseRefName}
                numberOfCommits={numberOfCommits}
                conflictsCondition={conflictsCondition}
                headRepository={pullRequestData.headRepository}
                helpUrl={helpUrl}
                id={pullRequestData.id}
                isConfirmingMergeInfo={mergeboxHideSectionsFeatureFlag ? isConfirmingMergeInfo : undefined}
                isCrossRepo={pullRequestData.isCrossRepo}
                isDraft={pullRequestData.isDraft}
                isInMergeQueue={pullRequestData.isInMergeQueue}
                mergeQueue={pullRequestData.mergeQueue}
                canUserPushToBase={canUserPushToBase}
                defaultCommitAuthorEmail={mergeRequirements.defaultCommitAuthorEmail}
                commitMessageBody={mergeRequirements.commitMessageBody}
                commitMessageHeadline={mergeRequirements.commitMessageHeadline}
                mergeRequirementsState={mergeRequirements.state}
                mergeStateStatus={pullRequestData.mergeStateStatus}
                mergeBoxRollupStatus={mergeBoxRollupStatus}
                viewerCanAddAndRemoveFromMergeQueue={pullRequestData.viewerCanAddAndRemoveFromMergeQueue}
                viewerCanAdminBypassMergeRequirements={pullRequestData.viewerCanAdminBypassMergeRequirements}
                viewerCanAddToMergeQueueSolo={pullRequestData.viewerCanAddToMergeQueueSolo}
                viewerCanDisableAutoMerge={pullRequestData.viewerCanDisableAutoMerge}
                viewerMergeActions={pullRequestData.viewerMergeActions}
                viewerCanEnableAutoMerge={pullRequestData.viewerCanEnableAutoMerge}
                shouldFocusPrimaryMergeButton={shouldFocusPrimaryMergeButton}
                setShouldFocusPrimaryMergeButton={setShouldFocusPrimaryMergeButton}
                status={status}
                possibleCommitAuthorEmails={mergeRequirements.possibleCommitAuthorEmails}
                handleConfirmingMergeInfo={mergeboxHideSectionsFeatureFlag ? setIsConfirmingMergeInfo : undefined}
              />
            )}
          </>
        )}
      </div>
    </div>
  )
}
