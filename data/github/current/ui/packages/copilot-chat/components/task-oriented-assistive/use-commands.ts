import {useMemo} from 'react'

import {type Command, COMMANDS} from './commands'

export function useCommands(contextType?: string, persona?: string, filter?: string): Command[] {
  const commands = useMemo(() => {
    if (contextType === undefined) {
      return []
    }
    return (COMMANDS[contextType] || []).filter(command => {
      if (persona === undefined) {
        return true
      }
      if (!('persona' in command)) {
        return true
      }
      if (command.persona === undefined) {
        return true
      }
      return command.persona === persona
    })
  }, [contextType, persona])

  return useMemo(() => {
    const filteredCommands = commands.filter(command => {
      if (filter === undefined) {
        return true
      }
      // Simple starts-with case-insensitive filter for now
      return command.name.toLowerCase().startsWith(filter.toLowerCase())
    })

    // If there are no matches, append a custom command for the user's input
    if (filteredCommands.length === 0 && filter) {
      filteredCommands.push({
        type: 'custom',
        context: 'global',
        iconName: 'PaperAirplaneIcon',
        name: filter,
        prompt: filter,
      })
    }

    return filteredCommands
  }, [commands, filter])
}
