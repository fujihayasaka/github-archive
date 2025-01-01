import type {CommandResult} from './terminal-reducer'
import {CommandTask} from './terminal-reducer'
import type {TerminalTasks} from './workspace-editor-types'

const VALID_TASKS = ['build', 'run', 'test']

export function getCommands(tasks: TerminalTasks): Array<{task: CommandTask; command: string}> {
  return Object.entries(tasks)
    .filter(([key, value]) => !!value && VALID_TASKS.includes(key))
    .map(([key, value]) => {
      let task: CommandTask
      if (key === 'build') {
        task = CommandTask.Build
      } else if (key === 'run') {
        task = CommandTask.Run
      } else {
        task = CommandTask.Test
      }

      return {
        task,
        command: value,
      }
    })
}

export function getCommandForTask(tasks: TerminalTasks, task: CommandTask): string | undefined {
  return getCommands(tasks).find(command => command.task === task)?.command
}

export function getFirstCommand(tasks: TerminalTasks): {task: CommandTask; command: string} | undefined {
  return getCommands(tasks)[0]
}

export function hasAnyCommands(tasks: TerminalTasks): boolean {
  return !!getFirstCommand(tasks)
}

export function activeCommand(command: CommandResult): string {
  switch (command.task) {
    case CommandTask.Build:
      return 'Building...'
    case CommandTask.Run:
      return 'Running...'
    case CommandTask.Test:
      return 'Testing...'
    default:
      return 'Executing...'
  }
}
