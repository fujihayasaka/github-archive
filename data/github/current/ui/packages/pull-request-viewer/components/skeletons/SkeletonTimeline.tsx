import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {wrapElement} from '@github-ui/timeline-items/LayoutHelpers'
import {Box} from '@primer/react'

export function SkeletonTimeline() {
  return wrapElement(
    <Box sx={{display: 'flex', flexDirection: 'column', gap: 2, flexGrow: 1}}>
      <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'center', gap: 2}}>
        <LoadingSkeleton height="sm" variant="rounded" width="140px" />
      </Box>
      <LoadingSkeleton height="md" variant="rounded" width="random" />
      <LoadingSkeleton height="md" variant="rounded" width="random" />
    </Box>,
    <LoadingSkeleton height="xl" sx={{display: ['none', 'none', 'flex', 'flex']}} variant="elliptical" width="xl" />,
  )
}
