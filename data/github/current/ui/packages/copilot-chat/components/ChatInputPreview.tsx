import {testIdProps} from '@github-ui/test-id-props'
import {forwardRef, useEffect, useRef} from 'react'
import {unified} from 'unified'

import {useAvailableAgents} from '../utils/agents-helpers'
import {referenceID} from '../utils/copilot-chat-helpers'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {userMessageParser} from '../utils/user-message/user-message-parser'
import {getAllMentionedReferenceIds, hasPotentialAgentMention} from '../utils/user-message/user-message-utils'
import styles from './ChatInput.module.css'
import userMessageStyles from './UserMessage.module.css'

interface ChatInputPreviewProps {
  text: string
}

/**
 * This is displayed over the <textarea> for the ChatInput and is used to display rich text e.g. to highlight mentions
 * and references.
 */
export const ChatInputPreview = forwardRef<HTMLDivElement, ChatInputPreviewProps>(function ChatInputPreview(
  {text},
  ref,
) {
  // delay fetching agents until there is a potential mention
  const {availableAgents = []} = useAvailableAgents(hasPotentialAgentMention(text))

  const {currentReferences} = useChatState()
  const manager = useChatManager()

  const messageTree = unified()
    .use(userMessageParser, {references: currentReferences, agents: availableAgents})
    .parse(text)

  const mentionedReferences = getAllMentionedReferenceIds(messageTree)

  const previouslyMentionedReferences = useRef(mentionedReferences)
  useEffect(function removeReferencesForDeletedMentions() {
    for (const id of previouslyMentionedReferences.current)
      if (!mentionedReferences.has(id)) {
        const toRemove = currentReferences.find(r => referenceID(r) === id)
        if (toRemove) manager.removeReference(toRemove)
      }
    previouslyMentionedReferences.current = mentionedReferences
  })

  return (
    <div
      id="copilot-chat-textarea-preview"
      {...testIdProps('copilot-chat-input-textarea-preview')}
      aria-hidden
      className={styles.inputPreview}
      ref={ref}
      role="presentation"
    >
      {messageTree.children.map((node, i) => {
        switch (node.type) {
          case 'text':
            return node.value
          case 'reference-mention':
            return node.data.mentionedReferenceId !== undefined ? (
              <span className={userMessageStyles.mention} key={i} {...testIdProps('input-preview-ref')}>
                {node.value}
              </span>
            ) : (
              node.value
            )
          case 'agent-mention':
            return (
              <span className={userMessageStyles.mention} key={i}>
                {node.value}
              </span>
            )
        }
      })}
    </div>
  )
})
