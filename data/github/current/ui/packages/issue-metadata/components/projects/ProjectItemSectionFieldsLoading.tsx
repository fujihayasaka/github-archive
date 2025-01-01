import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {Box} from '@primer/react'

export function ProjectItemSectionFieldsLoading() {
  return (
    <Box as="li" sx={{mt: 0, mx: 2, mb: 2, ml: 3}}>
      <ProjectFieldLoading />
      <ProjectFieldLoading />
      <ProjectFieldLoading />
    </Box>
  )
}

function ProjectFieldLoading() {
  return (
    <Box sx={{display: 'flex', flexDirection: 'row', alignItems: 'flex-start', gap: 5, width: '100%', mt: 2}}>
      <IssuesLoadingSkeleton height="md" width="25%" />
      <IssuesLoadingSkeleton height="md" width="40%" />
    </Box>
  )
}
