import {sendEvent} from '@github-ui/hydro-analytics'
import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {SelectSuggestionsEvent, ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import type {DetailedHTMLProps, InputHTMLAttributes, ReactElement} from 'react'
import {useCallback, useEffect, useMemo, useState} from 'react'

import {AGENT_PREFIX, useAvailableAgents} from '../../utils/agents-helpers'
import {useChatState} from '../../utils/CopilotChatContext'
import {AgentSuggestion} from './AgentSuggestion'

export function AgentAutocomplete({
  children,
}: {
  children: ReactElement<DetailedHTMLProps<InputHTMLAttributes<HTMLTextAreaElement>, HTMLTextAreaElement>>
}) {
  const {mode} = useChatState()

  const [mounted, setMounted] = useState(() => typeof document !== 'undefined')
  useEffect(() => setMounted(true), [])

  const [showEvent, setShowEvent] = useState<ShowSuggestionsEvent | null>(null)
  const [suggestions, setSuggestions] = useState<Suggestion[]>([])

  const triggerChars = useMemo(() => [{triggerChar: AGENT_PREFIX, insertSpaceOnCommit: true}], [])

  const agents = useAvailableAgents(showEvent !== null)

  useEffect(() => {
    function updateSuggestions() {
      if (!showEvent) return

      const queryText = showEvent.query.toLowerCase()
      const matchesQuery = (item: string) => {
        const lc = item.toLowerCase()
        return lc.startsWith(queryText) && lc !== queryText
      }

      // Check for `@` first for agent suggestions
      // If ChatAutocomplete is enabled, we instead check for `@agent:`

      if (agents.disabled) setSuggestions([])
      if (agents.loading) setSuggestions(['loading'])
      if (queryText === '') {
        sendEvent('dotcom_chat.activate', {target: 'AGENT_COMMAND_MENU_TRIGGERED', mode})
      }

      const matchingAgents = agents.availableAgents?.filter(agent => matchesQuery(agent.slug)).slice(0, 10) ?? []

      setSuggestions(
        matchingAgents.map<Suggestion>(agent => ({
          value: agent.slug,
          key: agent.slug,
          render: p => <AgentSuggestion agent={agent} {...p} />,
        })),
      )
      return
    }

    if (!showEvent) {
      setSuggestions([])
    } else {
      // Set Loading State
      void updateSuggestions()
    }
  }, [agents.availableAgents, agents.disabled, agents.loading, agents.showLimit, mode, showEvent])

  const onShowSuggestions = useCallback((e: ShowSuggestionsEvent) => {
    setShowEvent(e)
  }, [])

  const onHideSuggestions = useCallback(() => {
    setShowEvent(null)
  }, [])

  if (!mounted) {
    return <div>{children}</div>
  }

  const onSelectSuggestion = ({suggestion}: SelectSuggestionsEvent) => {
    sendEvent('dotcom_chat.activate', {
      target: 'AGENT_COMMAND_MENU_ITEM_SELECTED',
      mode,
      suggestion: typeof suggestion === 'string' ? suggestion : suggestion.value,
    })
  }

  return (
    <InlineAutocomplete
      fullWidth
      suggestions={suggestions}
      triggers={triggerChars}
      tabInsertsSuggestions={false}
      onHideSuggestions={onHideSuggestions}
      onShowSuggestions={onShowSuggestions}
      onSelectSuggestion={onSelectSuggestion}
    >
      {children}
    </InlineAutocomplete>
  )
}
