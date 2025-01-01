import {wrapElement} from '@github-ui/timeline-items/LayoutHelpers'
import {Box} from '@primer/react'

import {SkeletonFilesChangedListing} from './SkeletonFilesChangedListing'
import {SkeletonTimeline} from './SkeletonTimeline'

export function SkeletonPullRequestSummarySecondaryContent() {
  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: 5}}>
      {wrapElement(<SkeletonFilesChangedListing />, undefined, undefined)}
      <Box sx={{display: 'flex', flexDirection: 'column', gap: 4}}>
        <SkeletonTimeline />
        <SkeletonTimeline />
        <SkeletonTimeline />
      </Box>
    </Box>
  )
}
