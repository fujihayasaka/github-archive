import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {Box} from '@primer/react'

export const MetadataFooterLoading = () => {
  return (
    <Box sx={{display: 'flex', justifyContent: 'space-between'}}>
      <IssuesLoadingSkeleton borderRadius="pill" height="lg" width="400px" />
    </Box>
  )
}
