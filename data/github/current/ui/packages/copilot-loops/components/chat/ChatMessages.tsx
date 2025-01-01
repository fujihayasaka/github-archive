import {Messages} from '@github-ui/copilot-chat/Chat'
import {ChatScrollContainer} from '@github-ui/copilot-chat/components/ChatScrollContainer'
import styles from './ChatMessages.module.css'
import {useRef} from 'react'
import {ChatInput} from './ChatInput'

interface ChatMessagesProps {
  isMobileView: boolean
}

export function ChatMessages({isMobileView}: ChatMessagesProps) {
  const inputRef = useRef<HTMLTextAreaElement>(null)
  return (
    <div className={styles.container}>
      <ChatScrollContainer disabled={isMobileView} className={styles.scrollContainer}>
        <Messages disableTopicPicker inputRef={inputRef} showQuotaExceededEmptyState={false} />
      </ChatScrollContainer>
      <div className={styles.input}>
        <ChatInput textAreaRef={inputRef} />
      </div>
    </div>
  )
}
