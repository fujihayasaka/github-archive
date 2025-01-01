import {IssuesLoadingSkeleton} from '@github-ui/issues-loading-skeleton'
import {Box} from '@primer/react'

export const HeaderLoading = () => {
  return (
    <>
      <Box sx={{display: 'flex', justifyContent: 'space-between', paddingBottom: 2}}>
        <IssuesLoadingSkeleton height="xl" width="400px" />
      </Box>
      <Box sx={{display: 'flex', alignItems: 'center', flexDirection: 'row', gap: 2, paddingTop: '14px'}}>
        <IssuesLoadingSkeleton borderRadius="pill" height="xl" width="80px" />
        <IssuesLoadingSkeleton height="lg" width="200px" />
      </Box>
    </>
  )
}
