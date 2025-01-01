import {createContext, useContext} from 'react'

import type {CommandId} from './commands'
import {dispatchGlobalCommand} from './components/GlobalCommands'

interface CommandsContext {
  /**
   * @param isLimitedScope Was this command originally caught by a `ScopedCommands.LimitedScope` wrapper?
   */
  triggerCommand: (id: CommandId, domEvent: KeyboardEvent | MouseEvent, isLimitedScope?: boolean) => void | false
  /** Notify the provider that these commands should have limited keybinding scope. */
  registerLimitedKeybindingScope: (uniqueKey: string, commands: CommandId[]) => void
}

const CommandsContext = createContext<CommandsContext>({
  triggerCommand(id, domEvent, isLimitedScope = false) {
    // Commands caught by `ScopedCommands.LimitedScope` should not trigger global events and should not `preventDefault`
    // if no handler is encountered for them
    if (isLimitedScope) return false
    // Without any scope context, we just emit a global event
    dispatchGlobalCommand(id, domEvent)
  },
  registerLimitedKeybindingScope: () => {},
})

export const CommandsContextProvider = CommandsContext.Provider

export const useCommandsContext = () => useContext(CommandsContext)
