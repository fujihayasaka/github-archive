import {ReviewGroupExpander} from './ReviewGroupExpander'
import type {PendingReviewRequest, ReviewGroup} from '../../../types'
import {RequestedReviewRow} from './RequestedReviewRow'
import {ListView} from '@github-ui/list-view'

export type PendingRequestedReviewsGroupProps = {
  pendingRequestedReviews: PendingReviewRequest[]
  pullRequestId: string
  reviewGroup: Exclude<ReviewGroup, typeof ReviewGroup.PendingReviewRequest & typeof ReviewGroup.RequestedChanges>
  viewerCanDismissReviews: boolean
}

export function PendingRequestedReviewsGroup({
  pendingRequestedReviews,
  pullRequestId,
  reviewGroup,
}: PendingRequestedReviewsGroupProps) {
  if (pendingRequestedReviews.length === 0) return null

  return (
    <ReviewGroupExpander count={pendingRequestedReviews.length} reviewGroup={reviewGroup} pullRequestId={pullRequestId}>
      <ListView title={`list of ${reviewGroup}`} titleHeaderTag="h3">
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
