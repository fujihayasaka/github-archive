import {CommandTask} from '../../../workspace-editor/utilities/terminal-reducer'
import {useTerminalContext} from '../../contexts/TerminalContext'

export const DeploymentOutput = () => {
  const {
    state: {history},
  } = useTerminalContext()

  const command = history[CommandTask.Build]
  const {exitCode, channel, output, loading} = command

  // If the command is running or has completed, the channel should be set
  const commandExecuted = channel != null || exitCode != null || loading

  if (command === undefined) {
    return <></>
  }

  return (
    <div className="d-flex flex-column rounded-2 bgColor">
      {commandExecuted ? (
        <pre className="text-mono px-3 py-2">{output}</pre>
      ) : (
        <div className="px-3 py-2">No deployment run</div>
      )}
    </div>
  )
}
