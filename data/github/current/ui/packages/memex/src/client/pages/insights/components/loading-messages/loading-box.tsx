import {Box} from '@primer/react'

// LoadingBox is the styled Box component to be used for all loading messages.
export const LoadingBox = ({children}: {children: React.ReactNode}) => {
  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexDirection: 'column',
        gap: 1,
        borderWidth: 1,
        borderRadius: 2,
        borderStyle: 'solid',
        borderColor: 'border.default',
        minHeight: '526px', // match height of charts with data
        padding: 4,
      }}
    >
      {children}
    </Box>
  )
}
