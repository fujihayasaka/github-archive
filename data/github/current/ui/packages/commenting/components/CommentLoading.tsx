import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {Box} from '@primer/react'
import {useMemo} from 'react'

import {TEST_IDS} from '../constants/test-ids'
import {CommentDivider} from './CommentDivider'

type CommentLoadingProps = {
  inHighlightedTimeline?: boolean
}

export const CommentLoading = ({inHighlightedTimeline}: CommentLoadingProps) => {
  const lineCount = useMemo(() => Math.floor(Math.random() * 5) + 1, [])

  const baseAvatarLoadingSx = {
    mt: 4,
  }

  const avatarLoadingSx = inHighlightedTimeline
    ? {...baseAvatarLoadingSx, display: ['none', 'none', 'flex', 'flex']}
    : baseAvatarLoadingSx

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'row',
        gap: 3,
      }}
    >
      <LoadingSkeleton variant="elliptical" height="40px" width="40px" sx={avatarLoadingSx} />
      <Box sx={{display: 'flex', flexDirection: 'column', flexGrow: 1}}>
        <CommentDivider />
        <Box
          sx={{
            border: '1px solid',
            borderColor: 'neutral.muted',
            borderRadius: 6,
            backgroundColor: 'canvas.default',
            boxShadow: 'shadow.small',
            overflowX: 'auto',
            flexGrow: 1,
            p: 3,
            display: 'flex',
            flexDirection: 'column',
            gap: 3,
          }}
          data-testid={TEST_IDS.commentSkeleton}
        >
          <Box sx={{flexDirection: 'row', alignItems: 'center', display: 'flex'}}>
            <LoadingSkeleton variant="rounded" height="sm" width="150px" />
          </Box>
          <Box sx={{display: 'flex', gap: 2, flexDirection: 'column'}}>
            {[...Array(lineCount)].map((_, index) => (
              // eslint-disable-next-line @eslint-react/no-array-index-key
              <LoadingSkeleton key={index} variant="rounded" height="sm" width="random" />
            ))}
          </Box>
        </Box>
      </Box>
    </Box>
  )
}
