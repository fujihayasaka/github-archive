import {useAnalytics} from '@github-ui/use-analytics'
import {CheckIcon, CodeReviewIcon, FileDiffIcon, XIcon} from '@primer/octicons-react'
import {CircleOcticon} from '@primer/react'
import {clsx} from 'clsx'
import {useMemo, useState, useId} from 'react'

import {accessibleReviewSummary} from '../../accessible-review-summary'
import {HEADER_ICON_SIZE} from '../../constants'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import type {
  PullRequestReviewState,
  PullRequestRuleFailureReason,
  OpinionatedReview,
  PendingReviewRequest,
  ReviewerRuleRollup,
} from '../../types'
import {ReviewGroup} from '../../types'
import styles from './ReviewerSection.module.css'
import {MergeBoxExpandable} from './common/MergeBoxExpandable'
import {OpinionatedReviewsGroup} from './reviewers-section/OpinionatedReviewsGroup'
import {PendingRequestedReviewsGroup} from './reviewers-section/PendingRequestedReviewsGroup'

export type ReviewerSectionProps = {
  reviewerRuleRollups: ReviewerRuleRollup[]
  latestOpinionatedReviews: OpinionatedReview[]
  pendingRequestedReviews: PendingReviewRequest[]
  viewerCanDismissReviews: boolean
  refetchMergeBoxQuery: () => void
  viewerCanReRequestReviews: boolean
}

export enum ConsolidatedReviewState {
  APPROVED = 'APPROVED',
  CHANGES_REQUESTED = 'CHANGES_REQUESTED',
  REVIEW_REQUIRED = 'REVIEW_REQUIRED',
  REVIEWED = 'REVIEWED',
}

export const getReviewsState = (
  reviewsRequired: number,
  isCodeownersRequired: boolean,
  reviews: Array<{
    authorCanPushToRepository: boolean
    state: PullRequestReviewState
  }>,
  failureReasons: PullRequestRuleFailureReason[],
): ConsolidatedReviewState => {
  if (failureReasons.length === 0 && reviews.length > 0 && (reviewsRequired > 0 || isCodeownersRequired)) {
    return ConsolidatedReviewState.APPROVED
  }
  if (
    failureReasons.includes('CODE_OWNER_REVIEW_REQUIRED') ||
    failureReasons.includes('SOC2_APPROVAL_PROCESS_REQUIRED') ||
    failureReasons.includes('MORE_REVIEWS_REQUIRED') ||
    failureReasons.includes('LAST_PUSH_APPROVAL_REQUIRED')
  ) {
    return ConsolidatedReviewState.REVIEW_REQUIRED
  }
  if (failureReasons.includes('CHANGES_REQUESTED')) {
    return ConsolidatedReviewState.CHANGES_REQUESTED
  }
  // we can assume if we fall through to here that there is a review because if
  // no reviews are required and we have none, we return early and don't render
  return ConsolidatedReviewState.REVIEWED
}

const reviewRequiredSummary = (reviewsRequired: number, failureReasons: PullRequestRuleFailureReason[]): string => {
  if (failureReasons.includes('MORE_REVIEWS_REQUIRED')) {
    if (reviewsRequired === 1) {
      return 'At least 1 approving review is required'
    } else if (reviewsRequired === 0 && failureReasons.includes('LAST_PUSH_APPROVAL_REQUIRED')) {
      return `An approval on the most recent push is required`
    } else {
      return `At least ${reviewsRequired} approving reviews are required`
    }
  } else {
    if (failureReasons.includes('CODE_OWNER_REVIEW_REQUIRED')) {
      return 'Code owner review required'
    } else if (failureReasons.includes('SOC2_APPROVAL_PROCESS_REQUIRED')) {
      return 'A review from a compliance team is required'
    }
  }
  return ''
}

const heading: {[key: string]: string} = {
  APPROVED: 'Changes approved',
  CHANGES_REQUESTED: 'Changes requested',
  REVIEW_REQUIRED: 'Review required',
  REVIEWED: 'Changes reviewed',
}

const icon: {[key: string]: JSX.Element} = {
  APPROVED: (
    <CircleOcticon
      className="bgColor-success-emphasis fgColor-onEmphasis"
      icon={() => <CheckIcon size={16} />}
      size={HEADER_ICON_SIZE}
    />
  ),
  CHANGES_REQUESTED: (
    <CircleOcticon
      className="bgColor-danger-emphasis fgColor-onEmphasis"
      icon={() => <FileDiffIcon size={16} />}
      size={HEADER_ICON_SIZE}
    />
  ),
  REVIEW_REQUIRED: (
    <CircleOcticon
      className="bgColor-danger-emphasis fgColor-onEmphasis"
      icon={() => <XIcon size={16} />}
      size={HEADER_ICON_SIZE}
    />
  ),
  REVIEWED: (
    <CircleOcticon
      className={clsx(styles.reviewedIcon, 'fgColor-onEmphasis')}
      icon={() => <CodeReviewIcon size={16} />}
      size={HEADER_ICON_SIZE}
    />
  ),
}

