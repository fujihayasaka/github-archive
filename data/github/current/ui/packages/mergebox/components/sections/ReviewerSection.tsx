import {useAnalytics} from '@github-ui/use-analytics'
import {CheckIcon, CodeReviewIcon, FileDiffIcon, XIcon} from '@primer/octicons-react'
import {CircleOcticon, Link} from '@primer/react'
import {clsx} from 'clsx'
import {useMemo, useState, useId} from 'react'

import {accessibleReviewSummary} from '../../accessible-review-summary'
import {HEADER_ICON_SIZE} from '../../constants'
import {MergeBoxSectionHeader} from './common/MergeBoxSectionHeader'
import type {PullRequestRuleFailureReason, OpinionatedReview, PendingReviewRequest} from '../../types'
import {ReviewGroup} from '../../types'
import styles from './ReviewerSection.module.css'
import {MergeBoxExpandable} from './common/MergeBoxExpandable'
import {OpinionatedReviewsGroup} from './reviewers-section/OpinionatedReviewsGroup'
import {PendingRequestedReviewsGroup} from './reviewers-section/PendingRequestedReviewsGroup'

export type ReviewerSectionProps = {
  consolidatedFailureReasons: PullRequestRuleFailureReason[]
  helpUrl: string
  latestOpinionatedReviews: OpinionatedReview[]
  numReviewsRequired: number
  pendingRequestedReviews: PendingReviewRequest[]
  pullRequestId: string
  reviewsState: ConsolidatedReviewState
  viewerCanDismissReviews: boolean
  viewerCanReRequestReviews: boolean
}

export const ConsolidatedReviewState = {
  APPROVED: 'APPROVED',
  CHANGES_REQUESTED: 'CHANGES_REQUESTED',
  REVIEW_REQUIRED: 'REVIEW_REQUIRED',
  REVIEWED: 'REVIEWED',
  REVIEW_REQUESTED: 'REVIEW_REQUESTED',
} as const

export type ConsolidatedReviewState = (typeof ConsolidatedReviewState)[keyof typeof ConsolidatedReviewState]

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
  consolidatedFailureReasons,
  helpUrl,
  latestOpinionatedReviews,
  numReviewsRequired,
  pendingRequestedReviews,
  pullRequestId,
  reviewsState,
  viewerCanDismissReviews,
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

  const DOCS_URL = `${helpUrl}/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/requesting-a-pull-request-review`

  const reviewSectionSubtitle = (reviewState: ConsolidatedReviewState): JSX.Element | string => {
    switch (reviewState) {
      case ConsolidatedReviewState.REVIEW_REQUIRED:
        return `${reviewRequiredSummary(
          numReviewsRequired,
          consolidatedFailureReasons,
        )} by reviewers with write access.`
      case ConsolidatedReviewState.REVIEW_REQUESTED:
        return (
          <>
            Review has been requested on this pull request. It is not required to merge.{' '}
            <Link inline href={DOCS_URL} className={clsx(styles.subtitleLink, 'position-relative')}>
              Learn more about requesting a pull request review.
            </Link>
          </>
        )
      default:
        return `${accessibleReviewSummary(latestOpinionatedReviews)} by reviewers with write access.`
    }
  }

  const REVIEW_SECTION_STATUSES: Record<
    ConsolidatedReviewState,
    {
      heading: string
      subtitle: JSX.Element | string
      icon: JSX.Element
    }
  > = {
    APPROVED: {
      heading: 'Changes approved',
      subtitle: reviewSectionSubtitle(ConsolidatedReviewState.APPROVED),
      icon: (
        <CircleOcticon
          className="bgColor-success-emphasis fgColor-onEmphasis"
          icon={() => <CheckIcon size={16} />}
          size={HEADER_ICON_SIZE}
        />
      ),
    },
    CHANGES_REQUESTED: {
      heading: 'Changes requested',
      subtitle: reviewSectionSubtitle(ConsolidatedReviewState.CHANGES_REQUESTED),
      icon: (
        <CircleOcticon
          className="bgColor-danger-emphasis fgColor-onEmphasis"
          icon={() => <FileDiffIcon size={16} />}
          size={HEADER_ICON_SIZE}
        />
      ),
    },
    REVIEW_REQUIRED: {
      heading: 'Review required',
      subtitle: reviewSectionSubtitle(ConsolidatedReviewState.REVIEW_REQUIRED),
      icon: (
        <CircleOcticon
          className="bgColor-danger-emphasis fgColor-onEmphasis"
          icon={() => <XIcon size={16} />}
          size={HEADER_ICON_SIZE}
        />
      ),
    },
    REVIEWED: {
      heading: 'Changes reviewed',
      subtitle: reviewSectionSubtitle(ConsolidatedReviewState.REVIEWED),
      icon: (
        <CircleOcticon
          className={clsx(styles.reviewedIcon, 'fgColor-onEmphasis')}
          icon={() => <CodeReviewIcon size={16} />}
          size={HEADER_ICON_SIZE}
        />
      ),
    },
    REVIEW_REQUESTED: {
      heading: 'Review requested',
      subtitle: reviewSectionSubtitle(ConsolidatedReviewState.REVIEW_REQUESTED),
      icon: (
        <CircleOcticon
          className="bgColor-success-emphasis fgColor-onEmphasis"
          icon={() => <CheckIcon size={16} />}
          size={HEADER_ICON_SIZE}
        />
      ),
    },
  }

  return (
    <section aria-label="Reviews" aria-describedby={reviewsSectionAriaId} className="border-bottom color-border-subtle">
      <MergeBoxSectionHeader
        headerId={reviewsSectionAriaId}
        title={REVIEW_SECTION_STATUSES[reviewsState].heading}
        subtitle={REVIEW_SECTION_STATUSES[reviewsState].subtitle}
        icon={REVIEW_SECTION_STATUSES[reviewsState].icon}
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
            reviewGroup={ReviewGroup.Approvals}
            opinionatedReviews={approvedReviews}
            pullRequestId={pullRequestId}
            viewerCanReRequestReviews={viewerCanReRequestReviews}
          />
          <OpinionatedReviewsGroup
            viewerCanDismissReviews={viewerCanDismissReviews}
            reviewGroup={ReviewGroup.RequestedChanges}
            opinionatedReviews={requestedChangesReviews}
            pullRequestId={pullRequestId}
            viewerCanReRequestReviews={viewerCanReRequestReviews}
          />
          <PendingRequestedReviewsGroup
            reviewGroup={ReviewGroup.PendingReviewRequest}
            viewerCanDismissReviews={viewerCanDismissReviews}
            pendingRequestedReviews={pendingRequestedReviews}
            pullRequestId={pullRequestId}
          />
        </div>
      </MergeBoxExpandable>
    </section>
  )
}
