import {ReviewGroupExpander} from './ReviewGroupExpander'
import type {PendingReviewRequest, ReviewGroup} from '../../../types'
import {RequestedReviewRow} from './RequestedReviewRow'
import {ListView} from '@github-ui/list-view'

export type PendingRequestedReviewsGroupProps = {
  pendingRequestedReviews: PendingReviewRequest[]
  reviewGroup: Exclude<ReviewGroup, ReviewGroup.PendingReviewRequest & ReviewGroup.RequestedChanges>
  refetchMergeBoxQuery: () => void
  viewerCanDismissReviews: boolean
}

export function PendingRequestedReviewsGroup({
  pendingRequestedReviews,
  reviewGroup,
}: PendingRequestedReviewsGroupProps) {
  if (pendingRequestedReviews.length === 0) return null

  return (
    <ReviewGroupExpander count={pendingRequestedReviews.length} reviewGroup={reviewGroup}>
      <ListView title={`list of ${reviewGroup}`}>
        {pendingRequestedReviews.map(reviewRequest => (
          <RequestedReviewRow
            key={`requested-review-from-${reviewRequest?.reviewer?.name}`}
            reviewRequest={reviewRequest}
          />
        ))}
      </ListView>
    </ReviewGroupExpander>
  )
}
