import {Box, Text} from '@primer/react'
import {theme} from '../../../theme'

export function HowItWorksItem() {
  return (
    <Box sx={{alignItems: 'center', display: 'flex', gap: '24px', justifyContent: 'center', width: '100%'}}>
      <GrayBox />

      <Box sx={{display: 'flex', flexDirection: 'column', gap: '4px', justifyContent: 'center', width: '100%'}}>
        <Text sx={{color: theme.color.fgDefault, ...theme.typography.title.small}}>Prepare your training data</Text>
        <Text sx={{color: theme.color.fgMuted, ...theme.typography.body.medium}}>
          Start fine tuning your first model
        </Text>
      </Box>
    </Box>
  )
}

function GrayBox() {
  return <Box sx={{backgroundColor: '#E8ECF2', borderRadius: '6px', height: '100px', width: '145px'}} />
}
