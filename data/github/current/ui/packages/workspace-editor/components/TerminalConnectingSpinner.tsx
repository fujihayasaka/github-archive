import {Spinner} from '@primer/react'
import type React from 'react'

import {TerminalStatus} from '../utilities/terminal-types'
import styles from './TerminalConnectingSpinner.module.css'

interface ITerminalConnectingSpinnerProps {
  terminalStatus: TerminalStatus
}

export const TerminalConnectingSpinner: React.FC<ITerminalConnectingSpinnerProps> = props => {
  const {terminalStatus} = props

  if (terminalStatus !== TerminalStatus.Connecting) {
    return
  }

  return (
    <div className={styles.Box}>
      <Spinner size="small" />
      Connecting to terminal...
    </div>
  )
}
