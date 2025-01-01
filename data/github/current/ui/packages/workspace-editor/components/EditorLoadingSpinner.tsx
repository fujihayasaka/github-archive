import {Box, Spinner} from '@primer/react'

export function EditorLoadingSpinner() {
  return (
    <Box sx={{alignSelf: 'flex-start', pt: 3}}>
      <Spinner />
    </Box>
  )
}
