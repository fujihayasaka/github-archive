import {Box, Heading} from '@primer/react'
import {LABELS} from '../../constants/labels'
export function AppTitle() {
  return (
    <Box sx={{display: 'flex', alignItems: 'center', gap: 2}}>
      <Heading id="sidebar-title" as="h2" sx={{fontSize: 3}}>
        <span>{LABELS.appHeader}</span>
      </Heading>
    </Box>
  )
}
