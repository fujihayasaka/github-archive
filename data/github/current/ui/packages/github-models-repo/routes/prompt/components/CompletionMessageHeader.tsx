import {testIdProps} from '@github-ui/test-id-props'
import {useUser} from '@github-ui/use-user'
import {RelativeTime} from '@primer/react'
import type {RepoModel} from '../../../types'
import type {Message} from '../types'
import {determineMessageMeta} from '../utils/message-meta'
import styles from './CompletionMessage.module.css'
import {CompletionMessageAvatar} from './CompletionMessageAvatar'

export interface CompletionMessageHeaderProps {
  message: Message
  model: RepoModel
  isLoading: boolean
}

export function CompletionMessageHeader({message, model, isLoading}: CompletionMessageHeaderProps) {
  const {currentUser} = useUser()
  const {avatarUrl, name} = determineMessageMeta(message, model, currentUser)
  return (
    <div className="d-flex gap-2 p-1" {...testIdProps('completion-message-header')}>
      <CompletionMessageAvatar isLoading={isLoading} messageRole={message.role} model={model} avatarUrl={avatarUrl} />
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
