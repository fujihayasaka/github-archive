import {createContext, useContext} from 'react'

import type {CommandId} from './commands'
import {dispatchGlobalCommand} from './components/GlobalCommands'

interface CommandsContext {
  triggerCommand: (id: CommandId, domEvent: KeyboardEvent | MouseEvent) => void | false
  /** Notify the provider that these commands should have limited keybinding scope. */
  registerLimitedKeybindingScope: (uniqueKey: string, commands: CommandId[]) => void
}

const CommandsContext = createContext<CommandsContext>({
  // Without any scope context, we just emit a global event
  triggerCommand: dispatchGlobalCommand,
  registerLimitedKeybindingScope: () => {},
})

export const CommandsContextProvider = CommandsContext.Provider

export const useCommandsContext = () => useContext(CommandsContext)
