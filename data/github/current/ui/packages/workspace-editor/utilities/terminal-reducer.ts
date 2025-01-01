import type {ConnectedCodespaceData, TerminalTasks} from './workspace-editor-types'

export interface TerminalReducer {}

export type TerminalAction =
  | {
      type: 'TOGGLE_TERMINAL_VISIBILITY'
      terminalVisibility: TerminalVisibility
    }
  | ({type: 'UPDATE_COMMAND'; id: number} & Partial<CommandResult>)
  | {type: 'START_COMMAND'; command: CommandResult}
  | {type: 'TOGGLE_TERMINAL_PANE'; pane: Pane}
  | {type: 'COMPLETE_COMMAND'; exitCode: number; id: number}
  | {type: 'COLLAPSE_COMMAND'; id: number}
  | {type: 'EXPAND_COMMAND'; id: number}
  | {type: 'CLEAR_ALL'}
  | {type: 'SET_TASKS'; tasks: TerminalTasks}
  | {type: 'SET_CODESPACE_DATA'; codespaceData: ConnectedCodespaceData}
  | {type: 'SET_PREVIEW_URL'; previewUrl: string | undefined}

export type TerminalVisibility = 'visible' | 'hidden'
export type TerminalState = {
  terminalVisibility: TerminalVisibility
  pane: Pane
  currentCommand: CommandResult | null
  history: {[id: number]: CommandResult}
  tasks: TerminalTasks
  codespaceData: ConnectedCodespaceData
  previewUrl: string | undefined
}

type Channel = {
  stop: (signal: 'INT' | 'TERM') => void
}

export type CommandResult = {
  buildTask: string
  command: string
  exitCode: number | null
  output: string
  id: number
  collapsed: boolean
  channel: Channel | null
  loading: boolean
}
export type Pane = 'output' | 'terminal'

export function terminalReducer(state: TerminalState, action: TerminalAction): TerminalState {
  switch (action.type) {
    case 'TOGGLE_TERMINAL_VISIBILITY': {
      const {terminalVisibility} = action
      return {...state, terminalVisibility}
    }
    case 'TOGGLE_TERMINAL_PANE': {
      const {pane} = action
      return {...state, pane}
    }
    case 'COMPLETE_COMMAND': {
      const {currentCommand, history} = state
      const {id, exitCode} = action

      // The command may already be in history if we started a new command before the previous one finished
      let newCurrentCommand: CommandResult | null
      let commandToUpdate: CommandResult

      if (currentCommand?.id === id) {
        newCurrentCommand = null
        commandToUpdate = {...currentCommand}
      } else if (history[id]) {
        newCurrentCommand = currentCommand
        commandToUpdate = {...history[id]}
      } else {
        return state
      }

      const updatedCommand = {...commandToUpdate, exitCode, channel: null}
      const newHistory = {...history, [id]: updatedCommand}
      return {...state, history: newHistory, currentCommand: newCurrentCommand}
    }
    case 'START_COMMAND': {
      const {currentCommand} = state
      let history = {...state.history}

      // If there is another command in progress, move it to the history
      if (currentCommand) {
        history = {...history, [currentCommand.id]: currentCommand}
      }

      return {...state, history, currentCommand: action.command}
    }
    case 'UPDATE_COMMAND': {
      // Eat the type property from action so that it's not included in update
      const {type, id, ...update} = action

      if (id === state.currentCommand?.id) {
        return {...state, currentCommand: {...state.currentCommand, ...update}}
      }

      if (state.history[id]) {
        const command = {...state.history[id], ...update}
        const history = {...state.history, [id]: command}
        return {...state, history}
      }

      return state
    }
    case 'COLLAPSE_COMMAND': {
      return terminalReducer(state, {type: 'UPDATE_COMMAND', id: action.id, collapsed: true})
    }
    case 'EXPAND_COMMAND': {
      return terminalReducer(state, {type: 'UPDATE_COMMAND', id: action.id, collapsed: false})
    }
    case 'CLEAR_ALL': {
      return {
        ...state,
        currentCommand: null,
        history: {},
      }
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
