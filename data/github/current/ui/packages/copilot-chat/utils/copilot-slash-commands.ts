import {sendEvent} from '@github-ui/hydro-analytics'
import type {Icon} from '@primer/octicons-react'
import {PencilIcon, PlusIcon, TrashIcon} from '@primer/octicons-react'

import type {CopilotChatManager} from './copilot-chat-manager'
import type {CopilotChatState} from './copilot-chat-reducer'
import {getSelectedThread} from './get-selected-thread'

interface Params {
  manager: CopilotChatManager
}

export type SlashCommand = {
  action: (params: string, state: CopilotChatState) => Promise<void>
  label: string
  command: string // used for search
  requiresParams: boolean // Do not show in slash command menu
  icon: Icon
}

export const SLASH_COMMAND_PREFIX = '/'

export const getSlashCommands = ({manager}: Params): SlashCommand[] => {
  return [
    {
      label: 'Delete conversation',
      command: 'delete',
      icon: TrashIcon,
      requiresParams: false,
      action: async (params, state) => {
        manager.dispatch({type: 'SLASH_COMMANDS_LOADING'})
        try {
          const selectedThread = getSelectedThread(state)
          if (!selectedThread) throw new Error('Thread not found')
          await manager.deleteThread(selectedThread)
          sendEvent('dotcom_chat.activate', {target: 'SLASH_COMMAND_DELETE_THREAD', mode: state.mode})
          manager.dispatch({type: 'SLASH_COMMANDS_LOADED'})
        } catch {
          manager.dispatch({type: 'SLASH_COMMANDS_ERROR'})
        }
      },
    },
    {
      label: 'Rename conversation',
      command: 'rename',
      icon: PencilIcon,
      requiresParams: true,
      action: async (params, state) => {
        manager.dispatch({type: 'SLASH_COMMANDS_LOADING'})
        try {
          const selectedThread = getSelectedThread(state)
          if (!selectedThread) throw new Error('Thread not found')
          await manager.renameThread(selectedThread, params)
          sendEvent('dotcom_chat.activate', {target: 'SLASH_COMMAND_RENAME', mode: state.mode})
          manager.dispatch({type: 'SLASH_COMMANDS_LOADED'})
        } catch {
          manager.dispatch({type: 'SLASH_COMMANDS_ERROR'})
        }
      },
    },
    {
      label: 'Start a new conversation',
      command: 'new',
      icon: PlusIcon,
      requiresParams: false,
      action: async (params, state) => {
        manager.dispatch({type: 'SLASH_COMMANDS_LOADING'})
        try {
          await manager.selectThread(null)
          sendEvent('dotcom_chat.activate', {target: 'SLASH_COMMAND_NEW_THREAD', mode: state.mode})
          manager.dispatch({type: 'SLASH_COMMANDS_LOADED'})
        } catch {
          manager.dispatch({type: 'SLASH_COMMANDS_ERROR'})
        }
      },
    },
  ]
}

export const executePotentialSlashCommand = async (
  input: string,
  state: CopilotChatState,
  manager: CopilotChatManager,
): Promise<boolean> => {
  if ((input[0] ?? '') !== SLASH_COMMAND_PREFIX) return false
  // We know the first char is SLASH_COMMAND_PREFIX so we can safely remove it
  input = input.substring(1)

  const matchingCommands = getSlashCommands({manager}).filter(slashCommand => {
    const firstInputWord = (input.split(' ', 1)[0] ?? '').toLowerCase().trim()
    return slashCommand.command.toLowerCase().includes(firstInputWord)
  })

  if (matchingCommands.length !== 1) return false
  const matchingCommand = matchingCommands[0]!

  const params = input.substring(matchingCommand.command.length).trim()
  await matchingCommand.action(params, state)

  return true
}
