import {ListView} from '@github-ui/list-view'

import {ReviewGroupExpander} from './ReviewGroupExpander'
import type {OpinionatedReview, ReviewGroup} from '../../../types'
import {OpinionatedReviewRow} from './OpinionatedReviewRow'

export type OpinionatedReviewsGroupProps = {
  opinionatedReviews: OpinionatedReview[]
  reviewGroup: Exclude<ReviewGroup, ReviewGroup.PendingReviewRequest>
  viewerCanDismissReviews: boolean
  refetchMergeBoxQuery: () => void
  viewerCanReRequestReviews?: boolean
}

export function OpinionatedReviewsGroup({
  opinionatedReviews,
  reviewGroup,
  viewerCanDismissReviews,
  refetchMergeBoxQuery,
  viewerCanReRequestReviews,
}: OpinionatedReviewsGroupProps) {
  if (opinionatedReviews.length === 0) return null

  return (
    <ReviewGroupExpander count={opinionatedReviews.length} reviewGroup={reviewGroup}>
      <ListView title={`list of ${reviewGroup}`}>
        {opinionatedReviews.map(review => (
          <OpinionatedReviewRow
            refetchMergeBoxQuery={refetchMergeBoxQuery}
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
