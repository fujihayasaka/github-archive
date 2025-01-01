import {ConsolidatedReviewState} from '../../components/sections/ReviewerSection'
import type {
  PendingReviewRequest,
  PullRequestReviewState,
  PullRequestRuleFailureReason,
  ReviewerRuleRollup,
} from '../../types'
import {getReviewRuleRollupMetadata} from '../json-api-helpers'
import {BaseSectionStatus} from './base-section-status'

export class ReviewerSectionStatus extends BaseSectionStatus<ConsolidatedReviewState> {
  #reviewRules: ReviewerRuleRollup[] | undefined
  #consolidatedFailureReasons: PullRequestRuleFailureReason[] | undefined

  override get shouldRender() {
    if (this.pullRequest.mergeStateStatus === 'DIRTY') return false
    if (this.pullRequest.mergeStateStatus === 'UNKNOWN') return false

    return (
      this.latestOpinionatedReviews.length > 0 ||
      this.pendingRequestedReviews.length > 0 ||
      this.consolidatedFailureReasons.length > 0
    )
  }

  override get sectionStatus() {
    return getReviewsState(
      this.numReviewsRequired,
      this.codeownersRequired,
      this.latestOpinionatedReviews,
      this.consolidatedFailureReasons,
      this.pendingRequestedReviews,
    )
  }

  override get mergeBoxStatus() {
    switch (this.sectionStatus) {
      case ConsolidatedReviewState.APPROVED:
      case ConsolidatedReviewState.REVIEW_REQUESTED:
      case ConsolidatedReviewState.REVIEWED:
        return 'PASSED'
      case ConsolidatedReviewState.CHANGES_REQUESTED:
        return 'FAILED'
      case ConsolidatedReviewState.REVIEW_REQUIRED:
      default:
        return 'NEUTRAL'
    }
  }

  get numReviewsRequired() {
    const requiredReviewCounts = this.reviewRules?.flatMap(rule => rule.requiredReviewers || []) || []
    return requiredReviewCounts.length ? Math.max(...requiredReviewCounts) : 0
  }

  get consolidatedFailureReasons() {
    if (!this.#consolidatedFailureReasons) {
      const allFailureReasons = this.reviewRules?.flatMap(rule => rule.failureReasons || []) || []
      this.#consolidatedFailureReasons = [...new Set(allFailureReasons)].filter(isReviewRelatedFailureReason)
    }

    return this.#consolidatedFailureReasons
  }

  private get reviewRules() {
    if (!this.#reviewRules) {
      this.#reviewRules = getReviewRuleRollupMetadata(this.mergeRequirements)
    }

    return this.#reviewRules
  }

  private get codeownersRequired(): boolean {
    const codeownersRequiredRules = this.reviewRules?.filter(rule => rule.requiresCodeowners) || []
    return codeownersRequiredRules.length > 0
  }

  private get latestOpinionatedReviews() {
    return this.pullRequest.latestOpinionatedReviews
  }

  private get pendingRequestedReviews() {
    return this.pullRequest.pendingReviewRequests
  }
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

/**
 * Calculates the reviewer section state
 */
export const getReviewsState = (
  reviewsRequired: number,
  isCodeownersRequired: boolean,
  reviews: Array<{
    authorCanPushToRepository: boolean
    state: PullRequestReviewState
  }>,
  failureReasons: PullRequestRuleFailureReason[],
  pendingRequestedReviews: PendingReviewRequest[],
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
  if (reviewsRequired === 0 && pendingRequestedReviews.length > 0 && reviews.length === 0) {
    return ConsolidatedReviewState.REVIEW_REQUESTED
  }
  // we can assume if we fall through to here that there is a review because if
  // no reviews are required and we have none, we return early and don't render
  return ConsolidatedReviewState.REVIEWED
}
