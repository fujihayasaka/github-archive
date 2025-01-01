import {userHovercardPath, teamHovercardPath} from '@github-ui/paths'

import type {PendingReviewRequest} from '../../../types'
import {ReviewListItem} from './ReviewListItem'

export function RequestedReviewRow({reviewRequest}: {reviewRequest: PendingReviewRequest}) {
  const {reviewer} = reviewRequest

  if (!reviewer) return null

  let hovercardUrl = ''
  // Requested reviews can have team reviewers, so handle the hovercard URL differently
  if (reviewer.type === 'TEAM') {
    // Team login returns string shaped like "{owner}/{team-name}"
    const owner = reviewer.login.split('/')[0] ?? ''
    hovercardUrl = teamHovercardPath({owner, team: reviewer.name})
  } else {
    hovercardUrl = userHovercardPath({owner: reviewer.login})
  }

  let statusText = 'was requested for review'
  if (reviewRequest.isCodeOwner) {
    statusText += ' as a codeowner'
  }

  return (
    <ReviewListItem
      showReviewOptions={false}
      reviewer={reviewer}
      reviewStatusText={statusText}
      hovercardUrl={hovercardUrl}
    />
  )
}