const isReviewRelatedFailureReason = (r: PullRequestRuleFailureReason) => {
  return (
    r === 'CODE_OWNER_REVIEW_REQUIRED' ||
    r === 'SOC2_APPROVAL_PROCESS_REQUIRED' ||
    r === 'CHANGES_REQUESTED' ||
    r === 'MORE_REVIEWS_REQUIRED' ||
    r === 'LAST_PUSH_APPROVAL_REQUIRED'
  )
}

function partitionOpinionatedReviews(latestOpinionatedReviews: OpinionatedReview[]) {
  const approvedReviews: OpinionatedReview[] = []
  const requestedChangesReviews: OpinionatedReview[] = []

  for (const review of latestOpinionatedReviews) {
    if (review.state === 'APPROVED') approvedReviews.push(review)
    if (review.state === 'CHANGES_REQUESTED') requestedChangesReviews.push(review)
  }

  return {approvedReviews, requestedChangesReviews}
}

/**
 * Renders a collapsible section with a list of reviewers and their reviews.
 */
export function ReviewerSection({
  reviewerRuleRollups,
  latestOpinionatedReviews,
  pendingRequestedReviews,
  viewerCanDismissReviews,
  refetchMergeBoxQuery,
  viewerCanReRequestReviews,
}: ReviewerSectionProps) {
  const shouldAutoExpandSection = [...latestOpinionatedReviews, ...pendingRequestedReviews].length > 0
  const [reviewersExpanded, setReviewersExpanded] = useState(shouldAutoExpandSection)
  const {sendAnalyticsEvent} = useAnalytics()
  const reviewsSectionAriaId = useId()

  const {approvedReviews, requestedChangesReviews} = useMemo(
    () => partitionOpinionatedReviews(latestOpinionatedReviews),
    [latestOpinionatedReviews],
  )

  const reviewRules = reviewerRuleRollups

  const requiredReviewCounts = reviewRules?.flatMap(rule => rule.requiredReviewers || []) || []
  const numReviewsRequired = requiredReviewCounts.length ? Math.max(...requiredReviewCounts) : 0

  const codeownersRequiredRules = reviewRules?.filter(rule => rule.requiresCodeowners) || []
  const codeownersRequired = codeownersRequiredRules.length > 0

  const allFailureReasons = reviewRules?.flatMap(rule => rule.failureReasons || []) || []
  const consolidatedFailureReasons = [...new Set(allFailureReasons)].filter(isReviewRelatedFailureReason)

  const reviewsState = getReviewsState(
    numReviewsRequired,
    codeownersRequired,
    latestOpinionatedReviews,
    consolidatedFailureReasons,
  )

  // don't render if there are no reviews and no reviews are required
  if (
    latestOpinionatedReviews.length === 0 &&
    pendingRequestedReviews.length === 0 &&
    consolidatedFailureReasons.length === 0
  ) {
    return null
  }

  return (
    <section aria-label="Reviews" aria-describedby={reviewsSectionAriaId} className="border-bottom color-border-subtle">
      <MergeBoxSectionHeader
        headerId={reviewsSectionAriaId}
        title={heading[reviewsState]}
        subtitle={`${
          reviewsState === ConsolidatedReviewState.REVIEW_REQUIRED
            ? reviewRequiredSummary(numReviewsRequired, consolidatedFailureReasons)
            : accessibleReviewSummary(latestOpinionatedReviews)
        }
         by reviewers with write access.`}
        icon={icon[reviewsState]}
        expandableProps={
          shouldAutoExpandSection
            ? {
                ariaLabel: reviewersExpanded ? 'Collapse reviews' : 'Expand reviews',
                isExpanded: reviewersExpanded,
                onToggle: () => {
                  const eventType = reviewersExpanded ? 'reviewers_section.collapse' : 'reviewers_section.expand'
                  const eventTarget = 'MERGEBOX_REVIEWERS_SECTION_TOGGLE_BUTTON'
                  sendAnalyticsEvent(eventType, eventTarget)
                  setReviewersExpanded(!reviewersExpanded)
                },
              }
            : undefined
        }
      />
      <MergeBoxExpandable isExpanded={reviewersExpanded}>
        <div className={styles.reviewerGroupsContainer}>
          <OpinionatedReviewsGroup
            viewerCanDismissReviews={viewerCanDismissReviews}
            refetchMergeBoxQuery={refetchMergeBoxQuery}
            reviewGroup={ReviewGroup.Approvals}
            opinionatedReviews={approvedReviews}
            viewerCanReRequestReviews={viewerCanReRequestReviews}
          />
          <OpinionatedReviewsGroup
            viewerCanDismissReviews={viewerCanDismissReviews}
            refetchMergeBoxQuery={refetchMergeBoxQuery}
            reviewGroup={ReviewGroup.RequestedChanges}
            opinionatedReviews={requestedChangesReviews}
            viewerCanReRequestReviews={viewerCanReRequestReviews}
          />
          <PendingRequestedReviewsGroup
            reviewGroup={ReviewGroup.PendingReviewRequest}
            refetchMergeBoxQuery={refetchMergeBoxQuery}
            viewerCanDismissReviews={viewerCanDismissReviews}
            pendingRequestedReviews={pendingRequestedReviews}
          />
        </div>
      </MergeBoxExpandable>
    </section>
  )
}
