import {Box, Spinner} from '@primer/react'
import type React from 'react'

import {TerminalStatus} from '../utilities/terminal-types'

interface ITerminalConnectingSpinnerProps {
  terminalStatus: TerminalStatus
}

export const TerminalConnectingSpinner: React.FC<ITerminalConnectingSpinnerProps> = props => {
  const {terminalStatus} = props

  if (terminalStatus !== TerminalStatus.Connecting) {
    return
  }

  return (
    <Box
      sx={{
        display: 'flex',
        gap: 2,
        alignItems: 'center',
        p: 3,
        color: 'fg.muted',
        fontFamily: 'var(--fontStack-sansSerif)',
      }}
    >
      <Spinner size="small" /> Connecting to terminal...
    </Box>
  )
}
