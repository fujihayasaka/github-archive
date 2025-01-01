import {AlertIcon} from '@primer/octicons-react'
import {Flash, type BetterSystemStyleObject} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {Spacing} from '../../utils/style'

export function ErrorBanner({message, sx}: {message: string; sx?: BetterSystemStyleObject}) {
  return (
    <Flash sx={{mb: Spacing.CardMargin, ...sx}} variant="danger">
      <Octicon aria-label="Alert icon" icon={AlertIcon} />
      {message}
    </Flash>
  )
}
