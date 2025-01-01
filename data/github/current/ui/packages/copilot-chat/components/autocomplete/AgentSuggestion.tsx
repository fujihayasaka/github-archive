import {GitHubAvatar} from '@github-ui/github-avatar'
import {ActionList, type ActionListItemProps} from '@primer/react'

import {AGENT_PREFIX} from '../../utils/agents-helpers'
import type {CopilotChatAgent} from '../../utils/copilot-chat-types'

interface AgentSuggestionProps extends ActionListItemProps {
  agent: CopilotChatAgent
}

export function AgentSuggestion({agent, ...props}: AgentSuggestionProps) {
  return (
    <ActionList.Item {...props}>
      <ActionList.LeadingVisual>
        <GitHubAvatar src={agent.avatarUrl} />
      </ActionList.LeadingVisual>
      {agent.name}
      <ActionList.Description variant="inline" truncate>
        {AGENT_PREFIX}
        {agent.slug}
      </ActionList.Description>
    </ActionList.Item>
  )
}
