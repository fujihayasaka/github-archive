import {Box, Spinner, type BetterSystemStyleObject} from '@primer/react'

export function CenteredLoadingSpinner({sx}: {sx?: BetterSystemStyleObject}): JSX.Element {
  return (
    <Box
      sx={{
        alignItems: 'center',
        display: 'flex',
        flexDirection: 'row',
        justifyContent: 'center',
        mt: 6,
        width: '100%',
        ...sx,
      }}
    >
      <Spinner />
    </Box>
  )
}
