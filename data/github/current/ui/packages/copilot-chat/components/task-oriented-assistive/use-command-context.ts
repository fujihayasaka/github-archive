import {useMemo} from 'react'

import type {RepositoryReference} from '../../utils/copilot-chat-types'
import {useChatState} from '../../utils/CopilotChatContext'

// TODO Reconcile this. The implicit-context response does not match copilot-chat-types
export interface PullRequestReference {
  type: 'pull-request'
  number: number
  persona: 'author' | 'reviewer' | 'other'
}

type GlobalContext = {
  type: 'global'
}

export type CommandContext = GlobalContext | RepositoryReference | PullRequestReference

export function useCommandContext(): CommandContext | undefined {
  const state = useChatState()
  const {context, currentRepository} = state

  return useMemo(() => {
    if (Array.isArray(context)) {
      const pullRequest = context.find(item => item.type === 'pull-request')
      if (pullRequest) {
        // The PullRequestReference type is not what actually comes back from the server
        // TODO https://github.com/github/copilot-productivity/issues/4035
        return pullRequest as unknown as PullRequestReference
      }
    }

    if (currentRepository) {
      return {type: 'repository', ...currentRepository}
    }

    return {type: 'global'}
  }, [context, currentRepository])
}
