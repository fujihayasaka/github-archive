import {Box} from '@primer/react'
import {AssessingStep} from './AssessingStep'
import {CacheIcon, RepoIcon} from '@primer/octicons-react'

export function AssessingSteps() {
  return (
    <Box sx={{display: 'flex', flexDirection: 'column', gap: '4px'}}>
      <AssessingStep Icon={CacheIcon} text="Analyzing telemetry" />
      <AssessingStep Icon={RepoIcon} text="Next: Selected repos" />
    </Box>
  )
}
