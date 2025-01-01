import {Flash} from '@primer/react'

export const EmuContributionBlockedBanner = () => {
  return (
    <Flash
      sx={{mt: '16px'}}
      variant={'warning'}
      data-jump-to-bottom-target
      tabIndex={-1}
      id="emu-contribution-blocked-banner"
    >{`You cannot contribute to repositories outside of your enterprise.`}</Flash>
  )
}
