import type {OpinionatedReview} from '../../../types'
import {ReviewListItem} from './ReviewListItem'
import {userHovercardPath} from '@github-ui/paths'

const joinWithAnd = (items: string[]) => {
  if (items.length === 0) {
    return ''
  } else if (items.length === 1) {
    return items[0]
  } else if (items.length === 2) {
    return items.join(' and ')
  } else {
    const last = items.pop()
    return `${items.join(', ')}, and ${last}`
  }
}

const reviewStatusText = (state: string, onBehalfOf: string[], readOnly: boolean) => {
  let statusText = ''
  switch (state) {
    case 'APPROVED':
      statusText += 'Approved these changes'
      break
    case 'CHANGES_REQUESTED':
      statusText += 'Requested changes'
      break
    case 'COMMENTED':
      statusText += 'Commented'
      break
  }
  if (readOnly) {
    statusText += ' with read-only permissions'
  }
  if (state === 'APPROVED' && onBehalfOf.length > 0) {
    statusText += ` for ${joinWithAnd(onBehalfOf)}`
  }
  return statusText
}

export function OpinionatedReviewRow({
  review,
  viewerCanDismissReviews,
  refetchMergeBoxQuery,
  viewerCanReRequestReviews,
}: {
  review: OpinionatedReview
  viewerCanDismissReviews: boolean
  refetchMergeBoxQuery: () => void
  viewerCanReRequestReviews?: boolean
}) {
  const {author} = review
  if (!author) return null

  return (
    <ReviewListItem
      reviewer={author}
      reviewId={review.id}
      refetchMergeBoxQuery={refetchMergeBoxQuery}
      reviewStatusText={reviewStatusText(review.state, review.onBehalfOf, !review.authorCanPushToRepository)}
      hovercardUrl={userHovercardPath({owner: author.login})}
      viewerCanDismissReviews={viewerCanDismissReviews}
      viewerCanReRequestReviews={viewerCanReRequestReviews}
    />
  )
}
