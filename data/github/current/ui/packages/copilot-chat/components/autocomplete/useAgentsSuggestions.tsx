import type {Suggestion, Suggestions} from '@github-ui/inline-autocomplete/types'
import {TelescopeIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {useMemo} from 'react'

import {AGENTS_MARKETPLACE_URL, useAvailableAgents} from '../../utils/agents-helpers'
import {AgentSuggestion} from './AgentSuggestion'
import {LinkSuggestion} from './LinkSuggestion'

export interface AgentsQuery {
  category: 'agents'
  filter: string
}

export function useAgentsSuggestions(query: AgentsQuery | null) {
  const {availableAgents, loading, showLimit, disabled} = useAvailableAgents(query !== null)

  return useMemo<Suggestions | null>(() => {
    if (disabled || !query) return null

    if (loading && !availableAgents) return 'loading'

    return (
      availableAgents
        ?.filter(agent => query?.category === 'agents' && agent.name.toLowerCase().includes(query.filter.toLowerCase()))
        .map<Suggestion>(agent => ({
          value: `@${agent.slug}`,
          render: props => <AgentSuggestion agent={agent} {...props} />,
        }))
        .concat({
          value: null,
          key: `open-link:${AGENTS_MARKETPLACE_URL}`,
          render: props => (
            <>
              {availableAgents.length > 0 && <ActionList.Divider />}
              <LinkSuggestion
                leadingVisual={<TelescopeIcon />}
                {...props}
                inactiveText={showLimit ? 'Start a new conversation to use other extensions.' : undefined}
              >
                Marketplace
              </LinkSuggestion>
            </>
          ),
        }) ?? null
    )
  }, [disabled, query, loading, availableAgents, showLimit])
}
