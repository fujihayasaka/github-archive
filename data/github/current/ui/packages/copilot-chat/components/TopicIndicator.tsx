import {RepoIcon} from '@primer/octicons-react'
import {useRef} from 'react'

import type {Docset} from '../utils/copilot-chat-types'
import {useChatState, useChatStateLens} from '../utils/CopilotChatContext'
import {TopicIndicatorFlash} from './TopicIndicatorFlash'

export function TopicIndicator() {
  const {currentTopic} = useChatState()
  const docset = useChatStateLens(s => s.currentReferences.find(r => r.type === 'docset') as Docset | undefined)
  const topic = currentTopic ?? docset

  const removeButtonRef = useRef<HTMLButtonElement>(null)

  if (!topic) return null

  return <TopicIndicatorFlash icon={<RepoIcon />} topic={topic} removeButtonRef={removeButtonRef} />
}
