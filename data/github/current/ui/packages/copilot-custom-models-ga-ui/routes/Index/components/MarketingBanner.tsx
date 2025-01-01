import {Box, Heading, Text} from '@primer/react'
import {GreenBars} from './GreenBars'
import {theme} from '../../../theme'

export function MarketingBanner() {
  return (
    <Box
      sx={{
        border: theme.border,
        borderRadius: '6px',
        p: '24px',
        display: 'flex',
        flexDirection: 'column',
        gap: '8px',
        justifyContent: 'center',
        width: '100%',
      }}
    >
      <GreenBars />
      <Heading as="h2" sx={{...theme.typography.title.medium}}>
        Improve acceptance rate
      </Heading>
      <Text sx={{color: theme.color.fgMuted, ...theme.typography.body.medium}}>
        Should we add some proof here and tell people why they should even go through this process.
      </Text>
    </Box>
  )
}
