import {Box} from '@primer/react'
import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'

export function ParticipantsListLoading() {
  return (
    <Box sx={{m: 2, display: 'flex', flexDirection: 'column', gap: 2}}>
      <IssuesLoadingSkeleton height="md" width="60%" />
      <IssuesLoadingSkeleton height="md" width="80%" />
      <IssuesLoadingSkeleton height="md" width="40%" />
      <IssuesLoadingSkeleton height="md" width="60%" />
      <IssuesLoadingSkeleton height="md" width="70%" />
    </Box>
  )
}
