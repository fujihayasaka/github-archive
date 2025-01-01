import {CheckCircleFillIcon, IssueDraftIcon, SkipFillIcon, XCircleFillIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'

import type {CommandResult} from '../utilities/terminal-reducer'

interface TerminalCommandStatusIconProps {
  command: CommandResult
}

const TerminalCommandStatusIcon: React.FC<TerminalCommandStatusIconProps> = ({command}) => {
  const {exitCode, channel, loading, stopped} = command
  const statusIcon = stopped ? (
    <SkipFillIcon className="fgColor-muted" />
  ) : exitCode === 0 ? (
    <CheckCircleFillIcon className="fgColor-success" />
  ) : exitCode ? (
    <XCircleFillIcon className="fgColor-danger" />
  ) : channel || loading ? (
    <Spinner size="small" />
  ) : (
    <IssueDraftIcon className="fgColor-muted" />
  )

  return statusIcon
}

export default TerminalCommandStatusIcon
