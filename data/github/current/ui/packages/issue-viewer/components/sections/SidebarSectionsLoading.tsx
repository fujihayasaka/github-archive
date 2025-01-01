import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {Box} from '@primer/react'

export const SidebarSectionsLoading = () => {
  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: 2}}>
      <IssuesLoadingSkeleton height="md" width="60%" />
      <IssuesLoadingSkeleton height="md" width="80%" />
      <IssuesLoadingSkeleton height="md" width="40%" />
      <IssuesLoadingSkeleton height="md" width="60%" />
      <IssuesLoadingSkeleton height="md" width="70%" />
      <IssuesLoadingSkeleton height="md" width="50%" />
    </Box>
  )
}
