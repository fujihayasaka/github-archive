import {PublisherAvatar} from '../../../components/PublisherAvatar'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Spinner} from '@primer/react'
import styles from './PlaygroundChatAvatar.module.css'
import {testIdProps} from '@github-ui/test-id-props'
import type {Model} from '@github-ui/marketplace-common'

export interface PlaygroundChatAvatarProps {
  isLoading?: boolean
  avatarUrl: string
  messageRole: string
  model: Model
}

export function PlaygroundChatAvatar({isLoading, messageRole, model, avatarUrl}: PlaygroundChatAvatarProps) {
  const avatar =
    messageRole === 'assistant' || messageRole === 'error' ? (
      <PublisherAvatar
        square={false}
        logoUrl={model.logo_url}
        darkModeIcon={model.dark_mode_icon}
        publisher={model.publisher}
        size={24}
      />
    ) : (
      <GitHubAvatar src={avatarUrl} size={24} />
    )

  return (
    <div className="d-flex flex-items-center position-relative">
      {avatar}
      {isLoading && (
        <div className={styles.spinnerContainer} {...testIdProps('playground-avatar-spinner')}>
          <Spinner size="medium" className="fgColor-accent" />
        </div>
      )}
    </div>
  )
}
