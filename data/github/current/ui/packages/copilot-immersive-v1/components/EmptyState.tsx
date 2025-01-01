import CopilotIconAnimation from '@github-ui/copilot-chat/components/CopilotIconAnimation'
import {LegalDisclaimer} from '@github-ui/copilot-chat/components/LegalDisclaimer'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {useEffect, useState} from 'react'

import type {CopilotImmersivePayload, Icebreaker} from '../routes/payloads'
import styles from './EmptyState.module.css'
import {SuggestionCard} from './SuggestionCard'

type IcebreakerType = 'functional' | 'instructional' | 'interactional'

interface IcebreakerData {
  type: IcebreakerType
  data: Icebreaker[]
}

function isIcebreakerDataArray(value: unknown): value is IcebreakerData[] {
  return Array.isArray(value) && value.every(item => 'type' in item && 'data' in item)
}

function getRandomIcebreakers(icebreakers: Icebreaker[], count: number): Icebreaker[] {
  const shuffled = icebreakers.sort(() => 0.5 - Math.random())
  return shuffled.slice(0, count)
}

export function EmptyState({showSuggestions}: {showSuggestions: boolean}) {
  const manager = useChatManager()
  const state = useChatState()

  const currentThread = manager.getSelectedThread(state)
  const payload = useAppPayload<CopilotImmersivePayload>()

  const [suggestions, setSuggestions] = useState<Icebreaker[]>([])

  useEffect(() => {
    if (isIcebreakerDataArray(payload.icebreakers)) {
      const functionalIcebreakers = payload.icebreakers.find(ib => ib.type === 'functional')
      if (functionalIcebreakers && functionalIcebreakers.data.length > 0) {
        const randomSuggestions: Icebreaker[] = getRandomIcebreakers(functionalIcebreakers.data, 6)
        setSuggestions(randomSuggestions)
      }
    }
  }, [payload.icebreakers])

  return (
    <div className={styles.container}>
      <CopilotIconAnimation hidden />
      {showSuggestions && (
        <div>
          <h1 className="sr-only">Copilot Chat</h1>
          <h2 className="sr-only">Sample prompts to try</h2>
          <ul className={`${styles.suggestions} list-style-none`}>
            {suggestions.map((suggestion: Icebreaker) => (
              <li key={suggestion.id} className={styles.suggestionButton}>
                <SuggestionCard
                  key={suggestion.id}
                  titleHtml={suggestion.titleHtml as SafeHTMLString}
                  icon={suggestion.icon}
                  color={suggestion.color}
                  onClick={() => {
                    const thread = state.messages.length === 0 ? currentThread : manager.getSelectedThread(state)
                    const currentUserLogin = state.currentUserLogin
                    const message = suggestion.message
                    void manager.sendChatMessage({
                      thread,
                      content: message.replaceAll('$$USERNAME$$', currentUserLogin),
                      references: state.currentReferences,
                      topic: state.currentTopic,
                      context: state.context,
                      customInstructions: state.customInstructions,
                      model: state.model,
                    })
                    sendEvent('dotcom_chat.activate', {
                      target: 'EMPTY_STATE_SUGGESTION_CARD',
                      topic: state.currentTopic?.name,
                      mode: 'immersive',
                      suggestionId: suggestion.id,
                    })
                  }}
                />
              </li>
            ))}
          </ul>
        </div>
      )}
      <div className={styles.legalText}>
        <LegalDisclaimer />
      </div>
    </div>
  )
}
