import type {CommandResult} from './terminal-reducer'

export const generateCommandStatusText = (
  command: CommandResult,
  commandExecuted: boolean,
  commandDuration: string,
  commandForTask?: string,
): string | undefined => {
  const {stopped, startTime} = command

  // If the command is stopped, we will never need to show anything else
  if (stopped) {
    return 'Canceled'
  }

  // If the command is executed but not started, show connecting
  // Otherwise, show the duration
  if (commandExecuted) {
    if (!startTime) {
      return 'Connecting...'
    }

    return commandDuration
  }

  // Show the command for the task (or the lack thereof)
  return commandForTask
}
