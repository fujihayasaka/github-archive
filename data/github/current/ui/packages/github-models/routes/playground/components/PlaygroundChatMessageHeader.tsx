import type {Model} from '@github-ui/marketplace-common'
import type {PlaygroundMessage} from '../../../types'
import {determineMessageMeta} from '../../../utils/message-meta'
import {PlaygroundChatAvatar} from './PlaygroundChatAvatar'
import type {User} from '@github-ui/use-user'
import {RelativeTime} from '@primer/react'
import styles from './PlaygroundChatMessage.module.css'
import {testIdProps} from '@github-ui/test-id-props'

export interface PlaygroundChatMessageHeaderProps {
  message: PlaygroundMessage
  model: Model
  currentUser: User | null
  isLoading: boolean
}

export function PlaygroundChatMessageHeader({
  message,
  model,
  currentUser,
  isLoading,
}: PlaygroundChatMessageHeaderProps) {
  const {avatarUrl, name} = determineMessageMeta(message, model, currentUser)
  return (
    <div className="d-flex gap-2 p-1" {...testIdProps('playground-chat-message-header')}>
      <PlaygroundChatAvatar isLoading={isLoading} messageRole={message.role} model={model} avatarUrl={avatarUrl} />
      <div className={`message-container ${styles.messageContainer}`}>
        <div className={styles.messageRowWrapper}>
          <div className={styles.messageRow}>
            <div className={styles.message}>
              <span className={styles.messageAuthor}>{name}</span>
              <span className={styles.messageText}>
                {message.role !== 'user' && isLoading ? (
                  'Responding...'
                ) : (
                  <RelativeTime {...testIdProps('message-timestamp')} date={message.timestamp} format="relative" />
                )}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
