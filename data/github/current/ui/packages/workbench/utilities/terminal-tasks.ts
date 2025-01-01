import type {TerminalTasks} from '@github-ui/workspace-editor/utilities/workspace-editor-types'

import type {CommandResult} from './terminal-reducer'
import {CommandTask} from './terminal-reducer'

const VALID_TASKS = ['build', 'deploy']

export function getCommands(tasks: TerminalTasks): Array<{task: CommandTask; command: string}> {
  return Object.entries(tasks)
    .filter(([key, value]) => !!value && VALID_TASKS.includes(key))
    .map(([key, value]) => {
      let task: CommandTask
      if (key === 'deploy') {
        task = CommandTask.Deploy
      } else {
        task = CommandTask.Build
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
    case CommandTask.Deploy:
      return 'Deploying...'
    default:
      return 'Executing...'
  }
}
