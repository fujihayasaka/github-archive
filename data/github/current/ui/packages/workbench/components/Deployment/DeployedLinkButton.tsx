import {GlobeIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'

import {CommandTask} from '../../../workspace-editor/utilities/terminal-reducer'
import {useTerminalContext} from '../../contexts/TerminalContext'

export const DeployedLinkButton = () => {
  const {
    state: {history},
  } = useTerminalContext()
  const buildCommand = history[CommandTask.Build]
  const {exitCode, channel, output, loading} = buildCommand

  const hasCommandExecuted = channel != null || exitCode != null || loading
  const urlMatches = output.match(/https:\/\/.*\.github\.app/)

  if (!hasCommandExecuted || !urlMatches) {
    return <IconButton aria-label={`View the Spark once deployed`} as={'button'} icon={GlobeIcon} disabled />
  }

  const url = urlMatches[0]
  return <IconButton aria-label={`View the deployed Spark`} icon={GlobeIcon} as="a" href={url} target="_blank" />
}
