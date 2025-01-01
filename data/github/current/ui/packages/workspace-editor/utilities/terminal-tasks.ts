import type {CommandResult} from './terminal-reducer'
import type {TerminalTasks} from './workspace-editor-types'

export function getCommands(tasks: TerminalTasks): Array<{name: string; command: string}> {
  return Object.entries(tasks)
    .filter(([_, value]) => !!value)
    .map(([key, value]) => ({
      name: key.charAt(0).toUpperCase() + key.slice(1),
      command: value,
    }))
}

export function getFirstCommand(tasks: TerminalTasks): {name: string; command: string} | undefined {
  return getCommands(tasks)[0]
}

export function hasAnyCommands(tasks: TerminalTasks): boolean {
  return !!getFirstCommand(tasks)
}

export function activeCommand(command: CommandResult): string {
  switch (command.buildTask) {
    case 'Build':
      return 'Building...'
    case 'Run':
      return 'Running...'
    case 'Test':
      return 'Testing...'
    default:
      return 'Executing...'
  }
}
