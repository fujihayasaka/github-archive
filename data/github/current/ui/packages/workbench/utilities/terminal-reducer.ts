import type {ConnectedCodespaceData, TerminalTasks} from '@github-ui/workspace-editor/utilities/workspace-editor-types'

export interface TerminalReducer {}

export type TerminalAction =
  | {
      type: 'TOGGLE_TERMINAL_IS_COLLAPSED'
      isCollapsed: boolean
    }
  | ({type: 'UPDATE_COMMAND'; task: CommandTask} & Partial<CommandResult>)
  | {type: 'START_COMMAND'; command: CommandResult}
  | {type: 'RERUN_COMMAND'; command: CommandResult}
  | {type: 'TOGGLE_TERMINAL_PANE'; pane: Pane}
  | {type: 'COMPLETE_COMMAND'; exitCode: number; task: CommandTask}
  | {type: 'COLLAPSE_COMMAND'; task: CommandTask}
  | {type: 'EXPAND_COMMAND'; task: CommandTask}
  | {type: 'CLEAR_TASK'; task: CommandTask; command?: string}
  | {type: 'SET_TASK'; task: CommandTask; command: string}
  | {type: 'SET_TASKS'; tasks: TerminalTasks}
  | {type: 'SET_CODESPACE_DATA'; codespaceData: ConnectedCodespaceData}
  | {type: 'SET_PREVIEW_URL'; previewUrl: string | undefined}

export type TerminalState = {
  isCollapsed: boolean
  pane: Pane
  history: Record<CommandTask, CommandResult>
  tasks: TerminalTasks
  codespaceData: ConnectedCodespaceData
  previewUrl: string | undefined
}

type Channel = {
  stop: (signal: 'INT' | 'TERM') => void
}

export const CommandTask = {
  Build: 0,
  Deploy: 1,
  Commit: 2,
} as const

export type CommandTask = (typeof CommandTask)[keyof typeof CommandTask]

export type CommandResult = {
  task: CommandTask
  command: string
  exitCode: number | null
  output: string
  collapsed: boolean
  channel: Channel | null
  loading: boolean
  stopped: boolean
  startTime: Date | null
  endTime: Date | null
}
export type Pane = 'output' | 'terminal'

export function terminalReducer(state: TerminalState, action: TerminalAction): TerminalState {
  switch (action.type) {
    case 'TOGGLE_TERMINAL_IS_COLLAPSED': {
      const {isCollapsed} = action
      return {...state, isCollapsed}
    }
    case 'TOGGLE_TERMINAL_PANE': {
      const {pane} = action
      return {...state, pane}
    }
    case 'COMPLETE_COMMAND': {
      const {history} = state
      const {task, exitCode} = action
      const updatedCommand = {...history[task], exitCode, channel: null, endTime: new Date()}
      const newHistory = {...history, [task]: updatedCommand}
      return {...state, history: newHistory}
    }
    case 'START_COMMAND': {
      const {task} = action.command
      const history = {...state.history, [task]: action.command}

      return {...state, history}
    }
    case 'UPDATE_COMMAND': {
      // Eat the type property from action so that it's not included in update
      const {type, task, ...update} = action
      const existingCommand = state.history[task]
      const updatedCommand = {...state.history[task], ...update}

      // If the command was stopped while we were fetching the channel, immediately interrupt it and don't accept updates (i.e. output) for it
      if (existingCommand.stopped && updatedCommand.channel) {
        updatedCommand.channel.stop('INT')
        return state
      }

      const history = {...state.history, [task]: updatedCommand}
      return {...state, history}
    }
    case 'COLLAPSE_COMMAND': {
      return terminalReducer(state, {type: 'UPDATE_COMMAND', task: action.task, collapsed: true})
    }
    case 'EXPAND_COMMAND': {
      return terminalReducer(state, {type: 'UPDATE_COMMAND', task: action.task, collapsed: false})
    }
    case 'CLEAR_TASK': {
      const {task, command} = action
      const history = {...state.history}
      history[task] = clearTask(task, command)
      return {...state, history}
    }
    case 'SET_TASK': {
      const {task, command} = action
      const tasks = {...state.tasks}
      switch (task) {
        case CommandTask.Build:
          tasks.build = command
          break
        case CommandTask.Deploy:
          tasks.run = command
          break
        default:
          break
      }

      // Clear any previous output/exit codes since the task has changed
      const updatedState = terminalReducer(state, {type: 'CLEAR_TASK', task, command})

      return {...updatedState, tasks}
    }
    case 'SET_TASKS': {
      return {...state, tasks: action.tasks}
    }
    case 'SET_CODESPACE_DATA': {
      const {codespaceData} = action
      return {...state, codespaceData}
    }
    case 'SET_PREVIEW_URL': {
      const {previewUrl} = action
      return {...state, previewUrl}
    }
    default: {
      return state // Return the current state if the action type is unknown
    }
  }
}

export function clearTask(task: CommandTask, command?: string) {
  return {
    task,
    command: command ?? '',
    output: '',
    exitCode: null,
    channel: null,
    collapsed: true,
    loading: false,
    stopped: false,
    startTime: null,
    endTime: null,
  } as CommandResult
}

export function clearHistory(): Record<CommandTask, CommandResult> {
  return {
    [CommandTask.Build]: clearTask(CommandTask.Build),
    [CommandTask.Deploy]: clearTask(CommandTask.Deploy),
    [CommandTask.Commit]: clearTask(CommandTask.Commit),
  }
}
