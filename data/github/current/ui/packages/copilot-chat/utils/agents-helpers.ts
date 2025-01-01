import {useSyntheticChange} from '@github-ui/use-synthetic-change'
import {useQuery} from '@tanstack/react-query'
import {useCallback} from 'react'

import {findAgentCorrespondents} from './copilot-chat-helpers'
import type {CopilotChatAgent} from './copilot-chat-types'
import {useChatState} from './CopilotChatContext'
import {useChatManager} from './CopilotChatManagerContext'

export const AGENTS_MARKETPLACE_URL = 'https://github.com/marketplace?type=apps&copilot_app=true'
export const AGENT_PREFIX = '@'

/**
 * @param enabled Set to true when the agents list is rendered (ie, the menu is open). This enables lazy fetching. If
 * always true, will start fetching as soon as the consuming component is mounted.
 */
export function useAvailableAgents(enabled = true) {
  const {model, messages, agentsPath} = useChatState()
  const manager = useChatManager()

  const unsupportedModel = model?.hasLimitedCapabilities

  const selectAgents = useCallback(
    (agents: CopilotChatAgent[]) => {
      if (unsupportedModel) return {agents: [], showLimit: false}

      const previousAgent = findAgentCorrespondents(messages)[0]
      if (previousAgent)
        return {
          agents: agents.filter(agent => agent.slug === previousAgent.name),
          showLimit: true,
        }

      return {agents, showLimit: false}
    },
    [messages, unsupportedModel],
  )

  const {isLoading, data, refetch, isStale, isFetched} = useQuery({
    queryKey: ['copilot-chat', 'agents', agentsPath],
    queryFn: () => (agentsPath ? manager.fetchAgents(agentsPath) : []),
    select: selectAgents,
    enabled: enabled && !unsupportedModel,
  })

  /**
   * Imperatively fetch in a callback. This is not really how tanstack query is meant to be used but allows us to
   * lazily fetch when the button is clicked. We can delete this when we ship the unified attachment menu since we can
   * then just declaratively fetch when the menu is open.
   */
  const imperativelyFetch = async () => {
    if (!isFetched || isStale) {
      const result = await refetch()
      return result.data
    }
    return data
  }

  return {
    loading: isLoading,
    disabled: unsupportedModel,
    availableAgents: data?.agents,
    showLimit: data?.showLimit ?? false,
    imperativelyFetch,
  }
}

export interface UseInsertAgentProps {
  inputOnChange: React.ChangeEventHandler
  inputRef: React.RefObject<HTMLTextAreaElement>
}

/**
 * Returns a function that inserts an agent reference in the beginning of the target input.
 */
export function useInsertAgent({inputOnChange, inputRef}: UseInsertAgentProps) {
  const changeInput = useSyntheticChange({inputRef, fallbackEventHandler: inputOnChange})

  /**
   * @param agent The agent slug to insert. Leave blank to trigger autocomplete menu for user to select an agent.
   */
  return useCallback(
    (agent = '') => {
      if (inputRef.current?.value) changeInput(' ', [0, 0])
      const insertStr = `${AGENT_PREFIX}${agent}`
      changeInput(insertStr, [0, 0], insertStr.length)
    },
    [changeInput, inputRef],
  )
}
