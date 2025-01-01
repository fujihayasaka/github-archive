import {ListView} from '@github-ui/list-view'

import {ReviewGroupExpander} from './ReviewGroupExpander'
import type {OpinionatedReview, ReviewGroup} from '../../../types'
import {OpinionatedReviewRow} from './OpinionatedReviewRow'

export type OpinionatedReviewsGroupProps = {
  opinionatedReviews: OpinionatedReview[]
  pullRequestId: string
  reviewGroup: Exclude<ReviewGroup, typeof ReviewGroup.PendingReviewRequest>
  viewerCanDismissReviews: boolean
  viewerCanReRequestReviews?: boolean
}

export function OpinionatedReviewsGroup({
  opinionatedReviews,
  pullRequestId,
  reviewGroup,
  viewerCanDismissReviews,
  viewerCanReRequestReviews,
}: OpinionatedReviewsGroupProps) {
  if (opinionatedReviews.length === 0) return null

  return (
    <ReviewGroupExpander count={opinionatedReviews.length} reviewGroup={reviewGroup} pullRequestId={pullRequestId}>
      <ListView title={`list of ${reviewGroup}`} titleHeaderTag="h3">
        {opinionatedReviews.map(review => (
          <OpinionatedReviewRow
            key={`opinionated-review-from-${review?.author?.name}`}
            review={review}
            viewerCanDismissReviews={viewerCanDismissReviews}
            viewerCanReRequestReviews={viewerCanReRequestReviews}
          />
        ))}
      </ListView>
    </ReviewGroupExpander>
  )
}
