import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {getSelectedThread} from '@github-ui/copilot-chat/utils/get-selected-thread'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {BrowserIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useEffect, useRef, useState} from 'react'
import {useLocation} from 'react-router-dom'

import type {CopilotImmersivePayload, Icebreaker} from '../../routes/payloads'
import DiceIcon from '../Icons/DiceIcon'
import styles from './EmptyState.module.css'

interface EmptyStateProps {
  isOpening: boolean
}

type IcebreakerType = 'functional' | 'instructional' | 'interactional'

interface IcebreakerData {
  type: IcebreakerType
  data: Icebreaker[]
}

function isIcebreakerDataArray(value: unknown): value is IcebreakerData[] {
  return Array.isArray(value) && value.every(item => 'type' in item && 'data' in item)
}

function getRandomIcebreaker(icebreakers: Icebreaker[]): Icebreaker {
  const randomIndex = Math.floor(Math.random() * icebreakers.length)
  const randomIcebreaker = icebreakers[randomIndex]
  if (!randomIcebreaker) {
    throw new Error('No icebreaker found')
  }
  return randomIcebreaker
}

export function EmptyState({isOpening}: EmptyStateProps) {
  const manager = useChatManager()
  const state = useChatState()
  const location = useLocation()
  const buttonRef = useRef<HTMLButtonElement>(null)

  const currentThread = getSelectedThread(state)
  const payload = useAppPayload<CopilotImmersivePayload>()

  const [interactionalSuggestions, setInteractionalSuggestions] = useState<Icebreaker[]>([])

  useEffect(() => {
    if (isIcebreakerDataArray(payload.icebreakers)) {
      const icebreakers = payload.icebreakers.find(ib => ib.type === 'interactional')
      if (icebreakers && icebreakers.data.length > 0) {
        setInteractionalSuggestions(icebreakers.data)
      }
    }
  }, [payload.icebreakers, location])

  // Focus the button when isOpening becomes true
  useEffect(() => {
    if (isOpening && buttonRef.current) {
      // Use requestAnimationFrame to ensure focus happens after render
      window.requestAnimationFrame(() => {
        buttonRef.current?.focus()
      })
    }
  }, [isOpening])

  const handleButtonClick = () => {
    if (interactionalSuggestions.length === 0) return

    const randomSuggestion = getRandomIcebreaker(interactionalSuggestions)
    const thread = state.messages.length === 0 ? currentThread : getSelectedThread(state)
    const currentUserLogin = state.currentUserLogin
    const message = randomSuggestion.message

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
      target: 'CONTENT_PREVIEW_EMPTY_STATE_ICEBREAKER_BUTTON',
      topic: state.currentTopic?.name,
      mode: 'immersive',
      suggestionId: randomSuggestion.id,
    })
  }

  return (
    <div className={styles.container}>
      <BrowserIcon size={24} className={styles.icon} />
      <h1 className="sr-only">Content preview panel</h1>
      <h2 className={styles.heading}>View files directly within Copilot</h2>
      <p className={styles.subtitle}>Ask to generate a file or app, or use the button below to try it yourself.</p>
      <Button ref={buttonRef} leadingVisual={DiceIcon} onClick={handleButtonClick} disabled={state.isWaitingOnCopilot}>
        I’m feeling lucky
      </Button>
    </div>
  )
}
