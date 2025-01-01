import {GitHubAvatar} from '@github-ui/github-avatar'
import {sendEvent} from '@github-ui/hydro-analytics'
import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import {ActionList} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type {DetailedHTMLProps, InputHTMLAttributes, ReactElement} from 'react'
import {useEffect, useMemo, useState} from 'react'

import {AGENT_PREFIX, useAvailableAgents} from '../utils/agents-helpers'
import {getSlashCommands, SLASH_COMMAND_PREFIX} from '../utils/copilot-slash-commands'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

export function Autocomplete({
  children,
  textAreaRef,
}: {
  children: ReactElement<DetailedHTMLProps<InputHTMLAttributes<HTMLTextAreaElement>, HTMLTextAreaElement>>
  textAreaRef: React.RefObject<HTMLTextAreaElement>
}) {
  const manager = useChatManager()
  const {mode} = useChatState()

  const [mounted, setMounted] = useState(() => typeof document !== 'undefined')
  useEffect(() => setMounted(true), [])

  const [showEvent, setShowEvent] = useState<ShowSuggestionsEvent | null>(null)

  const agents = useAvailableAgents(showEvent?.trigger.triggerChar === AGENT_PREFIX)

  const suggestions = useMemo((): Suggestion[] | 'loading' | null => {
    if (!showEvent) return null

    // Only allow autocompletion at the beginning of the input
    const text = textAreaRef.current?.value ?? ''
    const selectionStart = textAreaRef.current?.selectionStart ?? 0

    if (
      (text[0] ?? '') !== showEvent?.trigger.triggerChar ||
      (selectionStart > 1 && text[selectionStart - 2]?.match(/\s/))
    )
      return null

    const queryText = showEvent.query.toLowerCase()
    const matchesQuery = (item: string) => {
      const lc = item.toLowerCase()
      return lc.startsWith(queryText) && lc !== queryText
    }

    switch (showEvent.trigger.triggerChar) {
      case SLASH_COMMAND_PREFIX: {
        if (mode === 'immersive') return null
        if (queryText === '') {
          sendEvent('dotcom_chat.activate', {target: 'SLASH_COMMAND_MENU_TRIGGERED', mode})
        }
        const slashCommands = getSlashCommands({manager})
        const matchingCommands = slashCommands.filter(slashCommand => matchesQuery(slashCommand.command))

        return matchingCommands.map(slashCommand => ({
          value: slashCommand.command,
          key: slashCommand.command,
          render: $props => (
            <ActionList.Item
              key={slashCommand.label}
              {...$props}
              onSelect={() =>
                sendEvent('dotcom_chat.activate', {
                  target: 'SLASH_COMMAND_MENU_ITEM_SELECTED',
                  mode,
                  command: slashCommand.command,
                })
              }
            >
              <ActionList.LeadingVisual>
                <Octicon icon={slashCommand.icon} />
              </ActionList.LeadingVisual>
              <span className="text-normal">{slashCommand.label}</span>
              <ActionList.Description variant="inline" truncate>
                {SLASH_COMMAND_PREFIX}
                {slashCommand.command}
              </ActionList.Description>
            </ActionList.Item>
          ),
        }))
      }

      case AGENT_PREFIX: {
        if (agents.disabled) return null
        if (agents.loading) return 'loading'
        if (queryText === '') {
          sendEvent('dotcom_chat.activate', {target: 'AGENT_COMMAND_MENU_TRIGGERED', mode})
        }

        const matchingAgents = agents.availableAgents?.filter(agent => matchesQuery(agent.slug)).slice(0, 10) ?? []

        return matchingAgents.map(agent => ({
          value: agent.slug,
          key: agent.slug,
          render: $props => (
            <ActionList.Item
              key={agent.slug}
              {...$props}
              onSelect={() =>
                sendEvent('dotcom_chat.activate', {
                  target: 'AGENT_COMMAND_MENU_ITEM_SELECTED',
                  mode,
                  command: agent.slug,
                })
              }
            >
              <ActionList.LeadingVisual>
                <GitHubAvatar src={agent.avatarUrl} />
              </ActionList.LeadingVisual>
              {agent.name}
              <ActionList.Description variant="inline" truncate>
                {AGENT_PREFIX}
                {agent.slug}
              </ActionList.Description>
              {agents.showLimit && (
                <ActionList.Description variant="block">
                  You&apos;re limited to one agent per thread.
                </ActionList.Description>
              )}
            </ActionList.Item>
          ),
        }))
      }
    }

    return null
  }, [showEvent, textAreaRef, mode, manager, agents.disabled, agents.loading, agents.availableAgents, agents.showLimit])

  if (!mounted) {
    return <div>{children}</div>
  }

  return (
    <InlineAutocomplete
      fullWidth
      suggestions={suggestions}
      triggers={[{triggerChar: SLASH_COMMAND_PREFIX}, {triggerChar: AGENT_PREFIX}]}
      tabInsertsSuggestions={false}
      onHideSuggestions={() => setShowEvent(null)}
      onShowSuggestions={e => setShowEvent(e)}
    >
      {children}
    </InlineAutocomplete>
  )
}
