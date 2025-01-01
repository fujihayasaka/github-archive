import {Flash} from '@primer/react'

export const EmuContributionBlockedBanner = () => {
  return (
    <Flash
      sx={{mt: '16px'}}
      variant={'warning'}
    >{`You cannot contribute to repositories outside of your enterprise.`}</Flash>
  )
}
