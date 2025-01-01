import {useEffect, useRef} from 'react'

import {isDocset, isRepository} from '../utils/copilot-chat-helpers'
import {CanIndexStatus, TopicIndexStatus, useReposIndexingState} from '../utils/copilot-chat-hooks'
import {useChatState} from '../utils/CopilotChatContext'

export default function TopicIndexedMessage() {
  const {currentTopic} = useChatState()

  const isTopicDocset = isDocset(currentTopic)
  const isTopicRepo = isRepository(currentTopic)

  let nwo = null
  if (currentTopic && isTopicRepo) {
    nwo = `${currentTopic.ownerLogin}/${currentTopic.name}`
  }
  const topicNwos = isTopicDocset ? currentTopic.repos : nwo ? [nwo] : []
  const [indexingState, triggerIndexing] = useReposIndexingState(topicNwos)

  const okToIndex =
    indexingState.requestStatus === CanIndexStatus.CanIndex &&
    ((isTopicRepo && indexingState.code === TopicIndexStatus.Unindexed) ||
      (isTopicDocset && indexingState.docs === TopicIndexStatus.Unindexed))

  const autoTriggeredIndexing = useRef(false)
  useEffect(
    function startIndexing() {
      const indexedState = isTopicDocset ? indexingState.docs : indexingState.code
      if (!autoTriggeredIndexing.current && indexedState === TopicIndexStatus.Unindexed && okToIndex) {
        autoTriggeredIndexing.current = true
        triggerIndexing()
      }
    },
    [indexingState.code, indexingState.docs, isTopicDocset, okToIndex, triggerIndexing],
  )

  // This shouldn't really be a component anymore
  return <></>
}
